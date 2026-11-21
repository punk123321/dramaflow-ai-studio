# AI News Studio backend v2 (run as ONE cell in Google Colab).
#
# What changed from v1:
#  * Jobs: POST /jobs returns a job id at once and the work runs in the
#    background; the app asks GET /jobs/<id> for progress. v1 kept one HTTP
#    request open for the whole video and the free Cloudflare tunnel cuts a
#    request after about 100 seconds, so a 4 minute video could not finish.
#  * Access token: every call except /health needs the header x-app-token.
#    The token is printed with the URL ("URL#TOKEN") so strangers who find the
#    random tunnel address cannot use your Colab (and your keys).
#  * The Gemini and Pexels keys are used for the job and not stored on disk.
#  * Every scene returns start/end seconds, so the app can make an SRT and
#    draw the subtitles itself with a Burmese font (ffmpeg here has none).
#  * ffmpeg errors are reported instead of hidden; all clips use the same
#    video/audio settings so joining them without re-encoding is safe.
#  * strict_grounding is really sent to Gemini; the real length is measured
#    from the voice files and a warning is given when it is not 3 to 5 minutes.
#
# Needs (first Colab cell):  !pip -q install fastapi uvicorn edge-tts google-genai requests
#                            !wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
import asyncio, json, re, secrets, shutil, subprocess, threading, time
from pathlib import Path
from typing import List, Optional

import edge_tts
import requests
import uvicorn
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from google import genai
from google.genai import types
from pydantic import BaseModel

app = FastAPI(title="AI News Studio Backend v2")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

OUT_DIR = Path("/content/news_outputs")
OUT_DIR.mkdir(parents=True, exist_ok=True)
TOKEN = secrets.token_urlsafe(16)
JOBS: dict = {}
LOCK = threading.Lock()
KEEP_SECONDS = 2 * 3600


class NewsRequest(BaseModel):
    topic: str
    gemini_key: str
    pexels_key: str = ""
    aspect_ratio: str = "9:16"  # "9:16" or "16:9"
    duration_min: float = 4.0  # 3.0 to 5.0
    voice_model: str = "my-MM-ThihaNeural"
    news_sources: List[str] = ["Reuters", "BBC Burmese"]
    strict_grounding: bool = True
    master_prompt: str = ""
    gemini_model: str = "gemini-2.5-flash"


def _auth(token: Optional[str]):
    if not token or not secrets.compare_digest(token, TOKEN):
        raise HTTPException(status_code=401, detail="Bad or missing x-app-token")


def _set(job_id: str, **kw):
    with LOCK:
        JOBS[job_id].update(kw)


def generate_script(req: NewsRequest) -> dict:
    client = genai.Client(api_key=req.gemini_key)
    duration = max(3.0, min(5.0, req.duration_min))
    target_words = int(duration * 140)
    scene_count = int(duration * 4)
    sources = ", ".join(req.news_sources)
    base = req.master_prompt or (
        f"You are a professional Myanmar news anchor. Write a {duration}-minute news script "
        f"(~{target_words} words, {scene_count} scenes) about: {req.topic}. Use sources: {sources}."
    )
    compiled = (
        base.replace("{{TOPIC}}", req.topic)
        .replace("{{SOURCES}}", sources)
        .replace("{{DURATION_MIN}}", str(duration))
        .replace("{{TARGET_WORDS}}", str(target_words))
        .replace("{{SCENE_COUNT}}", str(scene_count))
    )
    grounding = (
        "\nSTRICT GROUNDING: use only facts you found with Google Search in the listed sources. "
        "If you are not sure of a fact, a number or a quote, leave it out. Never invent quotes or figures. "
        "Say 'according to <source>' for important claims."
        if req.strict_grounding
        else ""
    )
    prompt = f"""{compiled}{grounding}

Do not call the story 'breaking news' unless it really just happened.
IMPORTANT: Return ONLY valid JSON (no markdown fences) in this exact structure:
{{
  "title": "Myanmar news headline",
  "scenes": [
    {{"narration": "Burmese narration (1-3 sentences)", "keyword": "short English stock-video search keyword", "source": "cited source name"}}
  ]
}}
Generate about {scene_count} scenes, about {target_words} Burmese words of narration in total.
"""
    config = types.GenerateContentConfig(tools=[{"google_search": {}}], temperature=0.7)
    last = None
    for _ in range(2):
        resp = client.models.generate_content(model=req.gemini_model, contents=prompt, config=config)
        raw = (resp.text or "").strip()
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if m:
            try:
                data = json.loads(m.group(0))
                if data.get("scenes"):
                    return data
            except json.JSONDecodeError as e:
                last = e
    raise ValueError(f"Gemini did not return usable JSON ({last or 'no scenes'})")


