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


def mask_key(message: str, key: str) -> str:
    """Never send the user's API key back in an error text."""
    if key and len(key) >= 8:
        return message.replace(key, "***")
    return message


GeminiFn = Callable[[dict], str]
TtsFn = Callable[[int, str], Tuple[int, str]]  # (part number, text) -> (milliseconds, file name)
ProgressFn = Callable[[str, int], None]


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
    parts = []
    order = sorted(texts)
    for idx, n in enumerate(order):
        audio_ms, audio_file = 0, ""
        if tts is not None:
            progress(f"အသံ လုပ်နေတယ် {idx + 1}/{len(order)}", 62 + int(36 * idx / len(order)))
            try:
                audio_ms, audio_file = tts(n, texts[n])
            except Exception as e:
                warnings.append(f"အပိုင်း {n} အသံ မရဘူး: {str(e)[:120]}")
        parts.append({"n": n, "text": texts[n], "audio_ms": audio_ms, "audio_file": audio_file})
    return {"parts": parts, "warnings": warnings}
