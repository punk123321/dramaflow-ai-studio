"""DramaFlow Recap Backend (for Altare, Colab or any computer that runs Python).

Start:  uvicorn main:app --host 0.0.0.0 --port $PORT
Set the environment variable APP_TOKEN to a long secret of your own. Every call
except /health needs it in the header x-app-token. Without it a random token is
made at start and printed in the log.

What it does for the app (Video Recap and Scene Recap):
  POST /recap/jobs             start a job, answers at once with a job id
  GET  /recap/jobs/<id>        progress, then the script parts (and voice files)
  GET  /recap/jobs/<id>/audio/<n>.wav   the voice of part n (24 kHz mono WAV)
The Gemini key arrives with the request, is used for the job and is not stored.
"""
import asyncio
import base64
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

from recap_core import mask_key, run_recap

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


class RecapRequest(BaseModel):
    mode: str = "scenes"  # "scenes" (pictures + dialogue) or "video" (a file already in Gemini)
    gemini_key: str
    gemini_model: str = "gemini-3.8-flash"
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


def _gemini_fn(req: RecapRequest):
    client = genai.Client(api_key=req.gemini_key)

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
        for attempt in range(3):
            try:
                r = client.models.generate_content(
                    model=req.gemini_model, contents=contents, config=types.GenerateContentConfig(temperature=0.5)
                )
                return r.text or ""
            except Exception as e:
                msg = str(e)
                busy = any(k in msg for k in ("429", "503", "RESOURCE_EXHAUSTED", "UNAVAILABLE"))
                if busy and attempt < 2:
                    time.sleep(25 * (attempt + 1))
                    continue
                raise RuntimeError(mask_key(msg, req.gemini_key))
        return ""

    return call


def _tts_fn(job_dir: Path, voice: str):
    use = voice if voice.startswith("my-MM-") else DEFAULT_VOICE

    def make(n: int, text: str):
        mp3, wav = job_dir / f"p{n}.mp3", job_dir / f"p{n}.wav"
        asyncio.run(edge_tts.Communicate(text, use).save(str(mp3)))
        p = subprocess.run(
            [_ffmpeg(), "-y", "-i", str(mp3), "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)],
            capture_output=True,
            text=True,
        )
        mp3.unlink(missing_ok=True)
        if p.returncode != 0 or not wav.exists():
            raise RuntimeError("ffmpeg: " + (p.stderr or "")[-200:])
        with wave.open(str(wav), "rb") as w:
            ms = int(w.getnframes() * 1000 / w.getframerate())
        return ms, wav.name

    return make


def clean_old():
    now = time.time()
    with LOCK:
        for jid, j in list(JOBS.items()):
            if j["status"] in ("done", "error") and now - j["created"] > KEEP_SECONDS:
                shutil.rmtree(OUT_DIR / jid, ignore_errors=True)
                del JOBS[jid]


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
    except Exception as e:  # shown in the app, with the key hidden
        _set(job_id, status="error", stage="မအောင်မြင်ဘူး", error=mask_key(str(e), req.gemini_key)[:400])
        shutil.rmtree(job_dir, ignore_errors=True)


@app.get("/health")
def health():
    return {"status": "ok", "service": "DramaFlow Recap Backend"}


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
            raise HTTPException(status_code=404, detail="Job မတွေ့ပါ")
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
        asyncio.run(edge_tts.Communicate(text, voice, rate=rate).save(str(mp3)))
        p = subprocess.run([_ffmpeg(), "-y", "-i", str(mp3), "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)],
                           capture_output=True, text=True)
        if p.returncode != 0 or not wav.exists():
            raise RuntimeError("ffmpeg: " + (p.stderr or "")[-150:])
        return Response(content=wav.read_bytes(), media_type="audio/wav")
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e)[:200])
    finally:
        shutil.rmtree(d, ignore_errors=True)
