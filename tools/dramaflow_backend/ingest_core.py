"""Link -> video, the logic with no network and no web framework.

The backend (main.py) downloads the video of a link the user gave (YouTube,
TikTok, Red Note ...) with yt-dlp, puts it into the user's OWN Gemini account
(Files API) and answers with the address Gemini needs. The download is a
private working copy on the backend; it is deleted after the upload. Nothing
here touches the network, so it is tested on its own (test_ingest_core.py).
"""
import ipaddress
import re
import socket
from typing import Callable, Optional, Tuple
from urllib.parse import urlparse

MAX_SECONDS = 3 * 3600  # longer than this is refused (disk and Gemini limits)
MAX_BYTES = 2 * 1024**3  # Gemini Files API accepts up to 2 GB per file
GEMINI_MIMES = {
    ".mp4": "video/mp4",
    ".mov": "video/mov",
    ".webm": "video/webm",
    ".avi": "video/avi",
    ".mpeg": "video/mpeg",
    ".mpg": "video/mpg",
    ".flv": "video/x-flv",
    ".wmv": "video/wmv",
    ".3gp": "video/3gpp",
}

# Subtitles that come with a video (only the ones the uploader made, not the
# machine captions). The first language in the list that exists wins.
SUB_LANGS = ["zh-Hans", "zh-CN", "zh", "zh-Hant", "zh-TW", "en", "my"]
MAX_SRT_CHARS = 300_000
SUB_SUFFIXES = (".srt", ".vtt", ".ass", ".ssa", ".ttml", ".json", ".json3", ".srv1", ".srv2", ".srv3", ".xml", ".lrc", ".txt")
MAX_COOKIE_BYTES = 400 * 1024
_COOKIE_DOMAINS = {
    "youtube": ("youtube.com", "google.com"),
    "tiktok": ("tiktok.com",),
    "rednote": ("xiaohongshu.com", "xhscdn.com"),
    "douyin": ("douyin.com",),
    "bilibili": ("bilibili.com",),
}

_URL = re.compile(r"https?://[^\s<>\"'“”‘’，。）)】」]+", re.I)


def extract_url(text: str) -> str:
    """The first web address in [text] (share texts from TikTok / Red Note
    carry words around the link). Empty when there is none."""
    m = _URL.search(text or "")
    return m.group(0).rstrip(".,;:!?]}'\"") if m else ""