def fetch_pexels(keyword: str, key: str, ratio: str, save: Path) -> bool:
    if not key:
        return False
    orient = "portrait" if ratio == "9:16" else "landscape"
    try:
        r = requests.get(
            "https://api.pexels.com/videos/search",
            headers={"Authorization": key},
            params={"query": keyword, "orientation": orient, "per_page": 1},
            timeout=15,
        )
        videos = r.json().get("videos", [])
        if not videos:
            return False
        files = videos[0].get("video_files", [])
        if not files:
            return False
        link = next((f["link"] for f in files if f.get("quality") == "hd"), files[0]["link"])
        total = 0
        with requests.get(link, timeout=30, stream=True) as v, open(save, "wb") as out:
            for chunk in v.iter_content(1 << 16):
                total += len(chunk)
                if total > 80 * 1024 * 1024:
                    return False
                out.write(chunk)
        return True
    except Exception:
        return False


async def _tts(text: str, voice: str, out_mp3: Path):
    use = voice if voice.startswith("my-MM-") else "my-MM-ThihaNeural"
    await edge_tts.Communicate(text, use).save(str(out_mp3))


def _run(cmd: list):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("ffmpeg failed: " + (p.stderr or "")[-300:])
    return p.stdout


def audio_seconds(path: Path) -> float:
    out = _run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", str(path)])
    return max(2.0, float(out.strip()))


def render_clip(video_in: Optional[Path], audio_in: Path, out_mp4: Path, ratio: str, dur: float):
    w, h = (720, 1280) if ratio == "9:16" else (1280, 720)
    enc = ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", "30",
           "-c:a", "aac", "-ar", "44100", "-ac", "2", "-shortest", "-t", f"{dur:.2f}"]
    if video_in and video_in.exists():
        _run(["ffmpeg", "-y", "-stream_loop", "-1", "-i", str(video_in), "-i", str(audio_in),
              "-vf", f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h}", *enc, str(out_mp4)])
    else:
        _run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=c=0x0f172a:s={w}x{h}:r=30", "-i", str(audio_in), *enc, str(out_mp4)])


def clean_old():
    now = time.time()
    with LOCK:
        for jid, j in list(JOBS.items()):
            if j["status"] in ("done", "error") and now - j["created"] > KEEP_SECONDS:
                shutil.rmtree(OUT_DIR / jid, ignore_errors=True)
                (OUT_DIR / f"{jid}.mp4").unlink(missing_ok=True)
                del JOBS[jid]


def run_job(job_id: str, req: NewsRequest):
    work = OUT_DIR / job_id
    try:
        work.mkdir(parents=True, exist_ok=True)
        _set(job_id, status="running", stage="Gemini က သတင်းရှာပြီး ဇာတ်ညွှန်း ရေးနေတယ်", progress=5)
        data = generate_script(req)
        scenes = data["scenes"]
        n = len(scenes)
        clips, out_scenes, t = [], [], 0.0
        for i, sc in enumerate(scenes):
            narr = str(sc.get("narration", "")).strip()
            if not narr:
                continue
            _set(job_id, stage=f"Scene {i + 1}/{n}: အသံ၊ ဗီဒီယိုနောက်ခံ၊ render", progress=10 + int(80 * i / n))
            mp3, raw, clip = work / f"s{i}.mp3", work / f"raw_{i}.mp4", work / f"clip_{i}.mp4"
            asyncio.run(_tts(narr, req.voice_model, mp3))
            dur = audio_seconds(mp3)
            has = fetch_pexels(str(sc.get("keyword") or "news"), req.pexels_key, req.aspect_ratio, raw)
            render_clip(raw if has else None, mp3, clip, req.aspect_ratio, dur)
            clips.append(clip)
            out_scenes.append({"narration": narr, "keyword": sc.get("keyword", ""), "source": sc.get("source", ""),
                               "start": round(t, 2), "end": round(t + dur, 2), "stock": has})
            t += dur
        if not clips:
            raise ValueError("Scene မထွက်ပါ")
        _set(job_id, stage="ဗီဒီယိုတွေ ဆက်နေတယ်", progress=94)
        lst = work / "list.txt"
        lst.write_text("\n".join(f"file '{p}'" for p in clips))
        final = OUT_DIR / f"{job_id}.mp4"
        _run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(final)])
        warnings = []
        if not (180 <= t <= 300):
            warnings.append(f"အသံရှည်က {int(t // 60)}:{int(t % 60):02d} ဖြစ်နေတယ် (၃-၅ မိနစ် မဟုတ်ဘူး)")
        if not req.pexels_key:
            warnings.append("Pexels key မပါလို့ နောက်ခံ အရောင်ပြောင်းသက်သက်ပဲ ဖြစ်တယ်")
        _set(job_id, status="done", stage="ပြီးပြီ", progress=100, title=data.get("title", req.topic),
             scenes=out_scenes, seconds=round(t, 1), warnings=warnings, size=final.stat().st_size)
    except Exception as e:  # shown in the app
        _set(job_id, status="error", stage="မအောင်မြင်ဘူး", error=str(e)[:400])
    finally:
        shutil.rmtree(work, ignore_errors=True)


