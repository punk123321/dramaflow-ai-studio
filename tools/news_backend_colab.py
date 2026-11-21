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
#  * The Gemini and stock-site keys are used for the job and not stored on disk.
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
    pexels_key: str = ""  # old apps; same as stock_key when stock_provider is "pexels"
    stock_provider: str = "wikimedia"  # "wikimedia" (no key), "pixabay", "unsplash", "pexels"
    stock_key: str = ""
    image_count: int = 20  # pictures for the whole video (picture sources only); 0 = one per scene
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
    {{"narration": "Burmese narration (1-3 sentences)", "keywords": ["2 to 3 DIFFERENT short English photo search phrases for this scene, most specific first"], "source": "cited source name"}}
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


UA = {"User-Agent": "DramaFlowNews/1.0 (personal news video tool)"}
MAX_BYTES = 80 * 1024 * 1024


def _download(link: str, save: Path, headers: Optional[dict] = None) -> bool:
    try:
        total = 0
        with requests.get(link, timeout=30, stream=True, headers=headers or UA) as v, open(save, "wb") as out:
            if v.status_code != 200:
                return False
            for chunk in v.iter_content(1 << 16):
                total += len(chunk)
                if total > MAX_BYTES:
                    return False
                out.write(chunk)
        return total > 1000
    except Exception:
        return False


def fetch_pexels(keyword: str, key: str, ratio: str, save: Path) -> bool:
    if not key:
        return False
    orient = "portrait" if ratio == "9:16" else "landscape"
    try:
        r = requests.get("https://api.pexels.com/videos/search", headers={"Authorization": key},
                         params={"query": keyword, "orientation": orient, "per_page": 1}, timeout=15)
        videos = r.json().get("videos", [])
        files = videos[0].get("video_files", []) if videos else []
        if not files:
            return False
        link = next((f["link"] for f in files if f.get("quality") == "hd"), files[0]["link"])
        return _download(link, save)
    except Exception:
        return False


def fetch_pixabay_video(keyword: str, key: str, ratio: str, save: Path) -> bool:
    if not key:
        return False
    try:
        r = requests.get("https://pixabay.com/api/videos/", params={"key": key, "q": keyword, "per_page": 5, "safesearch": "true"}, timeout=15)
        for hit in r.json().get("hits", []):
            vids = hit.get("videos", {})
            for size in ("medium", "large", "small"):  # medium is ~1280 wide: enough and light
                link = (vids.get(size) or {}).get("url")
                if link and _download(link, save):
                    return True
        return False
    except Exception:
        return False


def fetch_unsplash_image(keyword: str, key: str, ratio: str, save: Path) -> bool:
    if not key:
        return False
    orient = "portrait" if ratio == "9:16" else "landscape"
    try:
        r = requests.get("https://api.unsplash.com/search/photos", headers={"Authorization": f"Client-ID {key}", "Accept-Version": "v1"},
                         params={"query": keyword, "orientation": orient, "per_page": 1}, timeout=15)
        res = r.json().get("results", [])
        if not res:
            return False
        ok = _download(res[0]["urls"]["regular"], save)
        if ok:  # Unsplash asks apps to report the download
            try:
                requests.get(res[0]["links"]["download_location"], headers={"Authorization": f"Client-ID {key}"}, timeout=8)
            except Exception:
                pass
        return ok
    except Exception:
        return False


def fetch_wikimedia_image(keyword: str, key: str, ratio: str, save: Path) -> bool:
    """No key. Pictures only. Licences differ per picture (many need credit)."""
    try:
        r = requests.get("https://commons.wikimedia.org/w/api.php", headers=UA, timeout=15, params={
            "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
            "gsrsearch": f"{keyword} filetype:bitmap", "gsrlimit": 8, "prop": "imageinfo",
            "iiprop": "url|mime|size", "iiurlwidth": 1600})
        pages = (r.json().get("query") or {}).get("pages") or {}
        for pg in sorted(pages.values(), key=lambda p: p.get("index", 99)):
            ii = (pg.get("imageinfo") or [{}])[0]
            if ii.get("mime") not in ("image/jpeg", "image/png") or ii.get("width", 0) < 900:
                continue
            if _download(ii.get("thumburl") or ii.get("url"), save):
                return True
        return False
    except Exception:
        return False


# provider -> (function, kind of file it saves, file extension)
PROVIDERS = {
    "pexels": (fetch_pexels, "video", ".mp4"),
    "pixabay": (fetch_pixabay_video, "video", ".mp4"),
    "unsplash": (fetch_unsplash_image, "image", ".jpg"),
    "wikimedia": (fetch_wikimedia_image, "image", ".jpg"),
}


# ---- many pictures for the whole video ------------------------------------
def images_for(seconds: float, sec_per_image: float, max_per_scene: int = 4) -> int:
    """How many pictures a scene of this length gets (at least 1)."""
    if sec_per_image <= 0:
        return 1
    return max(1, min(max_per_scene, int(round(seconds / sec_per_image))))


