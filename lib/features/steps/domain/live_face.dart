/// Live face check for attendance (owner 2026-11-23: "a photo is just a photo -- they will put a photo of a photo; turn
/// the face left, right, down, up like I saw on Google, free, no paid API").
///
/// The phone reads each camera frame with Google ML Kit (free, on the phone): how many faces, the head's turn (yaw) and
/// tilt (pitch), how open each eye is, and a tracking id for the same face. This file is the pure rule: three moves in a
/// RANDOM order (turn the head, tilt it, blink), each only after looking straight again, by ONE face that stays the same,
/// then a last straight look -- that frame is the still the owner sees. A printed photo or a photo on another phone
/// cannot turn, tilt and blink on cue in an order it did not know.
///
/// Honest limit: this proves a live person in front of the phone; that it is the RIGHT person is the owner's look at the
/// still (and the person's own signed-in phone). A face-to-face match comes later with a licensed model.
library;

import 'dart:math';

enum AskodoxLiveMove { turn, nod, blink }

/// What ML Kit saw in one frame (only the numbers this rule needs; nothing is kept after the check).
class AskodoxFaceSample {
  const AskodoxFaceSample({
    required this.faces,
    this.yaw = 0,
    this.pitch = 0,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.trackingId,
    this.widthPx = 0,
  });

  final int faces;

  /// Head turn left / right (degrees) -- either side counts.
  final double yaw;

  /// Head tilt up / down (degrees) -- either way counts.
  final double pitch;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final int? trackingId;

  /// The face's width in the frame (pixels): a face far away (or a small photo) is asked to come closer.
  final double widthPx;

  bool get straight => yaw.abs() < 12 && pitch.abs() < 12;
  bool get eyesOpen => (leftEyeOpen ?? 1) > 0.6 && (rightEyeOpen ?? 1) > 0.6;
  bool get eyesClosed => leftEyeOpen != null && rightEyeOpen != null && leftEyeOpen! < 0.3 && rightEyeOpen! < 0.3;
}

/// Every move once, in a random order (a recording made for one order fails the next time).
List<AskodoxLiveMove> askodoxLiveMoves([Random? random]) => [...AskodoxLiveMove.values]..shuffle(random ?? Random.secure());

enum AskodoxLiveState { lookStraight, moving, done, failed }

/// What the person should do now (shown big + said), or a hint about the frame.
enum AskodoxLiveHint { none, noFace, oneFace, closer, backStraight }

class AskodoxLiveCheck {
  AskodoxLiveCheck(this.moves, {this.timeout = const Duration(seconds: 40), this.minFacePx = 120});

  final List<AskodoxLiveMove> moves;
  final Duration timeout;
  final double minFacePx;

  DateTime? _start;
  int _index = -1; // -1 = waiting for the first straight look; moves.length = waiting for the last one
  int? _face;
  bool _needStraight = false;
  bool _closed = false;
  AskodoxLiveState state = AskodoxLiveState.lookStraight;
  AskodoxLiveHint hint = AskodoxLiveHint.none;

  /// Moves finished so far (0..moves.length).
  int get done => _index < 0 ? 0 : (_index > moves.length ? moves.length : _index);

  /// The move asked now, null while a straight look is wanted.
  AskodoxLiveMove? get current => _index >= 0 && _index < moves.length && !_needStraight ? moves[_index] : null;

  /// Feeds one frame. Returns true when this frame is the final straight look -- the still to keep.
  bool feed(AskodoxFaceSample s, DateTime at) {
    if (state == AskodoxLiveState.done || state == AskodoxLiveState.failed) return false;
    _start ??= at;
    if (at.difference(_start!) > timeout) {
      state = AskodoxLiveState.failed;
      return false;
    }
    if (s.faces == 0) {
      hint = AskodoxLiveHint.noFace;
      return false;
    }
    if (s.faces > 1) {
      hint = AskodoxLiveHint.oneFace;
      return false;
    }
    if (s.widthPx > 0 && s.widthPx < minFacePx) {
      hint = AskodoxLiveHint.closer;
      return false;
    }
    if (s.trackingId != null) {
      if (_face != null && _face != s.trackingId) {
        // Another face (or the same one lost and found again): start over -- never count moves of two faces as one.
        _index = -1;
        _needStraight = false;
        _closed = false;
        state = AskodoxLiveState.lookStraight;
      }
      _face = s.trackingId;
    }
    hint = AskodoxLiveHint.none;
    if (_index < 0) {
      if (s.straight && s.eyesOpen) {
        _index = 0;
        state = AskodoxLiveState.moving;
      }
      return false;
    }
    if (_needStraight) {
      if (s.straight && s.eyesOpen) {
        _needStraight = false;
      } else {
        hint = AskodoxLiveHint.backStraight;
        return false;
      }
    }
    if (_index >= moves.length) {
      // all moves done: the last straight, eyes-open frame is the still
      if (s.straight && s.eyesOpen) {
        state = AskodoxLiveState.done;
        return true;
      }
      return false;
    }
    final did = switch (moves[_index]) {
      AskodoxLiveMove.turn => s.yaw.abs() > 20,
      AskodoxLiveMove.nod => s.pitch.abs() > 14,
      AskodoxLiveMove.blink => _blink(s),
    };
    if (did) {
      _index++;
      _needStraight = true;
      _closed = false;
    }
    return false;
  }

  bool _blink(AskodoxFaceSample s) {
    if (s.eyesClosed) {
      _closed = true;
      return false;
    }
    return _closed && s.eyesOpen;
  }
}

/// (en, te) words for a move.
(String, String) askodoxLiveMoveWords(AskodoxLiveMove m) => switch (m) {
      AskodoxLiveMove.turn => ('Turn your head to one side', 'తల ఒక వైపు తిప్పండి'),
      AskodoxLiveMove.nod => ('Tilt your head up or down', 'తల పైకి లేదా కిందకి వంచండి'),
      AskodoxLiveMove.blink => ('Close and open your eyes', 'కళ్ళు మూసి తెరవండి'),
    };

(String, String) askodoxLiveHintWords(AskodoxLiveHint h) => switch (h) {
      AskodoxLiveHint.noFace => ('Put your face in the oval', 'ముఖాన్ని ఓవల్ లో పెట్టండి'),
      AskodoxLiveHint.oneFace => ('Only one person, please', 'ఒక్కరే ఉండాలి'),
      AskodoxLiveHint.closer => ('Bring the phone closer', 'ఫోన్ దగ్గరగా పెట్టండి'),
      AskodoxLiveHint.backStraight => ('Now look straight again', 'ఇప్పుడు మళ్ళీ నేరుగా చూడండి'),
      AskodoxLiveHint.none => ('', ''),
    };
