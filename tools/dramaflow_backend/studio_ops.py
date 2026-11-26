"""Creator Studio operations (download, split, translate, subtitles, zip, YouTube).

main.py only gives these functions a request and an [Env] (where the library
folder is, how to report progress, whether the user pressed cancel / pause).
yt-dlp, ffmpeg and the Google libraries are used here, imported only when
needed, so the backend still starts without them. The logic that needs no
network is in studio_core.py.
"""
import base64
import json
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import Callable, List, Optional

import studio_core as sc
from ingest_core import check_url, classify, cookie_note, cookies_problem, cookies_source, parse_ffmpeg_duration

MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # small files from the phone (subtitles, thumbnails); videos never travel this way
MIN_FREE_BYTES = 1024**3
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
MIME = {".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm", ".mkv": "video/x-matroska", ".avi": "video/x-msvideo",
        ".flv": "video/x-flv", ".m4v": "video/mp4"}
KEEP_EXT = sc.VIDEO_EXT + sc.AUDIO_EXT + sc.SUB_EXT
RAW_SUB_EXT = (".vtt", ".ass", ".ssa", ".ttml", ".srv1", ".srv2", ".srv3", ".json3", ".bcc", ".xml", ".lrc")
TEMP_SUFFIX = (".part", ".ytdl", ".aria2", ".temp", ".tmp")
SLOW_SITES = {"youtube", "tiktok", "rednote", "bilibili", "douyin"}  # these block fast multi-line downloads (403): plain yt-dlp is used


class Canceled(BaseException):
    """Raised inside a download hook / loop; BaseException so yt-dlp does not swallow it."""


class Env:
    def __init__(self, lib: Path, ffmpeg: str, progress: Callable[[str, int], None], canceled: Callable[[], bool],
                 paused: Callable[[], bool] = lambda: False, detail: Callable[..., None] = lambda **k: None,
                 gemini_many: Optional[Callable[[List[str], str], List[str]]] = None):
        self.lib, self.ffmpeg, self.progress, self.canceled, self.paused, self.detail, self.gemini_many = lib, ffmpeg, progress, canceled, paused, detail, gemini_many

    def check(self):
        if self.canceled():
            raise Canceled()


def kind(name: str) -> str:
    low = (name or "").lower()
    return "image" if low.endswith(IMAGE_EXT) else sc.kind_of(name)


# ---- the library ------------------------------------------------------------
def list_library(lib: Path) -> List[dict]:
    out = []
    try:
        entries = list(lib.iterdir())
    except OSError:
        return []
    for f in entries:
        if not f.is_file() or not sc.safe_name(f.name):
            continue
        try:
            st = f.stat()
        except OSError:
            continue
        out.append({"name": f.name, "size": st.st_size, "kind": kind(f.name) if kind(f.name) != "other" else ("zip" if f.name.lower().endswith(".zip") else "other"), "mtime": int(st.st_mtime)})
    return sorted(out, key=lambda d: -d["mtime"])


def file_path(lib: Path, name: str, want=None) -> Path:
    """The path of a library file, or ValueError (Burmese) when the name is not a plain existing file."""
    if not sc.safe_name(name or ""):
        raise ValueError("ဖိုင်နာမည် မမှန်ဘူး")
    p = lib / name
    if not p.is_file():
        raise ValueError(f"'{name}' ဖိုင် မတွေ့ဘူး (Library ထဲ မရှိတော့ဘူး)")
    if want and kind(name) not in want:
        raise ValueError(f"'{name}' က {'/'.join(want)} ဖိုင် မဟုတ်ဘူး")
    return p