def _cands_wikimedia(keyword: str, key: str, ratio: str) -> list:
    r = requests.get("https://commons.wikimedia.org/w/api.php", headers=UA, timeout=15, params={
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
        "gsrsearch": f"{keyword} filetype:bitmap", "gsrlimit": 15, "prop": "imageinfo",
        "iiprop": "url|mime|size", "iiurlwidth": 1600})
    pages = (r.json().get("query") or {}).get("pages") or {}
    out = []
    for pg in sorted(pages.values(), key=lambda p: p.get("index", 99)):
        ii = (pg.get("imageinfo") or [{}])[0]
        if ii.get("mime") in ("image/jpeg", "image/png") and ii.get("width", 0) >= 900:
            out.append((f"wm{pg.get('pageid')}", ii.get("thumburl") or ii.get("url"), None))
    return out


def _cands_unsplash(keyword: str, key: str, ratio: str) -> list:
    if not key:
        return []
    orient = "portrait" if ratio == "9:16" else "landscape"
    r = requests.get("https://api.unsplash.com/search/photos", headers={"Authorization": f"Client-ID {key}", "Accept-Version": "v1"},
                     params={"query": keyword, "orientation": orient, "per_page": 10}, timeout=15)
    return [(f"us{x['id']}", x["urls"]["regular"], x["links"].get("download_location")) for x in r.json().get("results", [])]


def _cands_pixabay_photo(keyword: str, key: str, ratio: str) -> list:
    if not key:
        return []
    orient = "vertical" if ratio == "9:16" else "horizontal"
    r = requests.get("https://pixabay.com/api/", params={"key": key, "q": keyword, "image_type": "photo", "orientation": orient,
                                                          "per_page": 15, "safesearch": "true", "min_width": 900}, timeout=15)
    return [(f"pb{h['id']}", h.get("largeImageURL") or h.get("webformatURL"), None) for h in r.json().get("hits", [])]


IMAGE_SEARCH = {"wikimedia": _cands_wikimedia, "unsplash": _cands_unsplash, "pixabay_photo": _cands_pixabay_photo}


def collect_images(keywords: list, provider: str, key: str, ratio: str, need: int, used: set, work: Path, tag) -> list:
    """Up to [need] different pictures for one scene, never one already used in
    this video. Falls back to Wikimedia (no key) when the chosen source gives nothing."""
    got: list = []
    order = [provider] + (["wikimedia"] if provider != "wikimedia" else [])
    for name in order:
        for kw in keywords:
            if len(got) >= need:
                break
            try:
                cands = IMAGE_SEARCH[name](kw, key if name == provider else "", ratio)
            except Exception:
                cands = []
            for cid, url, loc in cands:
                if cid in used or not url:
                    continue
                path = work / f"img_{tag}_{len(got)}.jpg"
                if _download(url, path):
                    used.add(cid)
                    got.append(path)
                    if loc and name == "unsplash":  # Unsplash asks apps to report a download
                        try:
                            requests.get(loc, headers={"Authorization": f"Client-ID {key}"}, timeout=8)
                        except Exception:
                            pass
                    if len(got) >= need:
                        break
        if got:
            break
    return got


def fetch_media(keyword: str, req: "NewsRequest", base: Path):
    """Tries the chosen provider, then Wikimedia (no key). Returns (path, kind) or (None, "")."""
    chain = [req.stock_provider if req.stock_provider in PROVIDERS else "wikimedia"]
    if chain[0] != "wikimedia":
        chain.append("wikimedia")
    key = req.stock_key or (req.pexels_key if chain[0] == "pexels" else "")
    for name in chain:
        fn, kind, ext = PROVIDERS[name]
        save = base.with_suffix(ext)
        if fn(keyword, key if name == chain[0] else "", req.aspect_ratio, save):
            return save, kind
        save.unlink(missing_ok=True)
    return None, ""


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


