"""Cleans narration text before it goes to the voice (Edge TTS).

Pure Python, no network. The goal is only to remove what a voice reads badly:
emoji, markdown marks, brackets with stage directions, and small plain numbers
(0-99), which are spelled as Burmese words. Everything else is left alone, so
the text the user reviewed is the text that is spoken.
"""
import re
import unicodedata

_UNITS = {1: "တစ်", 2: "နှစ်", 3: "သုံး", 4: "လေး", 5: "ငါး", 6: "ခြောက်", 7: "ခုနစ်", 8: "ရှစ်", 9: "ကိုး"}
_TENS = {1: "ဆယ်", 2: "နှစ်ဆယ်", 3: "သုံးဆယ်", 4: "လေးဆယ်", 5: "ငါးဆယ်", 6: "ခြောက်ဆယ်", 7: "ခုနစ်ဆယ်", 8: "ရှစ်ဆယ်", 9: "ကိုးဆယ်"}
_ZERO = "သုံည"


def number_words(n: int) -> str:
    """0..99 in Burmese words: 11 -> ဆယ့်တစ်, 25 -> နှစ်ဆယ့်ငါး."""
    if not 0 <= n <= 99:
        raise ValueError("only 0..99")
    if n == 0:
        return _ZERO
    if n < 10:
        return _UNITS[n]
    t, u = divmod(n, 10)
    if u == 0:
        return _TENS[t]
    # "ဆယ်" becomes "ဆယ့်" (asat after the dot below) when a unit follows
    return _TENS[t][:-1] + "\u1037\u103a" + _UNITS[u]


# A plain 1-2 digit whole number. Not part of a longer number, a decimal, a
# time (12:30), a date or range (3/4, 1-2) or a version (1.2.3).
_NUM = re.compile(r"(?<![\d.,:/\-])\d{1,2}(?![\d.,:/]|-\d)")
_BRACKETS = re.compile(r"[\(\[（【][^\)\]）】\n]{0,80}[\)\]）】]")
_MARKS = re.compile(r"[*_`#>~|=]+")
_SPACES = re.compile(r"[ \t ]+")


def _drop_symbols(text: str) -> str:
    out = []
    for ch in text:
        cat = unicodedata.category(ch)
        if cat in ("So", "Sk", "Cs", "Co", "Cn"):  # emoji, pictographs, private use
            continue
        if ch in "‍️​‌⁠﻿":  # joiners, variation selectors, zero width
            continue
        out.append(ch)
    return "".join(out)


def normalize_for_tts(text: str) -> str:
    """Returns the text the voice should read. Never returns an empty string
    for non-empty input: if everything would be removed, the original is kept."""
    original = (text or "").strip()
    t = original.replace("\r\n", "\n")
    t = _BRACKETS.sub(" ", t)  # (laughs) [music] and similar
    t = _drop_symbols(t)
    t = _MARKS.sub(" ", t)
    t = _NUM.sub(lambda m: number_words(int(m.group(0))), t)
    lines = [_SPACES.sub(" ", ln).strip() for ln in t.split("\n")]
    t = "\n".join(ln for ln in lines if ln)
    return t if t else original