@app.get("/health")
def health():
    return {"status": "ok", "service": "AI News Studio Backend v2"}


@app.post("/jobs")
def create_job(req: NewsRequest, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    clean_old()
    with LOCK:
        if any(j["status"] in ("queued", "running") for j in JOBS.values()):
            raise HTTPException(status_code=409, detail="တခြား job တစ်ခု လုပ်နေတုန်းပါ")
        job_id = f"news_{int(time.time())}_{secrets.token_hex(2)}"
        JOBS[job_id] = {"status": "queued", "stage": "စောင့်နေတယ်", "progress": 0, "created": time.time(),
                        "error": "", "scenes": [], "warnings": []}
    threading.Thread(target=run_job, args=(job_id, req), daemon=True).start()
    return {"job_id": job_id}


@app.get("/jobs/{job_id}")
def job_status(job_id: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    with LOCK:
        j = JOBS.get(job_id)
        if j is None:
            raise HTTPException(status_code=404, detail="Job မတွေ့ပါ")
        out = {k: v for k, v in j.items() if k != "created"}
    if out["status"] == "done":
        out["download_url"] = f"/download/{job_id}.mp4"
    return out


@app.get("/download/{filename}")
def download(filename: str, x_app_token: Optional[str] = Header(default=None)):
    _auth(x_app_token)
    if not re.fullmatch(r"news_\d+_[0-9a-f]{4}\.mp4", filename):
        raise HTTPException(status_code=404, detail="Video not found")
    p = OUT_DIR / filename
    if not p.exists():
        raise HTTPException(status_code=404, detail="Video not found")
    return FileResponse(p, media_type="video/mp4", filename=filename)


def _serve():
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")


threading.Thread(target=_serve, daemon=True).start()
time.sleep(2)

proc = subprocess.Popen(["cloudflared", "tunnel", "--url", "http://localhost:8000"],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print("🚀 Server စတင်နေပါပြီ... Public URL ထွက်လာတာကို ခဏစောင့်ပါ")
for line in proc.stdout:
    m = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", line)
    if m:
        print("\n✅ App ထဲက 'Backend' နေရာမှာ ဒီတစ်ကြောင်းလုံး ကူးထည့်ပါ:")
        print(f"{m.group(0)}#{TOKEN}")
        print("\n(Colab ပိတ်ရင် URL ပြောင်းမယ်၊ ဒီ cell ကို ပြန် run ပြီး အသစ်ယူပါ)")
        break
# keep the cell alive so the server and the tunnel keep running
for _ in proc.stdout:
    pass