def save_upload(lib: Path, name: str, data_b64: str) -> str:
    """A small file from the phone (subtitles, a thumbnail) into the library. Returns the stored name."""
    if not sc.safe_name(name or "") or kind(name) not in ("srt", "image"):
        raise ValueError("စာတန်း (.srt) သို့မဟုတ် ပုံ (.jpg/.png) ဖိုင်ပဲ တင်လို့ရတယ်")
    try:
        raw = base64.b64decode(data_b64 or "", validate=False)
    except Exception:
        raise ValueError("ဖိုင်ဒေတာ မဖတ်နိုင်ဘူး")
    if not raw:
        raise ValueError("ဖိုင် အလွတ်ဖြစ်နေတယ်")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise ValueError("ဖိုင်ကြီးလွန်းတယ် (8 MB ထက် မကျော်ရ)")
    lib.mkdir(parents=True, exist_ok=True)
    stem, ext = os.path.splitext(name)
    final = sc.unique_name(sc.make_stem(stem), ext.lower(), [f.name for f in lib.iterdir()])
    (lib / final).write_bytes(raw)
    return final


def delete_file(lib: Path, name: str):
    file_path(lib, name).unlink()


def free_ok(lib: Path):
    try:
        if shutil.disk_usage(lib).free < MIN_FREE_BYTES:
            raise ValueError("Backend ရဲ့ disk နေရာ မလောက်တော့ဘူး (၁ GB အောက်) — Library ထဲက ဖိုင်တွေ ဖျက်ပါ")
    except OSError:
        pass


def has_nvenc(ffmpeg: str) -> bool:
    try:
        if "h264_nvenc" not in subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, timeout=10).stdout:
            return False
        return subprocess.run(["nvidia-smi"], capture_output=True, timeout=10).returncode == 0
    except Exception:
        return False


# ---- running ffmpeg ---------------------------------------------------------
def run_ffmpeg(env: Env, cmd: List[str], timeout: int = 6 * 3600):
    """ffmpeg that stops when the user cancels. Raises RuntimeError with the end of ffmpeg's message."""
    cmd = [cmd[0], "-hide_banner", "-loglevel", "error"] + cmd[1:]
    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    started = time.time()
    err = ""
    while True:
        try:
            _, err = p.communicate(timeout=0.5)
            break
        except subprocess.TimeoutExpired:
            if env.canceled():
                p.kill()
                p.communicate()
                raise Canceled()
            if time.time() - started > timeout:
                p.kill()
                p.communicate()
                raise RuntimeError("ffmpeg အချိန်ကြာလွန်းလို့ ရပ်လိုက်တယ်")
    if p.returncode != 0:
        raise RuntimeError("ffmpeg မအောင်မြင်ဘူး: " + (err or "").strip()[-300:])


def duration_ms(env: Env, path: Path) -> int:
    try:
        p = subprocess.run([env.ffmpeg, "-i", str(path)], capture_output=True, text=True, timeout=60)
        return parse_ffmpeg_duration(p.stderr)
    except Exception:
        return 0


# ---- download ---------------------------------------------------------------
def _resolve_short(url: str) -> str:
    ok, _ = check_url(url)
    if not ok:
        return url
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0"})
        with urllib.request.urlopen(req, timeout=8) as r:
            return r.geturl() or url
    except Exception:
        return url


_NAME_RE = re.compile(r"^(?P<title>.*) \[(?P<id>[^\]]+)\](?:\.(?P<lang>[\w\-]+))?\.(?P<ext>[A-Za-z0-9]+)$")


def final_name(raw_name: str, existing) -> str:
    """'<title> [id].mp4' / '<title> [id].zh-Hans.srt' -> a clean library name."""
    m = _NAME_RE.match(raw_name)
    if m:
        stem, ext, lang = sc.make_stem(m.group("title")), "." + m.group("ext").lower(), m.group("lang")
        if lang and ext == ".srt":
            return sc.unique_name(stem + "." + lang, ext, existing)
        return sc.unique_name(stem, ext, existing)
    base, ext = os.path.splitext(raw_name)
    return sc.unique_name(sc.make_stem(base), ext.lower(), existing)


