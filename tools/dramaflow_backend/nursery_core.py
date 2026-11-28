"""Children's song video helpers (pure functions, no I/O): karaoke lyrics (.ass with word-by-word fill, .srt), and one
ffmpeg command that joins scene pictures / clips with the finished song. Ported from the user's own "KidsTube Pro" starter
(media.py) and tightened: word times that really add up to the line, safe paths, and one pass instead of many temp files."""
import re
from typing import Dict, List, Optional, Sequence, Tuple

MAX_ITEMS = 60
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp", ".bmp")
_HEADING = re.compile(r"^\s*[\[\(（【].{0,40}[\]\)）】]\s*:?\s*$")
_CJK = re.compile(r"[㐀-鿿]")


def size_for(ratio: str) -> Tuple[int, int]:
    return (720, 1280) if "9:16" in (ratio or "") else (1280, 720)


def lyric_lines(lyrics: str) -> List[str]:
    """The lines that are sung: headings such as [Chorus] and markdown marks are dropped, blank lines too."""
    out = []
    for raw in (lyrics or "").splitlines():
        t = re.sub(r"[*_`#]+", "", raw).strip()
        t = re.sub(r"^[-•]\s+", "", t)
        if not t or _HEADING.match(t):
            continue
        out.append(t)
    return out


def split_words(text: str) -> List[str]:
    """Words to fill one after another. Spaces split Latin / Burmese-with-spaces text; text with no spaces that is Chinese
    splits per character; other text with no spaces (Burmese) stays one piece, because cutting inside a syllable breaks it."""
    t = " ".join((text or "").split())
    if not t:
        return []
    if " " in t:
        return t.split(" ")
    if _CJK.search(t):
        return list(t)
    return [t]


def word_centis(words: Sequence[str], seconds: float) -> List[int]:
    """Centiseconds for each word, in proportion to its length, adding up to exactly the line's length."""
    total = max(1, int(round(max(0.0, seconds) * 100)))
    if not words:
        return []
    weights = [max(1, len(w)) for w in words]
    ws = sum(weights)
    raw = [total * w / ws for w in weights]
    out = [int(r) for r in raw]
    # hand the remaining centiseconds to the words with the biggest fractions
    left = total - sum(out)
    order = sorted(range(len(raw)), key=lambda i: raw[i] - out[i], reverse=True)
    for i in order[:max(0, left)]:
        out[i] += 1
    return out


def proportional_cues(lines: Sequence[str], total: float, pad_ratio: float = 0.06, max_pad: float = 2.0) -> List[dict]:
    """No real timing known: the song is shared by the lines in proportion to their length, with a short quiet start / end.
    Each cue is {"s", "e", "t", "words": [(word, centis)]}."""
    lines = [l for l in lines if l.strip()]
    if not lines or total <= 0:
        return []
    pad = min(max_pad, total * pad_ratio)
    usable = max(0.5, total - 2 * pad)
    weights = [max(4, len(l)) for l in lines]
    ws = sum(weights)
    cues, cur = [], pad
    for l, w in zip(lines, weights):
        d = usable * w / ws
        s, e = cur, min(total, cur + d)
        cur = e
        words = split_words(l)
        cues.append({"s": s, "e": e, "t": l, "words": list(zip(words, word_centis(words, e - s)))})
    return cues


def cues_from_segments(segments) -> List[dict]:
    """Whisper segments (start, end, text, optional words with start / end / word) into cues with word fills."""
    cues = []
    for seg in segments:
        text = (getattr(seg, "text", "") or "").strip()
        s, e = float(getattr(seg, "start", 0.0) or 0.0), float(getattr(seg, "end", 0.0) or 0.0)
        if not text or e <= s:
            continue
        ws = getattr(seg, "words", None) or []
        pairs: List[Tuple[str, int]] = []
        if ws:
            # each word fills from its own start to the next word's start, so gaps are kept inside the line
            for i, w in enumerate(ws):
                wt = (getattr(w, "word", "") or "").strip()
                if not wt:
                    continue
                ws_, we_ = float(getattr(w, "start", s) or s), float(getattr(w, "end", e) or e)
                nxt = float(getattr(ws[i + 1], "start", we_) or we_) if i + 1 < len(ws) else e
                pairs.append((wt, max(1, int(round((max(we_, nxt if nxt > ws_ else we_) - ws_) * 100)))))
        if not pairs:
            words = split_words(text)
            pairs = list(zip(words, word_centis(words, e - s)))
        cues.append({"s": s, "e": e, "t": text, "words": pairs})
    # no overlaps and at least 0.4 s
    for i, c in enumerate(cues):
        if i + 1 < len(cues) and c["e"] > cues[i + 1]["s"]:
            c["e"] = max(c["s"] + 0.1, cues[i + 1]["s"])
        if c["e"] - c["s"] < 0.4:
            c["e"] = c["s"] + 0.4
    return cues


def _ts(sec: float, comma: bool) -> str:
    sec = max(0.0, float(sec))
    if comma:
        ms = int(round(sec * 1000))
        return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"
    cs = int(round(sec * 100))
    return f"{cs // 360000:d}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def srt_text(cues: Sequence[dict]) -> str:
    return "\n".join(f"{i}\n{_ts(c['s'], True)} --> {_ts(c['e'], True)}\n{c['t']}\n" for i, c in enumerate(cues, 1))


def ass_escape(t: str) -> str:
    return t.replace("\\", "/").replace("{", "(").replace("}", ")").replace("\n", " ").strip()


