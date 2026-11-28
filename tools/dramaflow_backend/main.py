"""DramaFlow Recap Backend (for Altare, Colab or any computer that runs Python).

Start:  uvicorn main:app --host 0.0.0.0 --port $PORT
Set the environment variable APP_TOKEN to a long secret of your own. Every call
except /health needs it in the header x-app-token. Without it a random token is
made at start and printed in the log.

What it does for the app (Video Recap and Scene Recap):
  POST /recap/jobs             start a job, answers at once with a job id
  GET  /recap/jobs/<id>        progress, then the script parts (and voice files)
  GET  /recap/jobs/<id>/audio/<n>.wav   the voice of part n (24 kHz mono WAV)
  POST /ingest/jobs            a video link (YouTube, TikTok, Red Note ...): download it
                               here, put it into the user's own Gemini account, answer
                               with the Gemini file address and the length
  GET  /ingest/jobs/<id>       progress, then {file_uri, mime, duration_ms, title}
  Creator Studio (your own files and videos you may use; the library lives on this machine):
  GET  /studio/files           the library          GET /studio/files/<name>   one file to the phone
  DELETE /studio/files/<name>  POST /studio/upload  a small .srt / picture from the phone
  POST /studio/jobs            download | split | translate | subtitle | zip | youtube | transcribe (Whisper) | render
  GET  /studio/jobs/<id>       progress (speed, ETA), result files / links
  POST /studio/jobs/<id>/cancel | pause | resume
  GET/POST /studio/youtube/... status, auth-link, auth-complete, unlink
The Gemini key arrives with the request, is used for the job and is not stored.
"""
import asyncio
import base64
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import threading
import time
import wave
from pathlib import Path
from typing import List, Optional

import edge_tts
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from google import genai
from google.genai import types
from pydantic import BaseModel

from ingest_core import (MAX_BYTES, MAX_SECONDS, SUB_LANGS, SUB_SUFFIXES, check_url, classify, clean_srt, cookie_note,
                         cookies_problem, cookies_source as _cookies_source, ingest_hint, parse_ffmpeg_duration, pick_subtitle, run_ingest)
from recap_core import fit_tempo, gemini_hint, mask_key, run_recap
import studio_core as sc
import studio_ops as so
from tts_text import normalize_for_tts

app = FastAPI(title="DramaFlow Recap Backend")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

TOKEN = os.environ.get("APP_TOKEN") or secrets.token_urlsafe(18)
if not os.environ.get("APP_TOKEN"):
    print("APP_TOKEN not set. A temporary token for this run:", TOKEN, flush=True)
OUT_DIR = Path(tempfile.gettempdir()) / "dramaflow_recap"
OUT_DIR.mkdir(parents=True, exist_ok=True)
JOBS: dict = {}
LOCK = threading.Lock()
KEEP_SECONDS = 2 * 3600
DEFAULT_VOICE = "my-MM-ThihaNeural"


class Group(BaseModel):
    first: int
    last: int
    prompt: str
    jpeg_b64: str = ""  # Scene Recap: the numbered contact sheet
    start_ms: int = 0  # Video Recap: look only at this time range
    end_ms: int = 0
    part_ms: List[int] = []  # how long each part's video is (first..last), to fit the voice


class RecapRequest(BaseModel):
    mode: str = "scenes"  # "scenes" (pictures + dialogue) or "video" (a file already in Gemini)
    gemini_key: str
    gemini_model: str = "gemini-3.8-flash"
    gemini_fallback: str = ""  # optional second model, tried when the first is gone (404) or over its quota
    voice: str = ""  # empty = script only, no voice
    file_uri: str = ""  # Gemini Files API address (video mode)
    file_mime: str = "video/mp4"
    groups: List[Group]


def _auth(token: Optional[str]):
    if not token or not secrets.compare_digest(token, TOKEN):
        raise HTTPException(status_code=401, detail="Bad or missing x-app-token")


