"""Creator Studio logic: no network, no web framework (tested in test_studio_core.py).

What the backend does for the "Studio" screen of the app, all on the backend
machine so a big video never has to travel through the tunnel to the phone:
download a link, cut a video into parts, translate subtitles, put the
subtitles into the MP4 (soft CC) and upload to the user's OWN YouTube channel.

Nothing here changes how a video looks (no zoom, flip, colour or pitch): parts
are cut as they are, subtitles are added as a separate track.
"""
import re
from typing import Callable, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse

# ---- names and file kinds ---------------------------------------------------
_NAME_OK = re.compile(r"^[\w\-. ()က-႟]{1,120}$")
VIDEO_EXT = (".mp4", ".mov", ".webm", ".mkv", ".avi", ".flv", ".m4v")
AUDIO_EXT = (".mp3", ".m4a", ".wav", ".aac", ".ogg", ".opus")
SUB_EXT = (".srt",)


def safe_name(name: str) -> bool:
    """A plain file name (no folders, no '..'): the only kind the library serves or deletes."""
    n = name or ""
    return bool(_NAME_OK.match(n)) and not n.startswith(".") and ".." not in n and "/" not in n and "\\" not in n


def kind_of(name: str) -> str:
    low = (name or "").lower()
    if low.endswith(VIDEO_EXT):
        return "video"
    if low.endswith(AUDIO_EXT):
        return "audio"
    if low.endswith(SUB_EXT):
        return "srt"
    return "other"


def make_stem(title: str, fallback: str = "video") -> str:
    """A file name stem from a video title: letters (also Burmese / Chinese), digits, - and space."""
    t = re.sub(r"[^\w\-\sက-႟]", "_", title or "")
    t = re.sub(r"\s+", " ", t).strip(" ._")
    t = re.sub(r"_+", "_", t)
    return (t[:80].strip(" ._")) or fallback


def unique_name(stem: str, ext: str, existing) -> str:
    """stem.ext, or stem (2).ext, stem (3).ext ... when that name is taken."""
    have = set(existing)
    n = 1
    while True:
        cand = f"{stem}{'' if n == 1 else f' ({n})'}{ext}"
        if cand not in have:
            return cand
        n += 1


# ---- time and parts ---------------------------------------------------------
def parse_time(ts: str) -> Optional[float]:
    """'90', '1:30', '01:02:03', '1:30.5' -> seconds, None when it is not a time."""
    t = (ts or "").strip().replace(",", ".")
    if not t:
        return None
    parts = t.split(":")
    if len(parts) > 3:
        return None
    try:
        vals = [float(p) for p in parts]
    except ValueError:
        return None
    if any(v < 0 for v in vals):
        return None
    secs = 0.0
    for v in vals:
        secs = secs * 60 + v
    return secs


def fmt_time(sec: float) -> str:
    s = int(round(max(0.0, sec)))
    return f"{s // 3600:d}:{(s % 3600) // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60:d}:{s % 60:02d}"


MIN_PART_SECONDS = 1.0
MAX_PARTS = 60