def op_download(env: Env, req) -> dict:
    try:
        import yt_dlp
    except Exception:
        raise RuntimeError("yt-dlp မတပ်ရသေးဘူး (Colab Cell 1 ကို ပြန် run ပါ)")
    quality = req.quality if req.quality in sc.QUALITIES else "720"
    fmt, what = sc.QUALITIES[quality]
    urls = sc.extract_urls(req.url, resolve=_resolve_short)
    if not urls:
        raise ValueError("Link မတွေ့ဘူး (http:// သို့မဟုတ် https:// နဲ့ စတဲ့ link ထည့်ပါ)")
    if len(urls) > 30:
        raise ValueError("Link 30 ခုထက် မများရ")
    for u in urls:
        ok, why = check_url(u)
        if not ok:
            raise ValueError(f"{u[:60]} — {why}")
    items, err = sc.parse_playlist_items(getattr(req, "playlist_items", ""))
    if err:
        raise ValueError(err)
    free_ok(env.lib)
    env.lib.mkdir(parents=True, exist_ok=True)
    kinds = {classify(u) for u in urls}
    conns = sc.SPEEDS.get(getattr(req, "speed", "safe4"), 4)
    use_aria2c = bool(shutil.which("aria2c")) and conns > 1 and what == "video" and not (kinds & SLOW_SITES)
    langs = sc.sub_langs(getattr(req, "sub_langs", "auto"), "youtube" in kinds)
    want_subs = what == "subtitles" or bool(getattr(req, "subtitles", False))
    result = {"files": [], "notes": [], "errors": []}
    src = cookies_source()
    cookie_text = ""
    if src is not None:
        cookie_text = src.read_text(encoding="utf-8", errors="ignore")
        bad = cookies_problem(cookie_text)
        if bad:
            raise ValueError(bad)
        result["notes"].append("cookies.txt သုံးထားတယ်")
        for u in urls:
            note = cookie_note(cookie_text, classify(u))
            if note:
                result["notes"].append(note)
    if use_aria2c:
        result["notes"].append(f"aria2c {conns} လိုင်းနဲ့ ဆွဲတယ်")
    elif conns > 1 and what == "video" and (kinds & SLOW_SITES):
        result["notes"].append("YouTube/TikTok/Red Note/Bilibili မှာ 403 မဖြစ်အောင် ပုံမှန် yt-dlp (1 လိုင်း) နဲ့ ဆွဲတယ်")

    for ui, url in enumerate(urls, 1):
        env.check()
        tmp = env.lib / f".tmp_{int(time.time())}_{ui}"
        tmp.mkdir(parents=True, exist_ok=True)
        log: List[str] = []

        class Quiet:
            def debug(self, m):
                pass

            def info(self, m):
                pass

            def warning(self, m):
                log.append(str(m))

            def error(self, m):
                log.append(str(m))

        def hook(d, ui=ui):
            while env.paused():
                env.check()
                env.detail(paused=True)
                time.sleep(0.5)
            env.check()
            if d.get("status") == "downloading":
                tot = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                got = d.get("downloaded_bytes") or 0
                pct = int(100 * got / tot) if tot else 0
                env.detail(paused=False, downloaded_mb=round(got / 1048576, 1), total_mb=round(tot / 1048576, 1), speed_mbs=round((d.get("speed") or 0) / 1048576, 2),
                           eta=d.get("eta"), file=os.path.basename(d.get("filename") or ""), fragment=(f"{d.get('fragment_index')}/{d.get('fragment_count')}" if d.get("fragment_count") else ""))
                env.progress(f"ဆွဲနေတယ် ({ui}/{len(urls)}) {pct}%" if tot else f"ဆွဲနေတယ် ({ui}/{len(urls)})", min(95, int(100 * (ui - 1 + (pct / 100 if tot else 0.0)) / len(urls))))

        opts = {
            "outtmpl": str(tmp / "%(title).80s [%(id)s].%(ext)s"),
            "windowsfilenames": True,
            "noplaylist": not bool(getattr(req, "playlist", False)),
            "quiet": True,
            "no_warnings": True,
            "logger": Quiet(),
            "socket_timeout": 30,
            "retries": 5,
            "fragment_retries": 5,
            "ffmpeg_location": env.ffmpeg,
            "progress_hooks": [hook],
            "ignoreerrors": False,
        }
        if items:
            opts["playlist_items"] = items
        if what == "video":
            opts["format"] = fmt
            opts["merge_output_format"] = "mp4"
        elif what == "audio":
            opts["format"] = fmt
            opts["postprocessors"] = [{"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"}]
        else:
            opts["skip_download"] = True
        if want_subs:
            opts.update({"writesubtitles": True, "subtitleslangs": langs, "subtitlesformat": "srt/best"})
            if what == "subtitles" and getattr(req, "auto_subs", False):
                opts["writeautomaticsub"] = True
            opts.setdefault("postprocessors", []).append({"key": "FFmpegSubtitlesConvertor", "format": "srt", "when": "before_dl"})
        if use_aria2c:
            opts["external_downloader"] = {"default": "aria2c"}
            opts["external_downloader_args"] = {"aria2c": sc.aria2_args(conns)}
        if src is not None:
            ck = tmp / "cookies.txt"  # a private copy: yt-dlp writes to its cookie file
            ck.write_text(cookie_text, encoding="utf-8")
            try:
                os.chmod(ck, 0o600)
            except OSError:
                pass
            opts["cookiefile"] = str(ck)
        try:
            env.progress(f"ဆွဲမယ် ({ui}/{len(urls)})", int(100 * (ui - 1) / len(urls)) + 1)
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.extract_info(url, download=True)
            made = 0
            for f in sorted(tmp.iterdir()):
                if f.name == "cookies.txt" or f.name.endswith(TEMP_SUFFIX) or not f.is_file():
                    continue
                low = f.name.lower()
                if low.endswith(RAW_SUB_EXT) or re.search(r"\.(danmaku|live_chat)\.", low):
                    continue
                if not low.endswith(KEEP_EXT) or re.search(r"\.f\d+\.", low):
                    continue
                dest = final_name(f.name, [x.name for x in env.lib.iterdir()])
                shutil.move(str(f), str(env.lib / dest))
                result["files"].append(dest)
                made += 1
            if made == 0:
                hint = sc.download_hint("\n".join(log), kinds, src is not None, use_aria2c, what == "subtitles")
                raise RuntimeError(hint or "ဖိုင်တစ်ခုမှ မရဘူး (link မှန်လား၊ ဒီ website အတွက် yt-dlp အသစ်လိုနိုင်တယ်)")
        except Canceled:
            raise
        except Exception as e:  # one bad link does not stop the others
            msg = str(e)
            hint = sc.download_hint(msg + "\n" + "\n".join(log), kinds, src is not None, use_aria2c, what == "subtitles")
            result["errors"].append(f"{url[:70]}: " + ((hint + " · ") if hint and hint not in msg else "") + msg[:240])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    if not result["files"]:
        raise RuntimeError(" | ".join(result["errors"]) or "ဖိုင်တစ်ခုမှ မရဘူး")
    env.progress("ပြီးပြီ", 100)
    return result