def classify(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()

    def on(*names):
        return any(host == n or host.endswith("." + n) for n in names)

    if on("youtube.com", "youtu.be"):
        return "youtube"
    if on("tiktok.com"):
        return "tiktok"
    if on("xiaohongshu.com", "xhslink.com"):
        return "rednote"
    if on("douyin.com", "iesdouyin.com"):
        return "douyin"
    if on("bilibili.com", "b23.tv"):
        return "bilibili"
    return "other"


def cookies_problem(text: str) -> str:
    """"" when [text] looks like a Netscape cookies.txt (what yt-dlp reads),
    otherwise what is wrong, in Burmese."""
    t = (text or "").lstrip("\ufeff").strip()
    if not t:
        return "cookies.txt ဖိုင်က အလွတ်ဖြစ်နေတယ်"
    if len(t.encode("utf-8", "ignore")) > MAX_COOKIE_BYTES:
        return "cookies.txt ဖိုင် ကြီးလွန်းတယ် (400 KB ထက် မကျော်ရ)"
    if t.startswith(("{", "[")):
        return "cookies.txt က JSON ပုံစံဖြစ်နေတယ် — Extension မှာ Netscape format ရွေးပြီး ပြန်ထုတ်ပါ"
    rows = 0
    for ln in t.splitlines():
        ln = ln.strip()
        if not ln or (ln.startswith("#") and not ln.startswith("#HttpOnly_")):
            continue
        if len(ln.split("\t")) >= 7:
            rows += 1
    if rows == 0:
        return "cookies.txt ထဲမှာ cookie တစ်ကြောင်းမှ မတွေ့ဘူး (Netscape format ဖြစ်ရမယ်၊ tab နဲ့ ခြားထားတာ)"
    return ""


def cookie_note(text: str, kind: str) -> str:
    """A warning when the cookies are not for the website of the link ("" if fine or unknown)."""
    want = _COOKIE_DOMAINS.get(kind)
    if not want:
        return ""
    low = (text or "").lower()
    if any(d in low for d in want):
        return ""
    return "cookies.txt ထဲမှာ ဒီ website (%s) ရဲ့ cookie မတွေ့ဘူး" % want[0]


def pick_subtitle(names) -> Tuple[Optional[str], str]:
    """From the files a download left (v.zh-Hans.srt, v.en.srt ...) the best
    subtitle: Chinese first, then English, Burmese, then anything. Danmaku /
    live chat are not subtitles. Returns (file name, language) or (None, "")."""
    best = None
    for n in names:
        m = re.fullmatch(r"v\.(.+)\.srt", n or "", re.I)
        if not m:
            continue
        lang = m.group(1)
        if re.search(r"danmaku|live_chat", lang, re.I):
            continue
        if lang in SUB_LANGS:
            rank = SUB_LANGS.index(lang)
        elif lang.lower().startswith("zh"):
            rank = len(SUB_LANGS)
        else:
            rank = len(SUB_LANGS) + 1
        key = (rank, lang)
        if best is None or key < best[0]:
            best = (key, n, lang)
    return (best[1], best[2]) if best else (None, "")


def clean_srt(text: str) -> str:
    """The subtitle text when it looks like an SRT and is not huge, else ""."""
    t = (text or "").lstrip("\ufeff").strip()
    if "-->" not in t or len(t) > MAX_SRT_CHARS:
        return ""
    return t


def check_url(url: str, resolve: Callable = socket.getaddrinfo) -> Tuple[bool, str]:
    """Only public http(s) addresses. The backend runs on a shared machine, so
    addresses that point inside it (localhost, private networks) are refused."""
    try:
        u = urlparse((url or "").strip())
    except ValueError:
        return False, "link ပုံစံ မမှန်ဘူး"
    if u.scheme not in ("http", "https") or not u.hostname:
        return False, "http:// သို့မဟုတ် https:// နဲ့စတဲ့ link ထည့်ပါ"
    host = u.hostname
    try:
        ips = [ipaddress.ip_address(host)]
    except ValueError:
        try:
            ips = [ipaddress.ip_address(info[4][0]) for info in resolve(host, None)]
        except Exception:
            return False, "link ရဲ့ website ကို ရှာမတွေ့ဘူး (စာလုံးပေါင်း စစ်ပါ)"
    for ip in ips:
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast or ip.is_unspecified:
            return False, "ဒီ link က အများသုံး website မဟုတ်ဘူး"
    return True, ""


def mime_for(path: str) -> Optional[str]:
    m = re.search(r"(\.[A-Za-z0-9]+)$", path or "")
    return GEMINI_MIMES.get(m.group(1).lower()) if m else None


def parse_ffmpeg_duration(stderr: str) -> int:
    """Milliseconds from the 'Duration: 00:12:34.56' line of `ffmpeg -i`. 0 if none."""
    m = re.search(r"Duration:\s*(\d+):(\d{2}):(\d{2})(?:\.(\d+))?", stderr or "")
    if not m:
        return 0
    h, mi, s = int(m.group(1)), int(m.group(2)), int(m.group(3))
    frac = int((m.group(4) or "0").ljust(3, "0")[:3])
    return ((h * 60 + mi) * 60 + s) * 1000 + frac


def ingest_hint(message: str, kind: str = "other", has_cookies: bool = False) -> str:
    """What to do next, in Burmese, for an error from the download or the upload."""
    low = (message or "").lower()
    if "sign in to confirm" in low or "not a bot" in low:
        if has_cookies:
            return ("cookies.txt ထည့်ထားပေမဲ့ YouTube က ဆက်တားနေတယ် — cookie သက်တမ်းကုန်နေနိုင်တယ်။ Chrome မှာ YouTube ကို login ဝင်ထားပြီး "
                    "cookies.txt ကို အသစ်ပြန်ထုတ်ပြီး Colab ထဲ ပြန်တင်ပါ (Colab runtime ကိုလည်း ပြန်စကြည့်ပါ)")
        return ("YouTube က Colab ကို 'robot မဟုတ်ကြောင်း အတည်ပြုပါ' လို့ တားထားတယ် — ဖြေရှင်းနည်း: Chrome မှာ YouTube ကို login ဝင်ပြီး "
                "cookies.txt (Netscape format) ထုတ်၊ Colab ရဲ့ ဘယ်ဘက် Files ထဲ /content/cookies.txt အဖြစ် တင်ပြီး ပြန်စမ်းပါ။ "
                "(ဒါမှမဟုတ် ခဏနေစမ်း / runtime ပြန်စ / ဗီဒီယိုဖိုင်ကို ပုံမှန်အတိုင်း ရွေးပါ)")
    if "private" in low or "login" in low or "log in" in low or "members-only" in low or "members only" in low:
        return "ဒီဗီဒီယိုက private / login လိုတယ် — အများမြင်လို့ရတဲ့ link ကို ထည့်ပါ"
    if "unsupported url" in low:
        return "ဒီ link ပုံစံကို မဖတ်တတ်ဘူး — ဗီဒီယိုစာမျက်နှာ တိုက်ရိုက် link ကို share ကနေ ပြန်ကူးပါ (channel/profile link မဟုတ်ရ)"
    if "video unavailable" in low or "has been removed" in low or "not available" in low or "404" in low:
        return "ဗီဒီယို မရှိတော့ဘူး / ဒီနိုင်ငံမှာ မရဘူး (link မှန်လား စစ်ပါ)"
    if "429" in low or "too many requests" in low or "403" in low or "forbidden" in low:
        hint = "website က Colab ကို ခဏ တားထားတယ် — ခဏနေ ပြန်စမ်းပါ"
        if kind in ("tiktok", "rednote", "douyin"):
            hint += " (ဒီ website တွေက တားလေ့ရှိတယ်၊ မရရင် ဗီဒီယိုဖိုင်ကို ရွေးတင်ပါ)"
        return hint
    if "ဖိုင် ကြီး" in (message or "") or "larger than" in low or "max-filesize" in low:
        return "ဗီဒီယိုက ကြီးလွန်းတယ် (၂ GB ကျော်)"
    if "user location" in low or "location is not supported" in low:
        return "Colab ရှိတဲ့ နေရာကို Google က မခွင့်ပြုဘူး — Colab runtime ကို ဖျက်ပြီး ပြန်စပါ"
    if "api key" in low or "permission" in low or "401" in low:
        return "Gemini key မှန်လား၊ Gemini API ဖွင့်ထားလား စစ်ပါ"
    return ""


def run_ingest(
    url: str,
    download: Callable[[str, Callable[[int], None]], dict],
    upload: Callable[[str, str], Tuple[str, str]],
    progress: Callable[[str, int], None],
) -> dict:
    """download(url, on_percent) -> {"path", "title", "duration_ms"};
    upload(path, mime) -> (file_uri, mime). Returns what the app needs."""
    ok, why = check_url(url)
    if not ok:
        raise ValueError(why)
    kind = classify(url)
    progress("ဗီဒီယို ဆွဲနေတယ်", 5)
    got = download(url, lambda pct: progress("ဗီဒီယို ဆွဲနေတယ် %d%%" % max(0, min(100, pct)), 5 + int(max(0, min(100, pct)) * 0.55)))
    path = got["path"]
    mime = mime_for(path)
    if not mime:
        raise ValueError("ဒီဗီဒီယိုပုံစံ (%s) ကို Gemini က မလက်ခံဘူး" % (path.rsplit(".", 1)[-1] if "." in path else "?"))
    progress("Gemini ဆီ တင်နေတယ်", 62)
    uri, mime = upload(path, mime)
    progress("ပြီးပြီ", 100)
    out = {
        "file_uri": uri,
        "mime": mime,
        "duration_ms": int(got.get("duration_ms") or 0),
        "title": str(got.get("title") or "")[:120],
        "source": kind,
        "cookies": bool(got.get("cookies")),
    }
    srt = clean_srt(got.get("srt") or "")
    if srt:  # the uploader's own subtitles: the app can use them instead of paying for speech-to-text
        out["srt"] = srt
        out["srt_lang"] = str(got.get("srt_lang") or "")[:20]
    return out
