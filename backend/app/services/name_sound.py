"""Names written in any Indian script match the same name in English letters (owner 2026-11-17: "మురళి మనోహర్ చికెన్"
must find the shop "Murali Manohar Chicken"). No word lists, no per-shop data: the Indic Unicode blocks share one
layout, so ONE table reads Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada and Malayalam.
A name's "sound" is its consonant skeleton, so spelling differences (chicken / chiken, mutton / matan) disappear; a soft
c sounds as s (piece / పీస్, rice / రైస్). Twin of the app's lib/features/pos/domain/pos_name_sound.dart: keep both alike."""
from __future__ import annotations

import re
from typing import List

# offset inside a 128-letter Indic block -> Latin
_LETTERS = {
    0x01: "m", 0x02: "m", 0x03: "h",
    0x05: "a", 0x06: "a", 0x07: "i", 0x08: "i", 0x09: "u", 0x0A: "u", 0x0B: "ru", 0x0D: "e", 0x0E: "e", 0x0F: "e",
    0x10: "ai", 0x11: "o", 0x12: "o", 0x13: "o", 0x14: "au",
}
_CONSONANTS = {
    0x15: "k", 0x16: "kh", 0x17: "g", 0x18: "gh", 0x19: "n", 0x1A: "ch", 0x1B: "ch", 0x1C: "j", 0x1D: "jh", 0x1E: "n",
    0x1F: "t", 0x20: "th", 0x21: "d", 0x22: "dh", 0x23: "n", 0x24: "t", 0x25: "th", 0x26: "d", 0x27: "dh", 0x28: "n",
    0x29: "n", 0x2A: "p", 0x2B: "ph", 0x2C: "b", 0x2D: "bh", 0x2E: "m", 0x2F: "y", 0x30: "r", 0x31: "r", 0x32: "l",
    0x33: "l", 0x34: "l", 0x35: "v", 0x36: "sh", 0x37: "sh", 0x38: "s", 0x39: "h",
    0x58: "k", 0x59: "kh", 0x5A: "g", 0x5B: "z", 0x5C: "d", 0x5D: "dh", 0x5E: "f", 0x5F: "y",
}
_SIGNS = {
    0x3E: "a", 0x3F: "i", 0x40: "i", 0x41: "u", 0x42: "u", 0x43: "ru", 0x44: "ru", 0x45: "e", 0x46: "e", 0x47: "e",
    0x48: "ai", 0x49: "o", 0x4A: "o", 0x4B: "o", 0x4C: "au", 0x4D: "",
}
_FIRST, _LAST = 0x0900, 0x0D7F


def latin(text: str) -> str:
    """Indic letters -> plain Latin (inherent 'a' after a consonant unless a vowel sign or virama follows)."""
    out: List[str] = []
    pending = False  # a consonant waiting for its vowel
    for ch in str(text or ""):
        code = ord(ch)
        if _FIRST <= code <= _LAST:
            off = (code - _FIRST) % 0x80
            if off == 0x3C:  # nukta: the consonant keeps waiting for its vowel
                continue
            if 0x66 <= off <= 0x6F:  # ౬౫ / ६५ -> 65
                if pending:
                    out.append("a")
                pending = False
                out.append(str(off - 0x66))
                continue
            if off in _SIGNS:
                out.append(_SIGNS[off])
                pending = False
                continue
            if pending:
                out.append("a")
                pending = False
            if off in _CONSONANTS:
                out.append(_CONSONANTS[off])
                pending = True
            elif off in _LETTERS:
                out.append(_LETTERS[off])
            else:
                out.append(" ")
            continue
        if pending:
            out.append("a")
            pending = False
        out.append(" " if ch in "‌‍" else ch)
    if pending:
        out.append("a")
    return "".join(out)


def sound(word: str) -> str:
    """The consonant skeleton of one Latin word: chicken -> ckn, matan / mutton -> mtn, murali -> mrl."""
    w = re.sub(r"[^a-z]", "", str(word or "").lower())
    if not w:
        return ""
    for a, b in (("ck", "k"), ("ch", "C"), ("ce", "se"), ("ci", "si"), ("cy", "sy"), ("sh", "s"), ("ph", "f"), ("th", "t"), ("dh", "d"), ("kh", "k"),
                 ("gh", "g"), ("bh", "b"), ("jh", "j"), ("q", "k"), ("x", "ks"), ("z", "j"), ("w", "v"), ("c", "k"),
                 ("C", "c"), ("ee", "i"), ("oo", "u")):
        w = w.replace(a, b)
    w = re.sub(r"(.)\1+", r"\1", w)
    return w[0] + re.sub(r"[aeiouy]", "", w[1:])


def sounds(text: str) -> List[str]:
    """Every word of any text (any script) as its sound, words shorter than 3 letters dropped."""
    words = re.findall(r"[a-z]+", latin(text).lower())
    return [sound(w) for w in words if len(w) >= 3 and len(sound(w)) >= 2]


def same(name_sound: str, said_sound: str) -> bool:
    """Equal, or the said word is the name word plus a short ending ("మటన్‌లో" = mutton + 'lo')."""
    if not name_sound or not said_sound:
        return False
    if name_sound == said_sound:
        return True
    return len(name_sound) >= 3 and said_sound.startswith(name_sound) and len(said_sound) - len(name_sound) <= 2