# ---- split ------------------------------------------------------------------
def op_split(env: Env, req) -> dict:
    src = file_path(env.lib, req.file, ("video",))
    total = duration_ms(env, src) / 1000
    if total < sc.MIN_PART_SECONDS:
        raise ValueError("ဗီဒီယိုအရှည်ကို မဖတ်နိုင်ဘူး (ဖိုင်ပျက်နေနိုင်တယ်)")
    if (getattr(req, "split_mode", "count") or "count") == "ranges":
        parts, err = sc.parse_ranges(req.ranges, total)
        if err:
            raise ValueError(err)
    else:
        parts = sc.equal_parts(total, int(getattr(req, "count", 2) or 2))
        if not parts:
            raise ValueError("ဗီဒီယို တိုလွန်းလို့ မခွဲနိုင်ဘူး")
    cues = []
    if getattr(req, "srt_file", ""):
        cues = sc.parse_srt(file_path(env.lib, req.srt_file, ("srt",)).read_text(encoding="utf-8", errors="ignore"))
    free_ok(env.lib)
    stem = os.path.splitext(src.name)[0]
    ext = src.suffix.lower()
    files, notes = [], []
    for i, (a, b) in enumerate(parts, 1):
        env.check()
        env.progress(f"အပိုင်း {i}/{len(parts)} ဖြတ်နေတယ်", int(100 * (i - 1) / len(parts)) + 1)
        name = sc.unique_name(f"{stem}_Part{i:02d}", ext, [f.name for f in env.lib.iterdir()])
        out = env.lib / name
        try:
            run_ffmpeg(env, sc.split_cmd(env.ffmpeg, str(src), a, b - a, str(out), bool(getattr(req, "reencode", False))))
        except BaseException:
            out.unlink(missing_ok=True)
            raise
        if not out.exists() or out.stat().st_size < 1024:
            out.unlink(missing_ok=True)
            raise RuntimeError(f"အပိုင်း {i} မထွက်ဘူး")
        files.append(name)
        if cues:
            part_cues = sc.slice_srt(cues, a, b)
            if part_cues:
                sname = sc.unique_name(f"{stem}_Part{i:02d}", ".srt", [f.name for f in env.lib.iterdir()])
                (env.lib / sname).write_text(sc.serialize_srt(part_cues), encoding="utf-8")
                files.append(sname)
    if not getattr(req, "reencode", False):
        notes.append("Stream copy နဲ့ ဖြတ်တာမို့ အနီးဆုံး key frame မှာ ဖြတ်တယ် (အတိအကျ လိုရင် 'Re-encode' ဖွင့်ပါ)")
    env.progress("ပြီးပြီ", 100)
    return {"files": files, "notes": notes, "errors": []}


