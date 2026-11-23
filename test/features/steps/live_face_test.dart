import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/steps/domain/live_face.dart';

/// Owner 2026-11-23: "a photo is just a photo -- they will put a photo of a photo". These frames are what ML Kit
/// would report; the rule must pass a live person and stop a still picture.
const straight = AskodoxFaceSample(faces: 1, trackingId: 7, widthPx: 260, leftEyeOpen: .95, rightEyeOpen: .95);
AskodoxFaceSample face({double yaw = 0, double pitch = 0, double eyes = .95, int id = 7}) =>
    AskodoxFaceSample(faces: 1, yaw: yaw, pitch: pitch, leftEyeOpen: eyes, rightEyeOpen: eyes, trackingId: id, widthPx: 260);

AskodoxFaceSample doing(AskodoxLiveMove m) => switch (m) {
      AskodoxLiveMove.turn => face(yaw: -28),
      AskodoxLiveMove.nod => face(pitch: 19),
      AskodoxLiveMove.blink => face(eyes: .05),
    };

void main() {
  final t0 = DateTime(2026, 11, 23, 9);
  DateTime at(int s) => t0.add(Duration(milliseconds: 600 * s));

  test('a live person: straight, then the three moves in the asked order, back straight each time = done', () {
    final moves = askodoxLiveMoves(Random(3));
    expect(moves.toSet(), AskodoxLiveMove.values.toSet(), reason: 'every move once');
    final c = AskodoxLiveCheck(moves);
    var i = 0;
    expect(c.feed(straight, at(i++)), isFalse);
    expect(c.current, moves[0]);
    for (final m in moves) {
      expect(c.feed(doing(m), at(i++)), isFalse);
      if (m == AskodoxLiveMove.blink) expect(c.feed(straight, at(i++)), isFalse, reason: 'eyes open again ends the blink');
      if (c.done < moves.length) {
        expect(c.current, isNull, reason: 'look straight before the next move');
        c.feed(straight, at(i++));
      }
    }
    final last = c.state == AskodoxLiveState.done || c.feed(straight, at(i++));
    expect(last, isTrue);
    expect(c.state, AskodoxLiveState.done);
    expect(c.done, 3);
  });

  test('a photo of a photo never passes: it stays straight and never moves', () {
    final c = AskodoxLiveCheck(askodoxLiveMoves(Random(1)), timeout: const Duration(seconds: 20));
    for (var i = 0; i < 40; i++) {
      expect(c.feed(straight, at(i)), isFalse);
    }
    expect(c.state, AskodoxLiveState.failed, reason: 'time runs out');
  });

  test('a move out of order does not count; two faces, no face and a far face only give a hint', () {
    final c = AskodoxLiveCheck([AskodoxLiveMove.nod, AskodoxLiveMove.turn, AskodoxLiveMove.blink]);
    c.feed(straight, at(0));
    c.feed(face(yaw: 30), at(1)); // turned, but a nod was asked
    expect(c.done, 0);
    c.feed(const AskodoxFaceSample(faces: 2), at(2));
    expect(c.hint, AskodoxLiveHint.oneFace);
    c.feed(const AskodoxFaceSample(faces: 0), at(3));
    expect(c.hint, AskodoxLiveHint.noFace);
    c.feed(const AskodoxFaceSample(faces: 1, trackingId: 7, widthPx: 60), at(4));
    expect(c.hint, AskodoxLiveHint.closer, reason: 'a small face (or a small photo) is asked to come closer');
    c.feed(face(pitch: -20), at(5));
    expect(c.done, 1);
    c.feed(face(yaw: 30), at(6));
    expect(c.done, 1, reason: 'not straight in between: a tilted still cannot count twice');
    expect(c.hint, AskodoxLiveHint.backStraight);
  });

  test('another face half-way starts the check again', () {
    final c = AskodoxLiveCheck([AskodoxLiveMove.turn, AskodoxLiveMove.nod, AskodoxLiveMove.blink]);
    c.feed(straight, at(0));
    c.feed(face(yaw: 25), at(1));
    expect(c.done, 1);
    c.feed(face(id: 9), at(2));
    expect(c.done, 0);
    expect(c.state, AskodoxLiveState.moving, reason: 'the new face looked straight, so it starts at move one');
  });

  test('every move and hint has words in English and Telugu', () {
    for (final m in AskodoxLiveMove.values) {
      final (en, te) = askodoxLiveMoveWords(m);
      expect(en.isNotEmpty && te.isNotEmpty, isTrue);
    }
    for (final h in AskodoxLiveHint.values.where((h) => h != AskodoxLiveHint.none)) {
      final (en, te) = askodoxLiveHintWords(h);
      expect(en.isNotEmpty && te.isNotEmpty, isTrue);
    }
  });
}
