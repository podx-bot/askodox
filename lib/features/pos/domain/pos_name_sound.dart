/// A name said in any Indian script matches the same name written in English letters, and back
/// (owner 2026-11-24: "రెండు చికెన్ బిర్యానీ" said at the counter must find "Chicken Biryani").
///
/// The Dart twin of backend `app/services/name_sound.py` -- keep the two tables and rules the same.
/// No word lists and no per-shop data: the Indic Unicode blocks share one layout, so ONE table reads
/// Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada and Malayalam. A word's "sound"
/// is its consonant skeleton, so spelling differences disappear (chicken / chiken / చికెన్ -> ckn,
/// biryani / biriyani / బిర్యానీ / बिरयानी -> brn, piece / పీస్ -> ps).
library;

// offset inside a 128-letter Indic block -> Latin
const _letters = {
  0x01: 'm', 0x02: 'm', 0x03: 'h',
  0x05: 'a', 0x06: 'a', 0x07: 'i', 0x08: 'i', 0x09: 'u', 0x0A: 'u', 0x0B: 'ru', 0x0D: 'e', 0x0E: 'e', 0x0F: 'e',
  0x10: 'ai', 0x11: 'o', 0x12: 'o', 0x13: 'o', 0x14: 'au',
};
const _consonants = {
  0x15: 'k', 0x16: 'kh', 0x17: 'g', 0x18: 'gh', 0x19: 'n', 0x1A: 'ch', 0x1B: 'ch', 0x1C: 'j', 0x1D: 'jh', 0x1E: 'n',
  0x1F: 't', 0x20: 'th', 0x21: 'd', 0x22: 'dh', 0x23: 'n', 0x24: 't', 0x25: 'th', 0x26: 'd', 0x27: 'dh', 0x28: 'n',
  0x29: 'n', 0x2A: 'p', 0x2B: 'ph', 0x2C: 'b', 0x2D: 'bh', 0x2E: 'm', 0x2F: 'y', 0x30: 'r', 0x31: 'r', 0x32: 'l',
  0x33: 'l', 0x34: 'l', 0x35: 'v', 0x36: 'sh', 0x37: 'sh', 0x38: 's', 0x39: 'h',
  0x58: 'k', 0x59: 'kh', 0x5A: 'g', 0x5B: 'z', 0x5C: 'd', 0x5D: 'dh', 0x5E: 'f', 0x5F: 'y',
};
const _signs = {
  0x3E: 'a', 0x3F: 'i', 0x40: 'i', 0x41: 'u', 0x42: 'u', 0x43: 'ru', 0x44: 'ru', 0x45: 'e', 0x46: 'e', 0x47: 'e',
  0x48: 'ai', 0x49: 'o', 0x4A: 'o', 0x4B: 'o', 0x4C: 'au', 0x4D: '',
};
const _first = 0x0900;
const _last = 0x0D7F;

/// Indic letters -> plain Latin (inherent 'a' after a consonant unless a vowel sign or virama follows).
String askodoxLatin(String text) {
  final out = StringBuffer();
  var pending = false; // a consonant waiting for its vowel
  for (final code in text.runes) {
    if (code >= _first && code <= _last) {
      final off = (code - _first) % 0x80;
      if (off == 0x3C) continue; // nukta: the consonant keeps waiting for its vowel
      if (off >= 0x66 && off <= 0x6F) {
        // ౬౫ / ६५ -> 65
        if (pending) out.write('a');
        pending = false;
        out.write('${off - 0x66}');
        continue;
      }
      final sign = _signs[off];
      if (sign != null) {
        out.write(sign);
        pending = false;
        continue;
      }
      if (pending) {
        out.write('a');
        pending = false;
      }
      final consonant = _consonants[off];
      final letter = _letters[off];
      if (consonant != null) {
        out.write(consonant);
        pending = true;
      } else if (letter != null) {
        out.write(letter);
      } else {
        out.write(' ');
      }
      continue;
    }
    if (pending) {
      out.write('a');
      pending = false;
    }
    out.write(code == 0x200C || code == 0x200D ? ' ' : String.fromCharCode(code));
  }
  if (pending) out.write('a');
  return out.toString();
}

/// Only the digits of any Indic script become ASCII ("౨ కిలో" -> "2 కిలో"); letters stay as they are.
String askodoxLatinDigits(String text) => String.fromCharCodes([
      for (final code in text.runes)
        if (code >= _first && code <= _last && (code - _first) % 0x80 >= 0x66 && (code - _first) % 0x80 <= 0x6F)
          0x30 + (code - _first) % 0x80 - 0x66
        else
          code,
    ]);

const _soundSteps = [
  ('ck', 'k'), ('ch', 'C'), ('ce', 'se'), ('ci', 'si'), ('cy', 'sy'), ('sh', 's'), ('ph', 'f'), ('th', 't'),
  ('dh', 'd'), ('kh', 'k'), ('gh', 'g'), ('bh', 'b'), ('jh', 'j'), ('q', 'k'), ('x', 'ks'), ('z', 'j'), ('w', 'v'),
  ('c', 'k'), ('C', 'c'), ('ee', 'i'), ('oo', 'u'),
];

/// The consonant skeleton of one Latin word: chicken -> ckn, matan / mutton -> mtn, piece -> ps, fry -> fr.
String askodoxSound(String word) {
  var w = word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (w.isEmpty) return '';
  for (final (from, to) in _soundSteps) {
    w = w.replaceAll(from, to);
  }
  w = w.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  return w[0] + w.substring(1).replaceAll(RegExp('[aeiouy]'), '');
}

/// Every word of [text] (any script) as a sound; a number stays itself ("Chicken 65" -> [ckn, 65]).
/// Words whose sound is shorter than 2 letters carry no name and are dropped.
List<String> askodoxSoundWords(String text) => [
      for (final m in RegExp(r'[a-z]+|\d+').allMatches(askodoxLatin(text.toLowerCase())))
        if (RegExp(r'^\d').hasMatch(m[0]!)) m[0]! else askodoxSound(m[0]!),
    ].where((s) => s.length >= 2 || RegExp(r'^\d+$').hasMatch(s)).toList();

/// One heard word is this name word: same sound, or the name word plus a short ending ("మటన్‌లో" = mutton + 'lo').
/// Two-letter sounds (fry, dum, pack) must be equal; numbers must be equal.
bool askodoxSameSound(String nameSound, String saidSound) {
  if (nameSound.isEmpty || saidSound.isEmpty) return false;
  if (nameSound == saidSound) return true;
  if (RegExp(r'^\d').hasMatch(nameSound) || RegExp(r'^\d').hasMatch(saidSound)) return false;
  return nameSound.length >= 3 && saidSound.startsWith(nameSound) && saidSound.length - nameSound.length <= 2;
}