# ---- subtitles --------------------------------------------------------------
def _free_translator(src_lang: str):
    from deep_translator import GoogleTranslator

    tr = GoogleTranslator(source=src_lang or "auto", target="my")
    sep = "\n<<<SRT_SEP>>>\n"

    def many(texts: List[str]) -> List[str]:
        if len(texts) == 1:
            return [tr.translate(texts[0]) or ""]
        res = tr.translate(sep.join(t.replace("<<<SRT_SEP>>>", " ") for t in texts)) or ""
        parts = re.split(r"\s*<<<\s*SRT_SEP\s*>>>\s*", res)
        time.sleep(0.25)
        return parts

    return many


def op_translate(env: Env, req) -> dict:
    src = file_path(env.lib, req.file, ("srt",))
    cues = sc.parse_srt(src.read_text(encoding="utf-8", errors="ignore"))
    if not cues:
        raise ValueError("SRT ထဲမှာ စာတန်းစာကြောင်း မတွေ့ဘူး")
    engine = getattr(req, "engine", "free") or "free"
    lang = getattr(req, "src_lang", "auto") or "auto"
    if engine == "gemini":
        if env.gemini_many is None:
            raise ValueError("Gemini key မပါဘူး (Settings မှာ ထည့်ပါ)")
        many = lambda texts: env.gemini_many(texts, lang)  # noqa: E731
    else:
        try:
            many = _free_translator(lang)
        except Exception:
            raise RuntimeError("deep-translator မတပ်ရသေးဘူး (Colab Cell 1 ကို ပြန် run ပါ) — ဒါမှမဟုတ် Gemini engine ရွေးပါ")

    def prog(done, total):
        env.check()
        env.progress(f"ဘာသာပြန်နေတယ် {done}/{total}", int(100 * done / max(1, total)))

    new, failed = sc.translate_cues(cues, many, prog)
    if failed >= len(cues):
        raise RuntimeError("ဘာသာပြန် တစ်ကြောင်းမှ မရဘူး (engine ကန့်သတ်ထားတာ/key မမှန်တာ ဖြစ်နိုင်တယ် — ခဏနေ ပြန်စမ်း၊ ဒါမှမဟုတ် တခြား engine ရွေးပါ)")
    stem = re.sub(r"_my$", "", os.path.splitext(src.name)[0])
    out = sc.unique_name(stem + "_my", ".srt", [f.name for f in env.lib.iterdir()])
    (env.lib / out).write_text(sc.serialize_srt(new), encoding="utf-8")
    notes = [f"စာကြောင်း {len(cues) - failed}/{len(cues)} ဘာသာပြန်ပြီး"]
    if failed:
        notes.append(f"{failed} ကြောင်း မပြန်နိုင်လို့ မူရင်းအတိုင်း ထားတယ်")
    env.progress("ပြီးပြီ", 100)
    return {"files": [out], "notes": notes, "errors": []}