def _set(job_id: str, **kw):
    with LOCK:
        JOBS[job_id].update(kw)


def _ffmpeg() -> str:
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return shutil.which("ffmpeg") or "ffmpeg"


FALLBACK_WHEN = ("404", "NOT_FOUND", "429", "RESOURCE_EXHAUSTED", "503", "UNAVAILABLE")


def _gemini_fn(req: RecapRequest):
    client = genai.Client(api_key=req.gemini_key)

    def ask(model: str, contents: list) -> str:
        for attempt in range(3):
            try:
                r = client.models.generate_content(model=model, contents=contents, config=types.GenerateContentConfig(temperature=0.5))
                return r.text or ""
            except Exception as e:
                msg = str(e)
                busy = any(k in msg for k in ("429", "503", "RESOURCE_EXHAUSTED", "UNAVAILABLE"))
                if busy and attempt < 2:
                    time.sleep(25 * (attempt + 1))
                    continue
                raise RuntimeError(mask_key(msg, req.gemini_key))
        return ""

    def call(g: dict) -> str:
        contents: list = []
        if g.get("jpeg_b64"):
            contents.append(types.Part.from_bytes(data=base64.b64decode(g["jpeg_b64"]), mime_type="image/jpeg"))
        if req.mode == "video":
            if not req.file_uri:
                raise ValueError("video file_uri မပါဘူး")
            contents.append(
                types.Part(
                    file_data=types.FileData(file_uri=req.file_uri, mime_type=req.file_mime),
                    video_metadata=types.VideoMetadata(
                        start_offset=f"{max(0, int(g.get('start_ms', 0)) // 1000)}s",
                        end_offset=f"{max(1, -(-int(g.get('end_ms', 0)) // 1000))}s",
                    ),
                )
            )
        contents.append(g["prompt"])
        try:
            return ask(req.gemini_model, contents)
        except RuntimeError as e:
            fb = req.gemini_fallback.strip()
            if fb and fb != req.gemini_model and any(k in str(e) for k in FALLBACK_WHEN):
                print(f"model {req.gemini_model} failed, trying {fb}", flush=True)
                return ask(fb, contents)
            raise

    return call


