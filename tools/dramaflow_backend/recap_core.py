"""Recap job logic with no web framework and no network, so it can be tested.

The app sends GROUPS. Each group already holds the prompt the app built (the
same prompt the manual flow copies to Gemini), an optional contact-sheet JPEG
and, for a whole video, the time range to look at. This module asks Gemini for
each group, reads the "=== PART n ===" parts out of the reply, and makes the
voice for each part. Gemini and the voice are passed in as functions.
"""
import re
import time
from typing import Callable, Dict, List, Optional, Tuple

PART_HEAD = re.compile(r"^[ \t]*[=\-#*\s]*PART\s*(\d+)[=\-#*\s:：]*$", re.IGNORECASE | re.MULTILINE)


def parse_reply(reply: str) -> Dict[int, str]:
    """Part number -> text. Text before the first part line is ignored."""
    text = (reply or "").replace("\r\n", "\n").replace("```", "")
    heads = list(PART_HEAD.finditer(text))
    out: Dict[int, str] = {}
    for i, h in enumerate(heads):
        n = int(h.group(1))
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        body = text[h.end():end].strip()
        if n >= 1 and body:
            out[n] = body
    return out


def gemini_hint(message: str) -> str:
    """What to do next, in Burmese, for a Gemini error text (used by the self-test)."""
    m, low = message, message.lower()
    if "location is not supported" in low or "user location" in low:
        return "Backend (Colab) ရှိတဲ့ နေရာကို Google က မခွင့်ပြုဘူး — Colab ရဲ့ Runtime > Disconnect and delete runtime လုပ်ပြီး အစကနေ ပြန် run ပါ"
    if "404" in m or "NOT_FOUND" in m:
        return "model နာမည် မရှိတော့ဘူး — model ကွက်မှာ gemini-3.8-flash လို နာမည်ပြောင်းပါ"
    if "429" in m or "RESOURCE_EXHAUSTED" in m:
        return "quota ပြည့်နေတယ် — ခဏစောင့်ပါ၊ aistudio.google.com/rate-limit မှာ စစ်ပါ"
    if "503" in m or "UNAVAILABLE" in m:
        return "Google ဘက် model လူသုံးများနေတယ် (ခဏဖြစ်တာ) — ခဏနေ ပြန်စမ်းပါ၊ အရန် model ထည့်ထားရင် Auto က အလိုအလျောက် ပြောင်းစမ်းမယ်"
    if "api key" in low or "400" in m or "403" in m or "PERMISSION" in m:
        return "key မှန်လား၊ Gemini API ဖွင့်ထားလား စစ်ပါ"
    return "မသိတဲ့ အမှား"


def mask_key(message: str, key: str) -> str:
    """Never send the user's API key back in an error text."""
    if key and len(key) >= 8:
        return message.replace(key, "***")
    return message


def part_targets(groups: List[dict]) -> Dict[int, int]:
    """Part number -> how long its video part is (ms), from each group's
    part_ms list (one entry per part, first..last). Missing or wrong-length
    lists give no target for that group."""
    out: Dict[int, int] = {}
    for g in groups:
        ms = g.get("part_ms") or []
        first, last = int(g["first"]), int(g["last"])
        if len(ms) != last - first + 1:
            continue
        for i, v in enumerate(ms):
            try:
                v = int(v)
            except (TypeError, ValueError):
                continue
            if v > 0:
                out[first + i] = v
    return out


GeminiFn = Callable[[dict], str]
TtsFn = Callable[[int, str, int], Tuple[int, str]]  # (part number, text, target ms or 0) -> (milliseconds, file name)
ProgressFn = Callable[[str, int], None]


MAX_SPEEDUP = 1.15  # the voice is sped up at most this much to fit its video part
LONG_WARN = 1.10  # still this much longer than the part after speeding up -> warn
SHORT_WARN = 0.5  # less than this share of the part -> warn
CONTEXT_CHARS = 300


def fit_tempo(audio_ms: int, target_ms: int, max_speed: float = MAX_SPEEDUP) -> float:
    """Speed factor (1.0 = unchanged) that makes a voice that is too long fit
    its video part. Never slows the voice down and never goes above max_speed."""
    if target_ms <= 0 or audio_ms <= 0 or audio_ms <= target_ms * 1.02:
        return 1.0
    return round(min(audio_ms / target_ms, max_speed), 3)