def op_subtitle_video(env: Env, req) -> dict:
    """Soft CC (a track you can switch off, what YouTube also reads) and / or hardsub (burned in)."""
    video = file_path(env.lib, req.file, ("video",))
    srt = file_path(env.lib, req.srt_file, ("srt",))
    mode = getattr(req, "sub_mode", "soft") or "soft"
    if mode not in ("soft", "hard", "both"):
        raise ValueError("sub_mode မမှန်ဘူး")
    free_ok(env.lib)
    stem = os.path.splitext(video.name)[0]
    files, notes = [], []
    steps = [m for m in ("soft", "hard") if mode in (m, "both")]
    for i, m in enumerate(steps):
        env.check()
        env.progress("Soft CC ထည့်နေတယ်" if m == "soft" else "Hardsub ဖော်နေတယ် (ကြာတယ်)", int(100 * i / len(steps)) + 1)
        name = sc.unique_name(stem + ("_cc" if m == "soft" else "_hardsub"), ".mp4", [f.name for f in env.lib.iterdir()])
        out = env.lib / name
        if m == "soft":
            cmd = sc.mux_cc_cmd(env.ffmpeg, str(video), str(srt), str(out))
        else:
            gpu = has_nvenc(env.ffmpeg)
            cmd = sc.hardsub_cmd(env.ffmpeg, str(video), str(srt), str(out), getattr(req, "font", "Padauk"), int(getattr(req, "font_size", 22) or 22), gpu)
            notes.append("GPU (nvenc) နဲ့ ဖော်တယ်" if gpu else "CPU နဲ့ ဖော်တယ် (GPU runtime ရွေးရင် ပိုမြန်တယ်)")
        try:
            run_ffmpeg(env, cmd)
        except BaseException:
            out.unlink(missing_ok=True)
            raise
        files.append(name)
    env.progress("ပြီးပြီ", 100)
    return {"files": files, "notes": notes, "errors": []}


# ---- zip --------------------------------------------------------------------
def op_zip(env: Env, req) -> dict:
    names = list(getattr(req, "files", []) or [])
    if not names:
        raise ValueError("ZIP လုပ်မယ့် ဖိုင် မရွေးရသေးဘူး")
    paths = [file_path(env.lib, n) for n in names]
    free_ok(env.lib)
    base = sc.make_stem(getattr(req, "zip_name", "") or "", "studio_" + time.strftime("%Y%m%d_%H%M"))
    out = sc.unique_name(base, ".zip", [f.name for f in env.lib.iterdir()])
    with zipfile.ZipFile(env.lib / out, "w", zipfile.ZIP_STORED, allowZip64=True) as z:  # videos do not shrink: no time wasted
        for i, p in enumerate(paths, 1):
            env.check()
            env.progress(f"ZIP {i}/{len(paths)}", int(100 * i / len(paths)))
            z.write(p, arcname=p.name)
    return {"files": [out], "notes": [], "errors": []}


# ---- YouTube ----------------------------------------------------------------
YT_SCOPES = ["https://www.googleapis.com/auth/youtube.upload", "https://www.googleapis.com/auth/youtube.force-ssl"]
_YT = {"flow": None}
_YT_LOCK = threading.Lock()


def yt_secret_path() -> Optional[Path]:
    for c in (os.environ.get("DF_YT_CLIENT_SECRET"), "/content/client_secret.json", str(Path(__file__).resolve().parent / "client_secret.json")):
        if c and Path(c).is_file():
            return Path(c)
    return None


