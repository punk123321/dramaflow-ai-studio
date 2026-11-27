"""Turns the app's render job (the same JSON the phone's own renderer reads) into one ffmpeg command, so a long video
can be made on the Colab machine instead of the phone. Pure functions, no I/O: the caller runs ffmpeg.

Stage 1 covers: cut pieces (in order), speed, flip, whole-picture blur, blur boxes (Censor), the original sound, burned-in
subtitles, output size / fit (original, bars, crop), frame rate and bitrate. Everything else in a job makes `unsupported()`
return a reason, and the caller must refuse the job: a render must never come out missing something that was asked for."""
from typing import Dict, List, Optional, Tuple

MAX_PIECES = 400
MAX_CENSORS = 6


def _num(v, default=0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return float(default)


def _pieces(job: dict) -> List[dict]:
    return [p for p in (job.get("pieces") or []) if isinstance(p, dict)]


def unsupported(job: dict) -> List[str]:
    """Reasons (Burmese) why this job cannot be made here yet. Empty list = it can."""
    why: List[str] = []
    pieces = _pieces(job)
    if not pieces:
        return ["ဗီဒီယို အပိုင်း မရှိဘူး"]
    if len(pieces) > MAX_PIECES:
        why.append(f"အပိုင်း {MAX_PIECES} ထက် မများရဘူး")
    last_end = -1.0
    for p in pieces:
        s, e = _num(p.get("s")), _num(p.get("e"))
        if e <= s:
            why.append("အပိုင်းတစ်ခုရဲ့ အချိန် မမှန်ဘူး")
            break
        if s < last_end:
            why.append("အပိုင်းတွေ အစီအစဉ်မကျ / ထပ်နေလို့ Colab မှာ မရသေးဘူး (မူရင်းအချိန်အတိုင်း စီပါ)")
            break
        last_end = e
    if any(p.get("f") for p in pieces):
        why.append("Freeze Frame")
    if any(p.get("c") for p in pieces):
        why.append("Crop / Zoom reframe")
    if any(_num(p.get("z")) != 0 for p in pieces):
        why.append("Zoom in / out")
    if any(p.get("l") for p in pieces):
        why.append("Filter (အရောင်)")
    if any(not (0.25 <= _num(p.get("sp", 1.0), 1.0) <= 4.0) for p in pieces):
        why.append("Speed ၀.၂၅–၄ အပြင်ဘက်")
    if any(lane for lane in (job.get("voiceLanes") or [])):
        why.append("Narration အသံ (ဖုန်းထဲက အသံဖိုင်တွေကို Colab ဆီ မပို့ရသေးဘူး)")
    if job.get("music"):
        why.append("Background music")
    if job.get("overlays"):
        why.append("Overlay (စာသား / ပုံသဏ္ဌာန် / Fade / Border …)")
    if job.get("splits"):
        why.append("Split Screen")
    if job.get("logo"):
        why.append("Logo")
    if job.get("corners"):
        why.append("ထောင့်စာသား")
    if job.get("fit") == "blur":
        why.append("Blur background (fit)")
    if len(job.get("censors") or []) > MAX_CENSORS:
        why.append(f"Blur box {MAX_CENSORS} ခုထက် များနေတယ်")
    out: List[str] = []
    for w in why:
        if w not in out:
            out.append(w)
    return out


def output_ms(job: dict) -> int:
    """Length of the finished video."""
    total = 0.0
    for p in _pieces(job):
        total += (_num(p.get("e")) - _num(p.get("s"))) / max(0.25, _num(p.get("sp", 1.0), 1.0))
    return int(total)


def atempo_chain(speed: float) -> str:
    """atempo only takes 0.5 to 2.0, so a bigger change is split in steps."""
    if abs(speed - 1.0) < 1e-6:
        return ""
    parts: List[str] = []
    s = speed
    while s > 2.0:
        parts.append("atempo=2.0")
        s /= 2.0
    while s < 0.5:
        parts.append("atempo=0.5")
        s /= 0.5
    parts.append(f"atempo={s:.6f}")
    return ",".join(parts)


def ass_color(argb: int, alpha_override: Optional[int] = None) -> str:
    """The app stores colours as 0xAARRGGBB; ASS wants &HAABBGGRR with the alpha turned round (00 = opaque)."""
    a = (argb >> 24) & 0xFF
    r, g, b = (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF
    inv = 255 - a if alpha_override is None else alpha_override
    return f"&H{inv:02X}{b:02X}{g:02X}{r:02X}"


def subtitle_style(style: dict, font: str = "Padauk") -> str:
    """force_style text for ffmpeg's subtitles filter. The size is a fraction of the picture height; libass reads an
    .srt as a 288-high page, so the font size is that fraction of 288."""
    import re
    font = re.sub(r"[^\w \-]", "", font or "Padauk") or "Padauk"
    frac = min(0.12, max(0.02, _num((style or {}).get("size"), 0.05)))
    size = max(8, int(round(frac * 288)))
    color = int((style or {}).get("color", 0xFFFFFFFF)) & 0xFFFFFFFF
    box = bool((style or {}).get("bg", True))
    top = bool((style or {}).get("top", False))
    align = 6 if top else 2
    if box:
        border = "BorderStyle=3,Outline=2,Shadow=0,OutlineColour=&H99000000,BackColour=&H99000000"
    else:
        border = "BorderStyle=1,Outline=2,Shadow=1,OutlineColour=&H00000000,BackColour=&H80000000"
    return f"FontName={font},FontSize={size},PrimaryColour={ass_color(color)},{border},Alignment={align},MarginV=18"


def srt_text(cues: List[dict]) -> str:
    """The already-cut subtitles (times on the finished video) as .srt text."""
    def t(ms: float) -> str:
        ms = max(0, int(ms))
        return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"
    lines: List[str] = []
    n = 0
    for c in cues or []:
        text = str(c.get("t", "")).strip()
        s, e = _num(c.get("s")), _num(c.get("e"))
        if not text or e <= s:
            continue
        n += 1
        lines += [str(n), f"{t(s)} --> {t(e)}", text, ""]
    return "\n".join(lines)


def escape_filter_path(p: str) -> str:
    return p.replace("\\", "/").replace(":", "\\:").replace("'", "\\'")


def _f(x: float) -> str:
    return f"{x:.6f}".rstrip("0").rstrip(".") or "0"


def censor_boxes(job: dict) -> List[Tuple[float, float, float, float, float, float, float]]:
    """(left, top, width, height, start_s, end_s, sigma) per blur box, as fractions of the SOURCE picture. Times are on the
    original video, like the phone renderer reads them."""
    out = []
    aspect = _num(job.get("aspect"), 16 / 9) or 16 / 9
    for c in job.get("censors") or []:
        w = min(1.0, max(0.03, _num(c.get("w"))))
        h = min(1.0, max(0.03, w * _num(c.get("ar"), 0.5) * aspect))
        x, y = _num(c.get("x"), 0.5), _num(c.get("y"), 0.5)
        l = min(1.0, max(0.0, x - w / 2))
        r = min(1.0, max(0.0, x + w / 2))
        t = min(1.0, max(0.0, y - h / 2))
        b = min(1.0, max(0.0, y + h / 2))
        if r - l < 0.01 or b - t < 0.01:
            raise ValueError("Blur box က ပုံအပြင်ဘက် ရောက်နေတယ်")
        sigma = min(60.0, max(5.0, _num(c.get("str"), 25.0)))
        out.append((l, t, r - l, b - t, _num(c.get("s")) / 1000.0, _num(c.get("e")) / 1000.0, sigma))
    return out


def filter_graph(job: dict, has_audio: bool, srt_path: Optional[str], font: str = "Padauk") -> Tuple[str, str, Optional[str]]:
    """(filter_complex text, video label, audio label or None)."""
    pieces = _pieces(job)
    n = len(pieces)
    fps = int(_num(job.get("fps"), 30)) or 30
    out_w, out_h = int(_num(job.get("outW"))), int(_num(job.get("outH")))
    if out_w < 2 or out_h < 2:
        raise ValueError("ထုတ်မယ့် အရွယ်အစား မမှန်ဘူး")
    out_w, out_h = out_w // 2 * 2, out_h // 2 * 2
    want_audio = has_audio and _num(job.get("originalVolume")) > 0
    vol = min(2.0, max(0.0, _num(job.get("originalVolume"), 1.0)))
    g: List[str] = []

    # 1. Blur boxes, on the source picture and the source clock. The picture is split once; each box is a cut-out that is
    #    blurred and laid back over the same place, only while its time window is on.
    src = "[0:v]"
    boxes = censor_boxes(job)
    if boxes:
        names = "".join(f"[cs{i}]" for i in range(len(boxes)))
        g.append(f"[0:v]split={len(boxes) + 1}[vbase]{names}")
        cur = "[vbase]"
        for i, (l, t, w, h, a, b, sigma) in enumerate(boxes):
            g.append(f"[cs{i}]crop=w=iw*{_f(w)}:h=ih*{_f(h)}:x=iw*{_f(l)}:y=ih*{_f(t)},gblur=sigma={_f(sigma)}:steps=2[cb{i}]")
            g.append(f"{cur}[cb{i}]overlay=x=W*{_f(l)}:y=H*{_f(t)}:enable='between(t,{_f(a)},{_f(b)})'[vo{i}]")
            cur = f"[vo{i}]"
        src = cur

    # 2. One cut per piece (the same decoded picture feeds all of them).
    if n == 1:
        vsrc = [src]
    else:
        g.append(f"{src}split={n}" + "".join(f"[vs{i}]" for i in range(n)))
        vsrc = [f"[vs{i}]" for i in range(n)]
    asrc: List[str] = []
    if want_audio:
        if n == 1:
            asrc = ["[0:a]"]
        else:
            g.append(f"[0:a]asplit={n}" + "".join(f"[as{i}]" for i in range(n)))
            asrc = [f"[as{i}]" for i in range(n)]
    seg: List[str] = []
    for i, p in enumerate(pieces):
        s, e = _num(p.get("s")) / 1000.0, _num(p.get("e")) / 1000.0
        sp = _num(p.get("sp", 1.0), 1.0)
        v = f"{vsrc[i]}trim=start={_f(s)}:end={_f(e)},setpts=(PTS-STARTPTS)/{_f(sp)}"
        if p.get("fh"):
            v += ",hflip"
        if p.get("fv"):
            v += ",vflip"
        bl = _num(p.get("bl"))
        if 0.5 <= bl <= 50:
            v += f",gblur=sigma={_f(bl)}"
        v += f",fps={fps},format=yuv420p[vp{i}]"
        g.append(v)
        seg.append(f"[vp{i}]")
        if want_audio:
            a = f"{asrc[i]}atrim=start={_f(s)}:end={_f(e)},asetpts=PTS-STARTPTS"
            ch = atempo_chain(sp)
            if ch:
                a += "," + ch
            a += f",aresample=44100,volume={_f(vol)}[ap{i}]"
            g.append(a)
            seg.append(f"[ap{i}]")
    if n == 1:
        vlab = seg[0]
        alab = seg[1] if want_audio else None
    else:
        g.append("".join(seg) + f"concat=n={n}:v=1:a={1 if want_audio else 0}[vcat]" + ("[acat]" if want_audio else ""))
        vlab, alab = "[vcat]", ("[acat]" if want_audio else None)

    # 3. Size, then subtitles on the finished picture.
    fit = job.get("fit") or "orig"
    if fit == "bars":
        size = f"scale={out_w}:{out_h}:force_original_aspect_ratio=decrease,pad={out_w}:{out_h}:(ow-iw)/2:(oh-ih)/2:color=black"
    elif fit == "crop":
        size = f"scale={out_w}:{out_h}:force_original_aspect_ratio=increase,crop={out_w}:{out_h}"
    else:
        size = f"scale={out_w}:{out_h}"
    chain = size + ",setsar=1"
    if job.get("burn") and srt_path and (job.get("subtitles") or []):
        chain += f",subtitles='{escape_filter_path(srt_path)}':force_style='{subtitle_style(job.get('subStyle') or {}, font)}'"
    g.append(f"{vlab}{chain}[vout]")
    return ";\n".join(g), "[vout]", alab


def build_cmd(ffmpeg: str, src: str, out: str, job: dict, has_audio: bool, nvenc: bool,
              srt_path: Optional[str] = None, font: str = "Padauk") -> List[str]:
    why = unsupported(job)
    if why:
        raise ValueError("Colab မှာ မထုတ်နိုင်သေးတာ: " + "၊ ".join(why))
    graph, vlab, alab = filter_graph(job, has_audio, srt_path, font)
    kbps = max(300, int(_num(job.get("bitrate"), 4_000_000) / 1000))
    cmd = [ffmpeg, "-y", "-i", src, "-filter_complex", graph, "-map", vlab]
    if alab:
        cmd += ["-map", alab]
    else:
        cmd += ["-an"]
    if nvenc:
        cmd += ["-c:v", "h264_nvenc", "-preset", "p4", "-rc", "vbr", "-b:v", f"{kbps}k", "-maxrate", f"{int(kbps * 1.5)}k"]
    else:
        cmd += ["-c:v", "libx264", "-preset", "veryfast", "-b:v", f"{kbps}k", "-maxrate", f"{int(kbps * 1.5)}k", "-bufsize", f"{kbps * 2}k"]
    cmd += ["-pix_fmt", "yuv420p", "-r", str(int(_num(job.get("fps"), 30)) or 30)]
    if alab:
        cmd += ["-c:a", "aac", "-b:a", "128k"]
    cmd += ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", out]
    return cmd