def fit_warning(n: int, audio_ms: int, target_ms: int) -> str:
    """A short Burmese note when the voice of part n does not fit its video
    part, or an empty string."""
    if target_ms <= 0 or audio_ms <= 0:
        return ""
    a, t = audio_ms / 1000, target_ms / 1000
    if audio_ms > target_ms * LONG_WARN:
        return f"အပိုင်း {n}: အသံ {a:.1f} စက္ကန့်၊ ဗီဒီယိုအပိုင်း {t:.1f} စက္ကန့် — အသံက ရှည်နေတယ် (script ကို တိုစေပါ)"
    if audio_ms < target_ms * SHORT_WARN:
        return f"အပိုင်း {n}: အသံ {a:.1f} စက္ကန့်၊ ဗီဒီယိုအပိုင်း {t:.1f} စက္ကန့် — အသံက တိုနေတယ် (အပိုင်းထဲ တိတ်နေမယ်)"
    return ""


def _tail(text: str, limit: int = CONTEXT_CHARS) -> str:
    t = " ".join(text.split())
    return t if len(t) <= limit else t[-limit:]


def with_context(prompt: str, previous_text: str) -> str:
    """Adds how the story stood at the end of the previous group, so names and
    events stay consistent from one request to the next."""
    if not previous_text.strip():
        return prompt
    return (
        prompt.rstrip()
        + "\n\nCONTEXT (the previous part of this recap ended like this. Do not repeat it; "
        + "only keep names and events consistent with it):\n"
        + _tail(previous_text)
        + "\n"
    )


def run_recap(
    groups: List[dict],
    gemini: GeminiFn,
    tts: Optional[TtsFn],
    progress: ProgressFn,
    gap_seconds: float = 6.0,
    sleep: Callable[[float], None] = time.sleep,
) -> dict:
    """Returns {"parts": [{"n", "text", "audio_ms", "audio_file"}], "warnings": [...]}.
    A group that fails is reported as a warning and the rest go on; when nothing
    at all came out, ValueError is raised."""
    warnings: List[str] = []
    texts: Dict[int, str] = {}
    total = max(1, len(groups))
    for gi, g in enumerate(groups):
        first, last = int(g["first"]), int(g["last"])
        progress(f"Gemini က အပိုင်း {first}–{last} ရေးနေတယ်", 5 + int(55 * gi / total))
        if texts:
            g = dict(g, prompt=with_context(g["prompt"], texts[max(texts)]))
        try:
            reply = gemini(g)
        except Exception as e:  # reported, the next group still runs
            warnings.append(f"အပိုင်း {first}–{last} မရဘူး: {str(e)[:160]}")
            continue
        got = parse_reply(reply)
        missing = []
        for n in range(first, last + 1):
            if n in got:
                texts[n] = got[n]
            else:
                missing.append(n)
        if missing:
            warnings.append("Gemini က မရေးပေးတဲ့ အပိုင်း: " + ", ".join(str(n) for n in missing))
        if gi + 1 < len(groups):
            sleep(gap_seconds)
    if not texts:
        raise ValueError("Gemini က script တစ်ပိုင်းမှ မပေးဘူး။ " + (warnings[0] if warnings else ""))
    targets = part_targets(groups)
    parts = []
    order = sorted(texts)
    for idx, n in enumerate(order):
        audio_ms, audio_file = 0, ""
        target = targets.get(n, 0)
        if tts is not None:
            progress(f"အသံ လုပ်နေတယ် {idx + 1}/{len(order)}", 62 + int(36 * idx / len(order)))
            try:
                audio_ms, audio_file = tts(n, texts[n], target)
                w = fit_warning(n, audio_ms, target)
                if w:
                    warnings.append(w)
            except Exception as e:
                warnings.append(f"အပိုင်း {n} အသံ မရဘူး: {str(e)[:120]}")
        parts.append({"n": n, "text": texts[n], "audio_ms": audio_ms, "target_ms": target, "audio_file": audio_file})
    return {"parts": parts, "warnings": warnings}