def yt_token_path() -> Path:
    return Path(os.environ.get("DF_YT_TOKEN") or "/content/youtube_token.json")


def yt_status() -> dict:
    return {"secret": yt_secret_path() is not None, "linked": yt_token_path().is_file()}


def yt_auth_link() -> str:
    sec = yt_secret_path()
    if sec is None:
        raise ValueError("client_secret.json မတွေ့ဘူး — Colab ထဲ /content/client_secret.json အဖြစ် တင်ပါ (Notebook Cell 5c)")
    try:
        from google_auth_oauthlib.flow import Flow
    except Exception:
        raise RuntimeError("google-auth-oauthlib မတပ်ရသေးဘူး (Colab Cell 1 ကို ပြန် run ပါ)")
    os.environ.setdefault("OAUTHLIB_RELAX_TOKEN_SCOPE", "1")
    try:
        flow = Flow.from_client_secrets_file(str(sec), scopes=YT_SCOPES, redirect_uri="http://localhost")
    except Exception as e:
        raise ValueError("client_secret.json ဖတ်မရဘူး (Google Cloud မှာ 'Desktop app' OAuth client ဖြစ်ရမယ်): " + str(e)[:120])
    url, _ = flow.authorization_url(access_type="offline", include_granted_scopes="true", prompt="consent")
    with _YT_LOCK:
        _YT["flow"] = flow
    return url


def yt_auth_complete(pasted: str) -> dict:
    with _YT_LOCK:
        flow = _YT["flow"]
    if flow is None:
        raise ValueError("Login link ကို အရင်ထုတ်ပါ (၁ ဆင့်)")
    code = sc.extract_oauth_code(pasted)
    if not code:
        raise ValueError("Google login ပြီးရင် browser မှာ ပေါ်တဲ့ http://localhost/?code=... လိပ်စာတစ်ခုလုံး ကူးထည့်ပါ")
    try:
        flow.fetch_token(code=code)
    except Exception as e:
        raise ValueError("Login အတည်မပြုနိုင်ဘူး: " + (sc.youtube_error_hint(str(e)) or str(e)[:160]))
    tp = yt_token_path()
    tp.write_text(flow.credentials.to_json(), encoding="utf-8")
    try:
        os.chmod(tp, 0o600)
    except OSError:
        pass
    with _YT_LOCK:
        _YT["flow"] = None
    return yt_status()


def yt_unlink():
    yt_token_path().unlink(missing_ok=True)
    with _YT_LOCK:
        _YT["flow"] = None