def equal_parts(duration: float, count: int) -> List[Tuple[float, float]]:
    """[count] parts of the same length that cover the whole video. A part is
    never shorter than a second, so too many parts are reduced."""
    if duration < MIN_PART_SECONDS:
        return []
    n = max(1, min(int(count), MAX_PARTS, int(duration // MIN_PART_SECONDS)))
    step = duration / n
    return [(round(i * step, 3), round(duration if i == n - 1 else (i + 1) * step, 3)) for i in range(n)]


def parse_ranges(text: str, duration: float) -> Tuple[List[Tuple[float, float]], str]:
    """'0:00-5:00, 5:00-12:30' (commas or new lines) -> ([(start, end)], error).
    An end past the video is cut to its end. The error is Burmese, '' when fine."""
    items = [x.strip() for x in re.split(r"[,\n;]+", text or "") if x.strip()]
    if not items:
        return [], "အပိုင်းအချိန် မထည့်ရသေးဘူး (ဥပမာ 0:00-5:00, 5:00-12:30)"
    out: List[Tuple[float, float]] = []
    for it in items:
        pieces = re.split(r"\s*(?:-|–|—|~|to)\s*", it, maxsplit=1)
        if len(pieces) != 2:
            return [], f"'{it}' ပုံစံ မမှန်ဘူး (စ-ဆုံး ဥပမာ 0:00-5:00)"
        a, b = parse_time(pieces[0]), parse_time(pieces[1])
        if a is None or b is None:
            return [], f"'{it}' ထဲက အချိန် မမှန်ဘူး"
        if duration > 0:
            b = min(b, duration)
        if a >= duration > 0:
            return [], f"'{it}' က ဗီဒီယိုအရှည် ({fmt_time(duration)}) ထက် ကျော်နေတယ်"
        if b - a < MIN_PART_SECONDS:
            return [], f"'{it}' က တိုလွန်းတယ် (အနည်းဆုံး ၁ စက္ကန့်၊ စချိန်<ဆုံးချိန်)"
        out.append((a, b))
    if len(out) > MAX_PARTS:
        return [], f"အပိုင်း {MAX_PARTS} ခုထက် မများရ"
    return out, ""


# ---- SRT --------------------------------------------------------------------
Cue = Tuple[int, int, str]  # start ms, end ms, text
_TIME = re.compile(r"(\d+):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d+):(\d{2}):(\d{2})[,.](\d{1,3})")


def _ms(h, m, s, f) -> int:
    return ((int(h) * 60 + int(m)) * 60 + int(s)) * 1000 + int(str(f).ljust(3, "0")[:3])


def parse_srt(text: str) -> List[Cue]:
    cues: List[Cue] = []
    blocks = re.split(r"\n\s*\n", (text or "").lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n").strip())
    for b in blocks:
        lines = [ln for ln in b.split("\n")]
        for i, ln in enumerate(lines):
            m = _TIME.search(ln)
            if m:
                body = "\n".join(x.strip() for x in lines[i + 1:] if x.strip())
                if body:
                    cues.append((_ms(*m.groups()[:4]), _ms(*m.groups()[4:]), body))
                break
    return cues


# ---- speech to text (Whisper) -----------------------------------------------
WHISPER_MODELS = ("tiny", "base", "small", "medium", "large-v3")
_WHISPER_LANG = re.compile(r"^[a-z]{2,3}$")


def whisper_lang(code: str) -> Optional[str]:
    """'auto' / empty / anything odd -> None (Whisper finds the language); 'zh-CN' -> 'zh'."""
    c = (code or "").strip().lower()
    if c in ("", "auto"):
        return None
    c = c.split("-")[0].split("_")[0]
    return c if _WHISPER_LANG.match(c) else None


def whisper_model_name(name: str) -> str:
    return name if name in WHISPER_MODELS else "small"


def segments_to_cues(segments, min_ms: int = 400) -> List[Cue]:
    """Whisper segments (objects with start / end in seconds and text) -> SRT cues: empty text dropped, every cue at least
    min_ms long, and no two cues overlapping (the earlier one is shortened)."""
    out: List[Cue] = []
    for seg in segments:
        text = " ".join(str(getattr(seg, "text", "") or "").split())
        if not text:
            continue
        a = max(0, int(round(float(getattr(seg, "start", 0.0)) * 1000)))
        b = int(round(float(getattr(seg, "end", 0.0)) * 1000))
        if b < a + min_ms:
            b = a + min_ms
        if out and a < out[-1][1]:
            ps, pe, pt = out[-1]
            if a - ps >= 200:
                out[-1] = (ps, a, pt)
            else:
                a = pe
                if b < a + min_ms:
                    b = a + min_ms
        out.append((a, b, text))
    return out


def _stamp(ms: int) -> str:
    ms = max(0, int(ms))
    return f"{ms // 3600000:02d}:{(ms // 60000) % 60:02d}:{(ms // 1000) % 60:02d},{ms % 1000:03d}"


def serialize_srt(cues: List[Cue]) -> str:
    return "\n".join(f"{i}\n{_stamp(a)} --> {_stamp(b)}\n{t}\n" for i, (a, b, t) in enumerate(cues, 1))


def slice_srt(cues: List[Cue], start_s: float, end_s: float) -> List[Cue]:
    """The cues that overlap [start_s, end_s], moved so the part starts at 0."""
    a, b = int(start_s * 1000), int(end_s * 1000)
    out: List[Cue] = []
    for s, e, t in cues:
        if e <= a or s >= b:
            continue
        out.append((max(s, a) - a, min(e, b) - a, t))
    return out


# ---- translation ------------------------------------------------------------
def batches(texts: List[str], max_chars: int = 2800, max_items: int = 40) -> List[List[int]]:
    """Indexes of [texts] in groups that are not too long for one request."""
    out: List[List[int]] = []
    cur: List[int] = []
    size = 0
    for i, t in enumerate(texts):
        add = len(t) + 8
        if cur and (size + add > max_chars or len(cur) >= max_items):
            out.append(cur)
            cur, size = [], 0
        cur.append(i)
        size += add
    if cur:
        out.append(cur)
    return out


def numbered_prompt(texts: List[str], src_hint: str = "") -> str:
    lines = "\n".join(f"{i}|{t.replace(chr(10), ' / ')}" for i, t in enumerate(texts, 1))
    src = f" ({src_hint})" if src_hint and src_hint != "auto" else ""
    return (
        f"Translate these subtitle lines{src} into natural spoken Burmese (Myanmar Unicode). "
        "Keep every line short, keep names consistent, do not explain. "
        "Answer with exactly the same numbering, one line per input line, in the form `N|translation`, and nothing else.\n\n" + lines
    )


def parse_numbered_reply(reply: str, count: int) -> List[str]:
    """The `N|text` lines of an answer as a list of [count] texts; a line that is
    missing stays empty."""
    got: Dict[int, str] = {}
    last = 0
    for ln in (reply or "").replace("\r", "").split("\n"):
        m = re.match(r"^\s*`?(\d+)\s*[|:)]\s*(.*?)`?\s*$", ln)
        if m and 1 <= int(m.group(1)) <= count:
            last = int(m.group(1))
            got[last] = m.group(2).strip()
        elif last and ln.strip() and not re.match(r"^\s*\d+\s*[|:)]", ln):
            got[last] = (got[last] + " " + ln.strip()).strip()
    return [got.get(i, "") for i in range(1, count + 1)]


def translate_cues(cues: List[Cue], translate_many: Callable[[List[str]], List[str]], progress: Optional[Callable[[int, int], None]] = None) -> Tuple[List[Cue], int]:
    """Translates every cue. [translate_many] takes a few lines and answers the
    same number of lines. A group that fails, or answers a wrong count, is done
    line by line; a line that still fails keeps its original text. Returns the
    new cues and how many lines stayed untranslated."""
    texts = [c[2] for c in cues]
    out = list(texts)
    failed = 0
    groups = batches(texts)
    for gi, idxs in enumerate(groups):
        part = [texts[i] for i in idxs]
        res: Optional[List[str]] = None
        try:
            r = translate_many(part)
            if isinstance(r, list) and len(r) == len(part):
                res = r
        except Exception:
            res = None
        if res is None:
            res = []
            for t in part:
                try:
                    one = translate_many([t])
                    res.append(one[0] if one else "")
                except Exception:
                    res.append("")
        for i, tr in zip(idxs, res):
            tr = (tr or "").strip()
            if tr:
                out[i] = tr
            else:
                failed += 1
        if progress:
            progress(gi + 1, len(groups))
    return [(c[0], c[1], out[i]) for i, c in enumerate(cues)], failed


# ---- ffmpeg commands --------------------------------------------------------
def split_cmd(ff: str, src: str, start: float, dur: float, out: str, reencode: bool) -> List[str]:
    """One part, cut as it is. Stream copy is fast but cuts at the nearest key
    frame; re-encoding cuts exactly."""
    cmd = [ff, "-y", "-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", src]
    if reencode:
        cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
    else:
        cmd += ["-c", "copy", "-avoid_negative_ts", "make_zero", "-movflags", "+faststart"]
    return cmd + [out]


def mux_cc_cmd(ff: str, video: str, srt: str, out: str, lang: str = "mya") -> List[str]:
    """The subtitles as a separate (soft) track in the MP4; the picture and sound are copied untouched."""
    return [ff, "-y", "-i", video, "-i", srt, "-map", "0:v:0", "-map", "0:a?", "-map", "1:0", "-c:v", "copy", "-c:a", "copy",
            "-c:s", "mov_text", "-metadata:s:s:0", f"language={lang}", "-metadata:s:s:0", "title=Myanmar", "-disposition:s:0", "default",
            "-movflags", "+faststart", out]


# ---- YouTube ----------------------------------------------------------------
YT_CATEGORIES = {"film": "1", "entertainment": "24", "people": "22", "education": "27", "howto": "26", "news": "25", "music": "10", "gaming": "20"}
YT_PRIVACY = ("private", "unlisted", "public")


def format_title(template: str, name: str, idx: int, total: int) -> str:
    """{name}, {n}, {total} in the template; '<' and '>' are not allowed by YouTube; 100 characters at most."""
    t = (template or "{name}").replace("{name}", name).replace("{n}", str(idx)).replace("{total}", str(total))
    t = re.sub(r"[<>]", "", t).strip()
    t = t[:100].strip()
    return t or name[:100] or "video"


def clean_tags(text: str) -> List[str]:
    """Comma separated tags without '<' '>', all together under ~450 characters."""
    out, size = [], 0
    for raw in re.split(r"[,\n]+", text or ""):
        t = re.sub(r"[<>]", "", raw).strip()
        if not t or size + len(t) + 1 > 450:
            continue
        out.append(t)
        size += len(t) + 1
    return out


def clean_description(text: str) -> str:
    return re.sub(r"[<>]", "", text or "")[:4900]


def extract_oauth_code(pasted: str) -> str:
    """The `code` from the address the browser ended on after Google's login
    (http://localhost/?code=...&scope=...), or the pasted text itself when it is
    only the code."""
    t = (pasted or "").strip()
    if not t:
        return ""
    if "code=" in t:
        try:
            q = parse_qs(urlparse(t).query)
            if q.get("code"):
                return q["code"][0].strip()
        except ValueError:
            pass
        m = re.search(r"[?&]code=([^&\s#]+)", t)
        if m:
            return m.group(1)
    return t if re.fullmatch(r"[\w\-./]{10,}", t) else ""


def youtube_error_hint(message: str) -> str:
    low = (message or "").lower()
    if "quotaexceeded" in low or "quota" in low:
        return "YouTube API quota ပြည့်သွားပြီ (တစ်ရက် ဗီဒီယို ၆ ပုဒ်လောက်ပဲ ရတတ်တယ်) — မနက်ဖြန် ပြန်စမ်းပါ"
    if "uploadlimitexceeded" in low:
        return "ဒီ channel ရဲ့ တစ်ရက် upload အကန့်အသတ် ပြည့်သွားပြီ"
    if "invalid_grant" in low or "expired" in low or "revoked" in low:
        return "YouTube login သက်တမ်းကုန်သွားပြီ — Studio > YouTube မှာ ပြန် login ဝင်ပါ"
    if "forbidden" in low or "403" in low or "insufficient" in low:
        return "YouTube က ခွင့်မပြုဘူး (scope/ခွင့်ပြုချက် မလောက်ဘူး၊ ပြန် login ဝင်ပါ။ OAuth app က Testing ဖြစ်ရင် Test users ထဲ သင့် email ထည့်ထားရမယ်)"
    if "unauthorized" in low or "401" in low:
        return "YouTube login မမှန်တော့ဘူး — ပြန် login ဝင်ပါ"
    return ""


# ---- downloading ------------------------------------------------------------
# key -> (yt-dlp format, what it makes). "mp3" and "srt" are not video downloads.
QUALITIES = {
    "best": ("bestvideo+bestaudio/best", "video"),
    "1080": ("bestvideo[height<=1080]+bestaudio/best[height<=1080]/bestvideo+bestaudio/best", "video"),
    "1080hevc": ("bestvideo[height<=1080][vcodec^=hev]+bestaudio/bestvideo[height<=1080][vcodec^=hvc]+bestaudio/bestvideo[height<=1080]+bestaudio/best", "video"),
    "720": ("bestvideo[height<=720]+bestaudio/best[height<=720]/bestvideo+bestaudio/best", "video"),
    "480": ("bestvideo[height<=480]+bestaudio/best[height<=480]/best", "video"),
    "mp3": ("bestaudio/best", "audio"),
    "srt": ("", "subtitles"),
}
# download lines (aria2c connections); 1 = plain yt-dlp, the gentlest for sites that block fast downloads
SPEEDS = {"native": 1, "safe2": 2, "safe4": 4, "fast8": 8, "turbo16": 16}
KEEP_BILI_QUERY = {"p", "bvid", "aid", "oid", "sid", "season_id", "ep_id", "list_id", "mid"}
_URL_IN_TEXT = re.compile(r"https?://[^\s　\"'<>，。！？；、【】（）《》「」]+", re.I)


def host_of(url: str) -> str:
    try:
        return (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""


def is_short_bilibili(url: str) -> bool:
    return host_of(url) in ("b23.tv", "www.b23.tv", "bili2233.cn", "www.bili2233.cn")


def normalize_url(url: str) -> str:
    """Bilibili: the mobile / language-prefixed forms become the plain video page and only the
    query parts that pick a video are kept. Other sites are left as they are."""
    from urllib.parse import parse_qsl, urlencode, urlunparse

    try:
        u = urlparse(url)
    except ValueError:
        return url
    host = (u.hostname or "").lower()
    if not (host == "bilibili.com" or host.endswith(".bilibili.com")):
        return url
    if host in ("m.bilibili.com", "bilibili.com"):
        host = "www.bilibili.com"
    path = re.sub(r"^/(?:en|zh(?:-hans|-hant|-cn|-tw|-hk)?|ja|ko|th|vi|id|ms)(?=/(?:video|bangumi|list|medialist|cheese|festival|s/video)/)", "", u.path, flags=re.I)
    path = re.sub(r"^/s/video/", "/video/", path, flags=re.I)
    q = [(k, v) for k, v in parse_qsl(u.query, keep_blank_values=False) if k.lower() in KEEP_BILI_QUERY]
    return urlunparse((u.scheme or "https", host, path, "", urlencode(q), ""))


def extract_urls(text: str, resolve=None) -> List[str]:
    """Every address in [text] (one or many lines, share texts with words around the link),
    in order, without repeats. [resolve] turns a short Bilibili link into the real one."""
    out: List[str] = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        found = _URL_IN_TEXT.findall(line)
        if not found and re.fullmatch(r"(BV[0-9A-Za-z]+|av\d+)", line):
            found = ["https://www.bilibili.com/video/" + line]
        for u in found:
            u = u.rstrip(".,;!?)'\"")
            if not u:
                continue
            if resolve is not None and is_short_bilibili(u):
                try:
                    u = resolve(u) or u
                except Exception:
                    pass
            u = normalize_url(u)
            if u not in out:
                out.append(u)
    return out


def parse_playlist_items(text: str) -> Tuple[Optional[str], str]:
    """'4-7' or '4,6,8' (yt-dlp's own syntax: also 1:3 and -5:) -> (items, error). Empty text = all parts."""
    t = re.sub(r"\s+", "", text or "")
    if not t:
        return None, ""
    if not re.fullmatch(r"[0-9,\-:]+", t):
        return None, "အပိုင်းနံပါတ်ပုံစံ မမှန်ဘူး (ဥပမာ 4-7 သို့မဟုတ် 4,6,8)"
    if len(t) > 120:
        return None, "အပိုင်းနံပါတ် စာရင်း ရှည်လွန်းတယ်"
    return t, ""


def sub_langs(mode: str, has_youtube: bool = False) -> List[str]:
    """Which subtitle languages to ask for: auto / all / zh / en / my."""
    if mode == "all":
        return ["all", "-danmaku", "-live_chat"]
    if mode == "zh":
        return ["zh-Hans", "zh-CN", "zh-Hant", "zh-TW", "zh-HK", "zh.*", "zh"]
    if mode == "en":
        return ["en.*", "en"]
    if mode == "my":
        return ["my.*", "my"]
    if has_youtube:
        return ["en", "my", "zh-Hans", "zh-CN", "zh"]  # fewer requests: YouTube answers 429 to long lists
    return ["all", "-danmaku", "-live_chat"]


def aria2_args(connections: int) -> List[str]:
    n = max(1, min(16, int(connections)))
    return ["-x", str(n), "-s", str(n), "-k", "1M", "--file-allocation=none", "--summary-interval=0"]


def download_hint(log: str, platforms=None, has_cookie: bool = False, used_aria2c: bool = False, subtitles_only: bool = False) -> str:
    """What to try next, in Burmese, for an error text from yt-dlp (several hints possible)."""
    low = (log or "").lower()
    platforms = {str(x).lower() for x in (platforms or [])}
    out: List[str] = []
    if subtitles_only and ("subtitles are only available when logged in" in low or ("bilibili" in platforms and not has_cookie)):
        out.append("Bilibili က စာတန်းထိုး ဒေါင်းဖို့ login ဝင်ထားတဲ့ cookies.txt လိုတယ်")
    elif subtitles_only and not any(k in low for k in ("403", "404", "412", "429", "bot", "region")):
        out.append("ဒီဗီဒီယိုမှာ soft subtitle မပါတာ / ရွေးထားတဲ့ ဘာသာစကား မရှိတာ ဖြစ်နိုင်တယ်")
    if "sign in to confirm" in low or "not a bot" in low or "confirm you’re not a bot" in low:
        out.append("YouTube က Colab ကို bot လို့ထင်နေတယ် — cookies.txt ကို /content/cookies.txt မှာ တင်ပါ (Notebook Cell 5b)၊ ဒါမှမဟုတ် runtime ကို Disconnect and delete လုပ်ပြီး IP အသစ်ယူပါ")
    if "412" in low or "precondition failed" in low:
        out.append("Bilibili က Colab IP ကို ခေတ္တပိတ်ထားတယ် — runtime ပြန်စ (Disconnect and delete) ပြီး IP အသစ်နဲ့ ပြန်စမ်းပါ")
    if "403" in low or "aria2c exited" in low or "forbidden" in low:
        out.append("Server က ပိတ်ထားတယ်" + (" — 'ပုံမှန် yt-dlp (1 လိုင်း)' ကို ရွေးစမ်းပါ" if used_aria2c else ""))
    if "429" in low or "too many requests" in low:
        out.append("တောင်းဆိုမှု များလွန်းလို့ ခဏတားထားတယ် — ခဏနေ ပြန်စမ်းပါ")
    if "unsupported url" in low:
        out.append("ဒီ link ပုံစံကို မဖတ်တတ်ဘူး — ဗီဒီယိုစာမျက်နှာ link ကို တိုက်ရိုက်ထည့်ပါ")
    if "private" in low or "login required" in low or "members-only" in low:
        out.append("private / login လိုတဲ့ ဗီဒီယို — အများမြင်လို့ရတဲ့ link ထည့်ပါ (သို့) cookies.txt ထည့်ပါ")
    return " · ".join(out)


# ---- subtitles in the picture (hardsub) -------------------------------------
def escape_filter_path(p: str) -> str:
    """A file path inside an ffmpeg filter argument."""
    return str(p).replace("\\", "/").replace(":", "\\:").replace("'", "\\'").replace(",", "\\,").replace("[", "\\[").replace("]", "\\]")


def hardsub_cmd(ff: str, video: str, srt: str, out: str, font: str = "Padauk", size: int = 22, gpu: bool = False) -> List[str]:
    """The subtitles burned into the picture (cannot be switched off). Needs a
    re-encode; the font must be installed (Padauk for Burmese)."""
    font = re.sub(r"[^\w \-]", "", font or "Padauk") or "Padauk"
    size = max(10, min(60, int(size)))
    style = f"FontName={font},FontSize={size},PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=1,MarginV=24"
    vf = f"subtitles='{escape_filter_path(srt)}':force_style='{style}'"
    enc = ["-c:v", "h264_nvenc", "-preset", "p4", "-cq", "23"] if gpu else ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23"]
    return [ff, "-y", "-i", video, "-vf", vf] + enc + ["-c:a", "copy", "-movflags", "+faststart", out]