def _speak(text: str, voice: str, mp3: Path, rate: str = "+0%"):
    """Edge TTS to an mp3 file, three tries."""
    for attempt in range(3):
        try:
            asyncio.run(edge_tts.Communicate(text, voice, rate=rate).save(str(mp3)))
            return
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def _to_wav(src: Path, dst: Path, tempo: float = 1.0):
    """24 kHz mono WAV; tempo above 1.0 speeds the voice up (pitch is kept)."""
    cmd = [_ffmpeg(), "-y", "-i", str(src), "-ar", "24000", "-ac", "1"]
    if tempo > 1.001:
        cmd += ["-filter:a", f"atempo={tempo}"]
    cmd += ["-c:a", "pcm_s16le", str(dst)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or not dst.exists():
        raise RuntimeError("ffmpeg: " + (p.stderr or "")[-200:])


def _wav_ms(wav: Path) -> int:
    with wave.open(str(wav), "rb") as w:
        return int(w.getnframes() * 1000 / w.getframerate())


def _tts_fn(job_dir: Path, voice: str):
    use = voice if voice.startswith("my-MM-") else DEFAULT_VOICE

    def make(n: int, text: str, target_ms: int = 0):
        mp3, wav = job_dir / f"p{n}.mp3", job_dir / f"p{n}.wav"
        try:
            _speak(normalize_for_tts(text), use, mp3)
            _to_wav(mp3, wav)
            ms = _wav_ms(wav)
            tempo = fit_tempo(ms, target_ms)
            if tempo > 1.0:  # a little too long: speed it up, never more than 15%
                fast = job_dir / f"p{n}_fast.wav"
                _to_wav(mp3, fast, tempo)
                fast.replace(wav)
                ms = _wav_ms(wav)
        finally:
            mp3.unlink(missing_ok=True)
        return ms, wav.name

    return make


def clean_old():
    now = time.time()
    with LOCK:
        for jid, j in list(JOBS.items()):
            if j["status"] in ("done", "error") and now - j["created"] > KEEP_SECONDS:
                shutil.rmtree(OUT_DIR / jid, ignore_errors=True)
                del JOBS[jid]


def _save_job(job_id: str):
    """The finished job (text, warnings, audio addresses) is kept next to its
    audio files, so the app can fetch it again after the web process restarted."""
    try:
        with LOCK:
            data = dict(JOBS[job_id])
        (OUT_DIR / job_id / "job.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass


def _load_job(job_id: str):
    if not re.fullmatch(r"recap_\d+_[0-9a-f]{4}", job_id):
        return None
    f = OUT_DIR / job_id / "job.json"
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return None
    if data.get("status") != "done" or time.time() - float(data.get("created", 0)) > KEEP_SECONDS:
        return None
    with LOCK:
        JOBS[job_id] = data
    return data


def run_job(job_id: str, req: RecapRequest):
    job_dir = OUT_DIR / job_id
    try:
        job_dir.mkdir(parents=True, exist_ok=True)
        _set(job_id, status="running", stage="စတင်နေတယ်", progress=2)
        result = run_recap(
            [g.model_dump() for g in req.groups],
            _gemini_fn(req),
            _tts_fn(job_dir, req.voice) if req.voice else None,
            lambda stage, pct: _set(job_id, stage=stage, progress=pct),
        )
        for p in result["parts"]:
            if p["audio_file"]:
                p["audio_url"] = f"/recap/jobs/{job_id}/audio/{p['n']}.wav"
            p.pop("audio_file")
        _set(job_id, status="done", stage="ပြီးပြီ", progress=100, parts=result["parts"], warnings=result["warnings"])
        _save_job(job_id)
    except Exception as e:  # shown in the app, with the key hidden
        _set(job_id, status="error", stage="မအောင်မြင်ဘူး", error=mask_key(str(e), req.gemini_key)[:400])
        shutil.rmtree(job_dir, ignore_errors=True)


@app.get("/health")
def health():
    return {"status": "ok", "service": "DramaFlow Recap Backend", "features": ["recap", "tts", "ingest", "studio"]}


@app.post("/recap/jobs")
def create_job(req: RecapRequest, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if not req.groups:
        raise HTTPException(status_code=400, detail="groups မပါဘူး")
    clean_old()
    with LOCK:
        if any(j["status"] in ("queued", "running") for j in JOBS.values()):
            raise HTTPException(status_code=409, detail="တခြား job တစ်ခု လုပ်နေတုန်းပါ")
        job_id = f"recap_{int(time.time())}_{secrets.token_hex(2)}"
        JOBS[job_id] = {"status": "queued", "stage": "စောင့်နေတယ်", "progress": 0, "created": time.time(),
                        "error": "", "parts": [], "warnings": []}
    threading.Thread(target=run_job, args=(job_id, req), daemon=True).start()
    return {"job_id": job_id}


@app.get("/recap/jobs/{job_id}")
def job_status(job_id: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    with LOCK:
        j = JOBS.get(job_id)
    if j is None:
        j = _load_job(job_id)
    if j is None:
        raise HTTPException(status_code=404, detail="Job မတွေ့ပါ")
    with LOCK:
        return {k: v for k, v in j.items() if k != "created"}


@app.get("/recap/jobs/{job_id}/audio/{n}.wav")
def audio(job_id: str, n: int, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if not re.fullmatch(r"recap_\d+_[0-9a-f]{4}", job_id):
        raise HTTPException(status_code=404, detail="Audio not found")
    p = OUT_DIR / job_id / f"p{int(n)}.wav"
    if not p.exists():
        raise HTTPException(status_code=404, detail="Audio not found")
    return FileResponse(p, media_type="audio/wav", filename=p.name)


# ---- link -> video in the user's own Gemini account -------------------------
class IngestRequest(BaseModel):
    url: str
    gemini_key: str
    max_height: int = 720  # Gemini looks at about 1 frame a second, so 720p is plenty


def _state_name(f) -> str:
    st = getattr(f, "state", None)
    return str(getattr(st, "name", st) or "")


def _ytdlp_download(url: str, job_dir: Path, max_height: int, on_pct):
    """yt-dlp is imported here so the backend still starts (and recaps work)
    when it is not installed; the error then says what to install."""
    try:
        import yt_dlp
        from yt_dlp.utils import match_filter_func
    except Exception:
        raise RuntimeError("yt-dlp မတပ်ရသေးဘူး (Colab Cell 1 ကို ပြန် run ပါ)")
    h = max(240, min(1080, int(max_height)))

    def hook(d):
        if d.get("status") == "downloading":
            tot = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            if tot:
                on_pct(int(100 * (d.get("downloaded_bytes") or 0) / tot))

    cookies_text = ""
    cookie_file = None
    src = _cookies_source()
    if src is not None:
        cookies_text = src.read_text(encoding="utf-8", errors="ignore")
        bad = cookies_problem(cookies_text)
        if bad:
            raise ValueError(bad)
        cookie_file = job_dir / "cookies.txt"  # a private copy (yt-dlp writes to its cookie file); deleted with the job
        cookie_file.write_text(cookies_text, encoding="utf-8")
        try:
            os.chmod(cookie_file, 0o600)
        except OSError:
            pass
        note = cookie_note(cookies_text, classify(url))
        if note:
            print("cookies:", note, flush=True)

    opts = {
        "outtmpl": str(job_dir / "v.%(ext)s"),
        "format": f"bv*[height<={h}][ext=mp4]+ba[ext=m4a]/bv*[height<={h}]+ba/b[height<={h}]/b",
        "merge_output_format": "mp4",
        "noplaylist": True,
        "max_filesize": MAX_BYTES,
        "match_filter": match_filter_func(f"!is_live & duration <=? {MAX_SECONDS}"),
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 30,
        "retries": 3,
        "ffmpeg_location": _ffmpeg(),
        "progress_hooks": [hook],
        # the uploader's own subtitles, as .srt (a failure here does not stop the video)
        "writesubtitles": True,
        "subtitleslangs": list(SUB_LANGS),
        "subtitlesformat": "srt/best",
        "postprocessors": [{"key": "FFmpegSubtitlesConvertor", "format": "srt", "when": "before_dl"}],
    }
    if cookie_file is not None:
        opts["cookiefile"] = str(cookie_file)
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
    files = [f for f in job_dir.glob("v.*") if f.suffix.lower() not in (".part", ".ytdl") + tuple(SUB_SUFFIXES)]
    if not files:
        raise RuntimeError("ဗီဒီယို မရဘူး (၃ နာရီထက် ရှည်တာ / live / ၂ GB ထက်ကြီးတာ ဖြစ်နိုင်တယ်)")
    path = max(files, key=lambda f: f.stat().st_size)
    if isinstance(info, dict) and info.get("entries"):
        info = (info["entries"] or [{}])[0] or {}
    ms = int(float((info or {}).get("duration") or 0) * 1000)
    if not ms:
        try:
            p = subprocess.run([_ffmpeg(), "-i", str(path)], capture_output=True, text=True, timeout=60)
            ms = parse_ffmpeg_duration(p.stderr)
        except Exception:
            ms = 0
    srt, srt_lang = "", ""
    sub_name, srt_lang = pick_subtitle([f.name for f in job_dir.glob("v.*.srt")])
    if sub_name:
        try:
            srt = clean_srt((job_dir / sub_name).read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            srt = ""
        if not srt:
            srt_lang = ""
    return {"path": str(path), "title": (info or {}).get("title") or "", "duration_ms": ms,
            "srt": srt, "srt_lang": srt_lang, "cookies": cookie_file is not None}


def _gemini_upload(key: str, path: str, mime: str):
    client = genai.Client(api_key=key)
    f = client.files.upload(file=path, config=types.UploadFileConfig(mime_type=mime, display_name="dramaflow_ingest"))
    waited = 0
    while _state_name(f) == "PROCESSING":
        if waited > 1200:
            raise RuntimeError("Gemini က ဗီဒီယိုကို မပြီးသေးဘူး (၂၀ မိနစ်ကျော်)")
        time.sleep(5)
        waited += 5
        f = client.files.get(name=f.name)
    if _state_name(f) != "ACTIVE":
        raise RuntimeError("Gemini က ဗီဒီယိုကို လက်မခံဘူး (%s)" % (_state_name(f) or "?"))
    return f.uri, mime


def run_ingest_job(job_id: str, req: IngestRequest):
    job_dir = OUT_DIR / job_id
    done = {}
    try:
        job_dir.mkdir(parents=True, exist_ok=True)
        _set(job_id, status="running", stage="စတင်နေတယ်", progress=2)
        done = run_ingest(
            req.url.strip(),
            lambda url, on_pct: _ytdlp_download(url, job_dir, req.max_height, on_pct),
            lambda path, mime: _gemini_upload(req.gemini_key, path, mime),
            lambda stage, pct: _set(job_id, stage=stage, progress=min(pct, 99)),
        )
        err = ""
    except Exception as e:  # shown in the app, with the key hidden
        msg = mask_key(str(e), req.gemini_key)
        hint = ingest_hint(msg, classify(req.url), has_cookies=_cookies_source() is not None)
        err = ((hint + " · ") if hint else "") + msg[:300]
    shutil.rmtree(job_dir, ignore_errors=True)  # the downloaded copy is never kept
    if err:
        _set(job_id, status="error", stage="မအောင်မြင်ဘူး", error=err)
    else:
        _set(job_id, status="done", stage="ပြီးပြီ", progress=100, info=done)


@app.post("/ingest/jobs")
def create_ingest(req: IngestRequest, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if not req.gemini_key.strip():
        raise HTTPException(status_code=400, detail="Gemini key မပါဘူး")
    ok, why = check_url(req.url)
    if not ok:
        raise HTTPException(status_code=400, detail=why)
    clean_old()
    with LOCK:
        if any(j["status"] in ("queued", "running") for j in JOBS.values()):
            raise HTTPException(status_code=409, detail="တခြား job တစ်ခု လုပ်နေတုန်းပါ")
        job_id = f"ingest_{int(time.time())}_{secrets.token_hex(2)}"
        JOBS[job_id] = {"status": "queued", "stage": "စောင့်နေတယ်", "progress": 0, "created": time.time(),
                        "error": "", "info": {}}
    threading.Thread(target=run_ingest_job, args=(job_id, req), daemon=True).start()
    return {"job_id": job_id}


@app.get("/ingest/jobs/{job_id}")
def ingest_status(job_id: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    with LOCK:
        j = JOBS.get(job_id) if job_id.startswith("ingest_") else None
        if j is None:
            raise HTTPException(status_code=404, detail="Job မတွေ့ပါ")
        return {k: v for k, v in j.items() if k != "created"}


class TtsRequest(BaseModel):
    text: str
    voice: str = DEFAULT_VOICE
    rate: str = "+0%"


@app.post("/tts")
def tts_once(req: TtsRequest, x_app_token: Optional[str] = Header(default=None)):
    """One piece of text -> a WAV (24 kHz mono), for the app's Audio stage."""
    _auth(x_app_token)
    text = req.text.strip()
    if not text or len(text) > 6000:
        raise HTTPException(status_code=400, detail="စာသား မရှိဘူး/ရှည်လွန်းတယ် (၆၀၀၀ လုံးအထိ)")
    rate = req.rate if re.fullmatch(r"[+-]\d{1,3}%", req.rate) else "+0%"
    voice = req.voice if req.voice.startswith("my-MM-") else DEFAULT_VOICE
    d = OUT_DIR / f"tts_{secrets.token_hex(4)}"
    try:
        d.mkdir(parents=True, exist_ok=True)
        mp3, wav = d / "a.mp3", d / "a.wav"
        _speak(normalize_for_tts(text), voice, mp3, rate)
        _to_wav(mp3, wav)
        return Response(content=wav.read_bytes(), media_type="audio/wav")
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e)[:200])
    finally:
        shutil.rmtree(d, ignore_errors=True)


class SelfTestRequest(BaseModel):
    gemini_key: str = ""
    gemini_model: str = "gemini-3.8-flash"


@app.post("/selftest")
def selftest(req: SelfTestRequest, x_app_token: Optional[str] = Header(default=None)):
    """Checks what the recap needs, one by one, and says in Burmese what to do
    when something fails. Every check is [{id, ok, note}]; nothing is stored."""
    _auth(x_app_token)
    checks = []

    def add(cid: str, ok: bool, note: str):
        checks.append({"id": cid, "ok": ok, "note": note})

    ff = _ffmpeg()
    try:
        p = subprocess.run([ff, "-version"], capture_output=True, text=True, timeout=20)
        add("ffmpeg", p.returncode == 0, "ရတယ်" if p.returncode == 0 else "ffmpeg မပွင့်ဘူး (requirements ထဲ imageio-ffmpeg ပါလား)")
    except Exception as e:
        add("ffmpeg", False, "ffmpeg မရှိဘူး: " + str(e)[:80])

    d = OUT_DIR / f"selftest_{secrets.token_hex(3)}"
    try:
        d.mkdir(parents=True, exist_ok=True)
        _speak("မင်္ဂလာပါ", DEFAULT_VOICE, d / "t.mp3")
        _to_wav(d / "t.mp3", d / "t.wav")
        add("edge_tts", True, f"မြန်မာအသံ လုပ်လို့ရတယ် ({_wav_ms(d / 't.wav')} ms)")
    except Exception as e:
        add("edge_tts", False, "Edge TTS မရဘူး (backend က အင်တာနက်ထွက်လို့ရလား၊ ခဏနေ ပြန်စမ်း): " + str(e)[:100])
    finally:
        shutil.rmtree(d, ignore_errors=True)

    if not req.gemini_key.strip():
        add("gemini", False, "Gemini key မပါဘူး (Settings မှာ ထည့်ပါ)")
    else:
        try:
            client = genai.Client(api_key=req.gemini_key.strip())
            r = client.models.generate_content(model=req.gemini_model, contents="Reply with the single word OK.")
            add("gemini", True, f"{req.gemini_model} ဖြေတယ်: {(r.text or '').strip()[:20]}")
        except Exception as e:
            msg = mask_key(str(e), req.gemini_key)
            hint = gemini_hint(msg)
            add("gemini", False, hint + " · " + msg[:120])
    return {"checks": checks}


# ---- Creator Studio ---------------------------------------------------------
STUDIO_DIR = Path(os.environ.get("DF_STUDIO_DIR") or (Path(tempfile.gettempdir()) / "dramaflow_studio"))
STUDIO_OPS = ("download", "split", "translate", "subtitle", "zip", "youtube", "transcribe", "render", "karaoke", "nursery")
STUDIO_FLAGS: dict = {}  # job id -> {"cancel": bool, "pause": bool}


class StudioUpload(BaseModel):
    name: str
    data_b64: str


class StudioRequest(BaseModel):
    op: str
    # download
    url: str = ""
    quality: str = "720"
    speed: str = "safe4"
    playlist: bool = False
    playlist_items: str = ""
    sub_langs: str = "auto"
    subtitles: bool = False
    auto_subs: bool = False
    # split / subtitle / translate
    file: str = ""
    split_mode: str = "count"
    count: int = 2
    ranges: str = ""
    srt_file: str = ""
    reencode: bool = False
    engine: str = "free"
    src_lang: str = "auto"
    gemini_key: str = ""
    gemini_model: str = "gemini-3.8-flash"
    sub_mode: str = "soft"
    font: str = "Padauk"
    font_size: int = 22
    # transcribe (Whisper)
    whisper_model: str = "small"
    whisper_vad: bool = True
    # render: the app's render job (see render_core.py)
    job: dict = {}
    # children's song video (karaoke + nursery ops)
    lyrics: str = ""
    karaoke_mode: str = "lyrics"
    ratio: str = "16:9"
    durations: List[float] = []
    # zip / youtube
    files: List[str] = []
    zip_name: str = ""
    confirm_rights: bool = False
    privacy: str = "private"
    title_template: str = "{name}"
    description: str = ""
    tags: str = ""
    category: str = "entertainment"
    kids: bool = False
    thumbnail: str = ""
    upload_cc: bool = False


class YoutubePaste(BaseModel):
    pasted: str


def _studio_gemini(req: StudioRequest):
    """Lines in, Burmese lines out, with the user's own Gemini key (used for this job only)."""
    client = genai.Client(api_key=req.gemini_key)

    def many(texts: List[str], lang: str) -> List[str]:
        prompt = sc.numbered_prompt(texts, lang)
        for attempt in range(3):
            try:
                r = client.models.generate_content(model=req.gemini_model, contents=prompt, config=types.GenerateContentConfig(temperature=0.3))
                return sc.parse_numbered_reply(r.text or "", len(texts))
            except Exception as e:
                msg = str(e)
                if any(k in msg for k in ("429", "503", "RESOURCE_EXHAUSTED", "UNAVAILABLE")) and attempt < 2:
                    time.sleep(20 * (attempt + 1))
                    continue
                raise RuntimeError(mask_key(msg, req.gemini_key))
        return []

    return many


def run_studio_job(job_id: str, req: StudioRequest):
    flags = STUDIO_FLAGS.setdefault(job_id, {"cancel": False, "pause": False})

    def detail(**kw):
        with LOCK:
            JOBS[job_id].setdefault("detail", {}).update(kw)

    env = so.Env(
        STUDIO_DIR, _ffmpeg(),
        lambda stage, pct: _set(job_id, stage=stage, progress=min(100, max(0, int(pct)))),
        lambda: flags["cancel"], lambda: flags["pause"], detail,
        _studio_gemini(req) if req.engine == "gemini" and req.gemini_key.strip() else None,
    )
    try:
        STUDIO_DIR.mkdir(parents=True, exist_ok=True)
        _set(job_id, status="running", stage="စတင်နေတယ်", progress=1)
        fn = {"download": so.op_download, "split": so.op_split, "translate": so.op_translate,
              "subtitle": so.op_subtitle_video, "zip": so.op_zip, "youtube": so.op_youtube, "transcribe": so.op_transcribe, "render": so.op_render, "karaoke": so.op_karaoke, "nursery": so.op_nursery}[req.op]
        result = fn(env, req)
        _set(job_id, status="done", stage="ပြီးပြီ", progress=100, result=result)
    except so.Canceled:
        _set(job_id, status="canceled", stage="ရပ်လိုက်ပြီ")
    except Exception as e:  # shown in the app, with the key hidden
        _set(job_id, status="error", stage="မအောင်မြင်ဘူး", error=mask_key(str(e), req.gemini_key)[:500])
    finally:
        flags["pause"] = False
        detail(paused=False)


@app.get("/studio/files")
def studio_files(x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    STUDIO_DIR.mkdir(parents=True, exist_ok=True)
    try:
        free = round(shutil.disk_usage(STUDIO_DIR).free / 1024**3, 1)
    except OSError:
        free = None
    return {"files": so.list_library(STUDIO_DIR), "free_gb": free, "aria2c": bool(shutil.which("aria2c")), "youtube": so.yt_status()}


@app.get("/studio/files/{name}")
def studio_file(name: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    try:
        p = so.file_path(STUDIO_DIR, name)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return FileResponse(str(p), filename=p.name, media_type="application/octet-stream")


@app.delete("/studio/files/{name}")
def studio_delete(name: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    try:
        so.delete_file(STUDIO_DIR, name)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return {"ok": True}


@app.post("/studio/upload")
def studio_upload(req: StudioUpload, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    try:
        return {"name": so.save_upload(STUDIO_DIR, req.name, req.data_b64)}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/studio/jobs")
def studio_create(req: StudioRequest, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if req.op not in STUDIO_OPS:
        raise HTTPException(status_code=400, detail="op မမှန်ဘူး")
    if req.op == "youtube" and not req.confirm_rights:
        raise HTTPException(status_code=400, detail="YouTube ပေါ် တင်မယ့် ဗီဒီယိုက ကိုယ်ပိုင် / တင်ခွင့်ရှိတာ ဖြစ်ကြောင်း အတည်ပြုပါ")
    if req.op == "youtube" and req.privacy not in sc.YT_PRIVACY:
        raise HTTPException(status_code=400, detail="privacy မမှန်ဘူး")
    if req.op == "translate" and req.engine == "gemini" and not req.gemini_key.strip():
        raise HTTPException(status_code=400, detail="Gemini key မပါဘူး (Settings မှာ ထည့်ပါ)")
    clean_old()
    with LOCK:
        if any(j["status"] in ("queued", "running") for j in JOBS.values()):
            raise HTTPException(status_code=409, detail="တခြား job တစ်ခု လုပ်နေတုန်းပါ")
        job_id = f"studio_{int(time.time())}_{secrets.token_hex(2)}"
        JOBS[job_id] = {"status": "queued", "stage": "စောင့်နေတယ်", "progress": 0, "created": time.time(), "error": "",
                        "op": req.op, "detail": {}, "result": {"files": [], "links": [], "notes": [], "errors": []}}
        STUDIO_FLAGS[job_id] = {"cancel": False, "pause": False}
    threading.Thread(target=run_studio_job, args=(job_id, req), daemon=True).start()
    return {"job_id": job_id}


def _studio_job(job_id: str):
    j = JOBS.get(job_id) if job_id.startswith("studio_") else None
    if j is None:
        raise HTTPException(status_code=404, detail="Job မတွေ့ပါ")
    return j


@app.get("/studio/jobs/{job_id}")
def studio_status(job_id: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    with LOCK:
        j = _studio_job(job_id)
        return {k: (dict(v) if isinstance(v, dict) else v) for k, v in j.items() if k != "created"}


@app.post("/studio/jobs/{job_id}/{action}")
def studio_control(job_id: str, action: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if action not in ("cancel", "pause", "resume"):
        raise HTTPException(status_code=404, detail="Not found")
    with LOCK:
        j = _studio_job(job_id)
        if j["status"] not in ("queued", "running"):
            raise HTTPException(status_code=409, detail="Job ပြီးသွားပြီ")
    flags = STUDIO_FLAGS.setdefault(job_id, {"cancel": False, "pause": False})
    if action == "cancel":
        flags["cancel"] = True
        flags["pause"] = False
    else:
        flags["pause"] = action == "pause"
    return {"ok": True}


@app.get("/studio/youtube/status")
def studio_yt_status(x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    return so.yt_status()


@app.post("/studio/youtube/auth-link")
def studio_yt_link(x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    try:
        return {"url": so.yt_auth_link()}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/studio/youtube/auth-complete")
def studio_yt_complete(req: YoutubePaste, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    try:
        return so.yt_auth_complete(req.pasted)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/studio/youtube/unlink")
def studio_yt_unlink(x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    so.yt_unlink()
    return so.yt_status()