def _yt_service():
    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
    except Exception:
        raise RuntimeError("YouTube library မတပ်ရသေးဘူး (Colab Cell 1 ကို ပြန် run ပါ)")
    tp = yt_token_path()
    if not tp.is_file():
        raise ValueError("YouTube login မဝင်ရသေးဘူး — Studio > YouTube မှာ login အရင်ဝင်ပါ")
    creds = Credentials.from_authorized_user_file(str(tp), YT_SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        tp.write_text(creds.to_json(), encoding="utf-8")
        try:
            os.chmod(tp, 0o600)
        except OSError:
            pass
    if not creds.valid:
        raise ValueError("YouTube login သက်တမ်းကုန်သွားပြီ — ပြန် login ဝင်ပါ")
    return build("youtube", "v3", credentials=creds)


def _srt_for(env: Env, video_name: str) -> Optional[Path]:
    stem = os.path.splitext(video_name)[0]
    for cand in (stem + "_my.srt", re.sub(r"_(cc|hardsub)$", "", stem) + "_my.srt", stem + ".srt"):
        if sc.safe_name(cand) and (env.lib / cand).is_file():
            return env.lib / cand
    return None


def op_youtube(env: Env, req) -> dict:
    if not getattr(req, "confirm_rights", False):
        raise ValueError("YouTube ပေါ် တင်မယ့် ဗီဒီယိုက ကိုယ်ပိုင် / တင်ခွင့်ရှိတာ ဖြစ်ကြောင်း အတည်ပြုပါ")
    names = list(getattr(req, "files", []) or [])
    if not names:
        raise ValueError("တင်မယ့် ဗီဒီယို မရွေးရသေးဘူး")
    paths = [file_path(env.lib, n, ("video",)) for n in names]
    privacy = getattr(req, "privacy", "private") or "private"
    if privacy not in sc.YT_PRIVACY:
        raise ValueError("privacy မမှန်ဘူး")
    thumb = None
    if getattr(req, "thumbnail", ""):
        thumb = file_path(env.lib, req.thumbnail, ("image",))
    youtube = _yt_service()
    from googleapiclient.errors import HttpError
    from googleapiclient.http import MediaFileUpload

    cat = sc.YT_CATEGORIES.get(getattr(req, "category", "entertainment"), "24")
    tags = sc.clean_tags(getattr(req, "tags", ""))
    desc = sc.clean_description(getattr(req, "description", ""))
    links, notes, errors = [], [], []
    for i, p in enumerate(paths, 1):
        env.check()
        title = sc.format_title(getattr(req, "title_template", "{name}"), os.path.splitext(p.name)[0], i, len(paths))
        body = {"snippet": {"title": title, "description": desc, "tags": tags, "categoryId": cat},
                "status": {"privacyStatus": privacy, "selfDeclaredMadeForKids": bool(getattr(req, "kids", False))}}
        try:
            media = MediaFileUpload(str(p), mimetype=MIME.get(p.suffix.lower(), "video/mp4"), chunksize=8 * 1024 * 1024, resumable=True)
            r = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
            resp = None
            while resp is None:
                env.check()
                st, resp = r.next_chunk()
                if st:
                    env.progress(f"YouTube တင်နေတယ် ({i}/{len(paths)}) {int(st.progress() * 100)}%", int(100 * (i - 1 + st.progress()) / len(paths)))
            vid = resp.get("id")
            extra = ""
            if thumb is not None:
                try:
                    youtube.thumbnails().set(videoId=vid, media_body=MediaFileUpload(str(thumb))).execute()
                    extra += " · thumbnail OK"
                except Exception as te:
                    extra += " · thumbnail မတင်နိုင်ဘူး: " + str(te)[:80]
            if getattr(req, "upload_cc", False):
                srt = _srt_for(env, p.name)
                if srt is not None:
                    try:
                        youtube.captions().insert(
                            part="snippet", body={"snippet": {"videoId": vid, "language": "my", "name": "Myanmar", "isDraft": False}},
                            media_body=MediaFileUpload(str(srt), mimetype="application/octet-stream")).execute()
                        extra += " · Myanmar CC OK"
                    except Exception as ce:
                        extra += " · CC မတင်နိုင်ဘူး: " + str(ce)[:80]
                else:
                    extra += " · CC ဖိုင် (_my.srt) မတွေ့လို့ မတင်ဘူး"
            links.append({"title": title, "watch": f"https://youtu.be/{vid}", "studio": f"https://studio.youtube.com/video/{vid}/edit", "note": extra.strip(" ·")})
        except HttpError as he:
            msg = str(he)
            errors.append(f"{title}: " + (sc.youtube_error_hint(msg) or msg[:200]))
            if "quota" in msg.lower():
                break
        except Canceled:
            raise
        except Exception as e:
            msg = str(e)
            errors.append(f"{title}: " + (sc.youtube_error_hint(msg) or msg[:200]))
    if not links:
        raise RuntimeError(" | ".join(errors) or "တင်လို့မရဘူး")
    if privacy == "public":
        notes.append("Public ရွေးထားပေမဲ့ Google API project ကို audit မလုပ်ရသေးရင် YouTube က private ပဲ ထားတတ်တယ် — Studio လင့်ကနေ စစ်ပါ")
    notes.append("ဗီဒီယိုတစ်ပုဒ်တင်တိုင်း quota ကုန်တယ် (တစ်ရက် ၆ ပုဒ်လောက်)")
    env.progress("ပြီးပြီ", 100)
    return {"files": [], "links": links, "notes": notes, "errors": errors}