def ass_text(cues: Sequence[dict], width: int, height: int, font: str = "Padauk", size: Optional[int] = None) -> str:
    """Karaoke subtitles: every word fills from white to yellow as it is sung (\\kf). Colours are &HAABBGGRR."""
    size = size or max(36, int(height * 0.075))
    font = re.sub(r"[^\w \-]", "", font or "Padauk") or "Padauk"
    head = (
        "[Script Info]\nScriptType: v4.00+\n"
        f"PlayResX: {width}\nPlayResY: {height}\n\n"
        "[V4+ Styles]\n"
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, "
        "StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
        f"Style: Kids,{font},{size},&H0000E5FF,&H00FFFFFF,&H002B0A3D,&H80000000,-1,0,0,0,100,100,1,0,1,4,2,2,40,40,{int(height * 0.06)},1\n\n"
        "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    )
    ev = []
    for c in cues:
        words = c.get("words") or [(c["t"], max(1, int(round((c["e"] - c["s"]) * 100))))]
        line = " ".join(f"{{\\kf{cs}}}{ass_escape(w)}" for w, cs in words)
        ev.append(f"Dialogue: 0,{_ts(c['s'], False)},{_ts(c['e'], False)},Kids,,0,0,0,,{line}")
    return head + "\n".join(ev) + "\n"


def plan_durations(count: int, song: float, weights: Optional[Sequence[float]] = None, min_s: float = 1.5) -> List[float]:
    """Seconds for each of [count] scenes, adding up to the song length. [weights] (for example seconds the app planned)
    are scaled to fit; without them the scenes are equal. No scene is shorter than [min_s] when the song allows it."""
    if count <= 0 or song <= 0:
        return []
    w = [max(0.0, float(x)) for x in weights] if weights and len(weights) == count else [1.0] * count
    if sum(w) <= 0:
        w = [1.0] * count
    tot = sum(w)
    d = [song * x / tot for x in w]
    floor = min(min_s, song / count)
    short = sum(floor - x for x in d if x < floor)
    spare = sum(x - floor for x in d if x >= floor)
    if short > 0 and spare > 0:
        k = min(1.0, short / spare)
        d = [floor if x < floor else x - (x - floor) * k for x in d]
    return d


def is_image(name: str) -> bool:
    return (name or "").lower().endswith(IMAGE_EXT)


def _f(x: float) -> str:
    return f"{x:.4f}".rstrip("0").rstrip(".") or "0"


def build_slideshow_cmd(ffmpeg: str, items: Sequence[str], audio: str, out: str, durations: Sequence[float], song: float,
                        ratio: str = "16:9", fps: int = 30, sub_path: Optional[str] = None, font: str = "Padauk",
                        nvenc: bool = False, loudnorm: bool = True) -> List[str]:
    """One ffmpeg command: every picture (slow zoom, in and out in turn) or clip (looped if it is shorter than its scene)
    shown for its scene time, joined, the lyrics burned in (.ass karaoke or .srt) and the song as the sound."""
    n = len(items)
    if n < 1 or n > MAX_ITEMS:
        raise ValueError(f"ပုံ/clip 1 ကနေ {MAX_ITEMS} ထိပဲ ရတယ်")
    if len(durations) != n:
        raise ValueError("scene အချိန် အရေအတွက် မကိုက်ဘူး")
    w, h = size_for(ratio)
    fps = max(10, min(60, int(fps)))
    cmd = [ffmpeg, "-y"]
    chains = []
    for i, (src, d) in enumerate(zip(items, durations)):
        frames = max(2, int(round(d * fps)))
        if is_image(src):
            cmd += ["-i", src]
            sw, sh = (int(w * 1.25) // 2) * 2, (int(h * 1.25) // 2) * 2
            if i % 2 == 0:
                z = "min(zoom+0.0008,1.12)"
            else:
                z = "if(eq(on,0),1.12,max(zoom-0.0008,1.0))"
            vf = (f"scale={sw}:{sh}:force_original_aspect_ratio=increase,crop={sw}:{sh},"
                  f"zoompan=z='{z}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s={w}x{h}:fps={fps},setsar=1,format=yuv420p")
        else:
            cmd += ["-stream_loop", "-1", "-t", _f(d + 0.2), "-i", src]
            vf = (f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},fps={fps},"
                  f"trim=duration={_f(d)},setpts=PTS-STARTPTS,setsar=1,format=yuv420p")
        chains.append(f"[{i}:v]{vf}[v{i}]")
    cmd += ["-i", audio]
    cat = "".join(f"[v{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0,tpad=stop_mode=clone:stop_duration=1[vj]"
    graph = ";".join(chains + [cat])
    last = "[vj]"
    if sub_path:
        esc = sub_path.replace("\\", "/").replace(":", "\\:").replace("'", "\\'")
        if sub_path.lower().endswith(".ass"):
            graph += f";{last}ass='{esc}'[vout]"
        else:
            fname = re.sub(r"[^\w -]", "", font) or "Padauk"
            style = f"FontName={fname},FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H002B0A3D,BorderStyle=1,Outline=3,Alignment=2"
            graph += f";{last}subtitles='{esc}':force_style='{style}'[vout]"
        last = "[vout]"
    cmd += ["-filter_complex", graph, "-map", last, "-map", f"{n}:a:0"]
    if loudnorm:
        cmd += ["-af", "loudnorm=I=-14:TP=-1.5:LRA=11"]
    cmd += ["-t", _f(song)]
    if nvenc:
        cmd += ["-c:v", "h264_nvenc", "-preset", "p4", "-rc", "vbr", "-cq", "23", "-b:v", "0"]
    else:
        cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20"]
    cmd += ["-pix_fmt", "yuv420p", "-r", str(fps), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", out]
    return cmd