def render_clip(media: Optional[Path], kind: str, audio_in: Path, out_mp4: Path, ratio: str, dur: float):
    w, h = (720, 1280) if ratio == "9:16" else (1280, 720)
    enc = ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", "30",
           "-c:a", "aac", "-ar", "44100", "-ac", "2", "-shortest", "-t", f"{dur:.2f}"]
    if media and media.exists() and kind == "video":
        _run(["ffmpeg", "-y", "-stream_loop", "-1", "-i", str(media), "-i", str(audio_in),
              "-vf", f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h}", *enc, str(out_mp4)])
    elif media and media.exists() and kind == "image":
        # Ken Burns: a slow zoom-in on the still picture for the whole scene
        frames = max(30, int(dur * 30) + 2)
        vf = (f"scale={w * 2}:{h * 2}:force_original_aspect_ratio=increase,crop={w * 2}:{h * 2},"
              f"zoompan=z='1+0.25*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s={w}x{h}:fps=30")
        _run(["ffmpeg", "-y", "-i", str(media), "-i", str(audio_in), "-vf", vf, *enc, str(out_mp4)])
    else:
        _run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=c=0x0f172a:s={w}x{h}:r=30", "-i", str(audio_in), *enc, str(out_mp4)])


def render_image_clip(img: Path, out_mp4: Path, ratio: str, dur: float, idx: int):
    """Silent clip: a slow Ken Burns move on one picture (in, out, in, ...)."""
    w, h = (720, 1280) if ratio == "9:16" else (1280, 720)
    frames = max(15, int(round(dur * 30)))
    z = f"1+0.25*on/{frames}" if idx % 2 == 0 else f"1.25-0.25*on/{frames}"
    vf = (f"scale={w * 2}:{h * 2}:force_original_aspect_ratio=increase,crop={w * 2}:{h * 2},"
          f"zoompan=z='{z}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s={w}x{h}:fps=30")
    _run(["ffmpeg", "-y", "-i", str(img), "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
          "-r", "30", "-an", "-t", f"{dur:.2f}", str(out_mp4)])


def render_image_scene(imgs: list, audio_in: Path, out_mp4: Path, ratio: str, dur: float, work: Path, tag):
    """One scene: its pictures one after another, share the voice length equally."""
    k = len(imgs)
    parts = []
    for j, img in enumerate(imgs):
        p = work / f"kb_{tag}_{j}.mp4"
        render_image_clip(img, p, ratio, dur / k, j)
        parts.append(p)
    if k == 1:
        vid = parts[0]
    else:
        lst = work / f"kb_{tag}.txt"
        lst.write_text("\n".join(f"file '{p}'" for p in parts))
        vid = work / f"kb_{tag}_all.mp4"
        _run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(vid)])
    _run(["ffmpeg", "-y", "-i", str(vid), "-i", str(audio_in), "-c:v", "copy", "-c:a", "aac", "-ar", "44100", "-ac", "2",
          "-shortest", "-t", f"{dur:.2f}", str(out_mp4)])


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
        clips, out_scenes, t, stock_used = [], [], 0.0, {}
        use_images = req.stock_provider in IMAGE_SEARCH and req.image_count > 0
        sec_per_image = max(4.0, max(3.0, min(5.0, req.duration_min)) * 60 / max(1, min(60, req.image_count)))
        used_ids: set = set()
        for i, sc in enumerate(scenes):
            narr = str(sc.get("narration", "")).strip()
            if not narr:
                continue
            _set(job_id, stage=f"Scene {i + 1}/{n}: အသံ၊ ဗီဒီယိုနောက်ခံ၊ render", progress=10 + int(80 * i / n))
            mp3, raw, clip = work / f"s{i}.mp3", work / f"raw_{i}", work / f"clip_{i}.mp4"
            asyncio.run(_tts(narr, req.voice_model, mp3))
            dur = audio_seconds(mp3)
            raw_kw = sc.get("keywords") or []
            raw_kw = [raw_kw] if isinstance(raw_kw, str) else raw_kw
            kws = [str(k).strip() for k in raw_kw if str(k).strip()] or [str(sc.get("keyword") or "news")]
            imgs = []
            if use_images:
                imgs = collect_images(kws, req.stock_provider, req.stock_key, req.aspect_ratio,
                                      images_for(dur, sec_per_image), used_ids, work, i)
            if imgs:
                render_image_scene(imgs, mp3, clip, req.aspect_ratio, dur, work, i)
                stock_used["image"] = stock_used.get("image", 0) + len(imgs)
                has = True
            else:
                media, kind = fetch_media(kws[0], req, raw)
                has = media is not None
                render_clip(media, kind, mp3, clip, req.aspect_ratio, dur)
                if has:
                    stock_used[kind] = stock_used.get(kind, 0) + 1
            clips.append(clip)
            out_scenes.append({"narration": narr, "keyword": kws[0], "source": sc.get("source", ""),
                               "start": round(t, 2), "end": round(t + dur, 2), "stock": has, "images": len(imgs)})
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
        if not stock_used:
            warnings.append("နောက်ခံ ဗီဒီယို/ပုံ တစ်ခုမှ မရဘူး (key မှန်လား၊ keyword ရှာမတွေ့လား) — အရောင်နောက်ခံပဲ ဖြစ်တယ်")
        elif stock_used.get("image"):
            warnings.append(f"ပုံ {stock_used['image']} ခု သုံးထားတယ် (scene အလိုက် စဉ်ပေး၊ Ken Burns zoom)။ Wikimedia/Unsplash ပုံတွေမှာ လိုင်စင်/credit လိုနိုင်တယ် — publish မလုပ်ခင် စစ်ပါ")
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
