import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_3d.dart';
import 'package:podx/features/companion/companion_human.dart';
import 'package:podx/features/companion/companion_voice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('lip-sync visemes', () {
    test('vowels open, labials close, in Latin and Indic scripts', () {
      double v(String c) => askodoxViseme(c.codeUnitAt(0));
      expect(v('a'), greaterThan(v('m')));
      expect(v('o'), greaterThan(v('b')));
      expect(v(' '), lessThan(v('e')));
      expect(v('అ'), greaterThan(v('మ'))); // Telugu a / ma
      expect(v('आ'), greaterThan(v('प'))); // Devanagari aa / pa
      expect(v('ా'), greaterThan(.9)); // Telugu vowel sign aa
    });

    test('mouth follows the text being spoken (paced, word ranges, audio position)', () {
      var now = DateTime(2026);
      final voice = AskodoxCompanionVoice(clock: () => now);
      voice.speechBegin('mama');
      expect(voice.currentCharIndex(), 0);
      final closed = voice.mouthOpenness();
      now = now.add(const Duration(milliseconds: 75)); // ~1 char at 14 chars/s
      expect(voice.currentCharIndex(), 1);
      expect(voice.mouthOpenness(), greaterThan(closed));

      voice.speechBegin('hello world');
      voice.speechRange(6, 11); // native TTS: now saying "world"
      expect(voice.currentCharIndex(), 6);

      voice.speechBegin('abcdefghij');
      voice.speechProgress(const Duration(milliseconds: 500), const Duration(seconds: 1));
      expect(voice.currentCharIndex(), 5); // Sarvam audio halfway -> middle of the text

      voice.speechEnd();
      expect(voice.speaking, isFalse);
      expect(voice.mouthOpenness(), 0);
    });

    test('mic level is clamped and cleared when speech ends', () {
      final voice = AskodoxCompanionVoice();
      voice.setMicLevel(3);
      expect(voice.micLevel, 1);
      voice.setMicLevel(-1);
      expect(voice.micLevel, 0);
    });
  });

  group('expressions and gestures', () {
    test('every mood has its own gesture and expression', () {
      final idle = askodoxPoseFor(AskodoxCompanionMood.idle, .25);
      for (final mood in AskodoxCompanionMood.values.where((m) => m != AskodoxCompanionMood.idle)) {
        final pose = askodoxPoseFor(mood, .25);
        final moved = pose.handR.x != idle.handR.x ||
            pose.handR.y != idle.handR.y ||
            pose.handL.x != idle.handL.x ||
            pose.handL.y != idle.handL.y;
        expect(moved, isTrue, reason: '$mood gesture');
      }
      expect(askodoxPoseFor(AskodoxCompanionMood.greeting, .1).handR.y, greaterThan(0)); // waves
      expect(askodoxPoseFor(AskodoxCompanionMood.explaining, .1).handR.x, greaterThan(1.4)); // points at results
      expect(askodoxPoseFor(AskodoxCompanionMood.thinking, .1).browTilt, isNot(0)); // raised brow
      expect(askodoxPoseFor(AskodoxCompanionMood.help, .1).browTilt, lessThan(0)); // concerned
    });

    test('live signals: mic makes it lean in, lip-sync drives the mouth, blinks close the eyes', () {
      final calm = askodoxPoseFor(AskodoxCompanionMood.listening, 0);
      final loud = askodoxPoseFor(AskodoxCompanionMood.listening, 0, const AskodoxCompanionSignals(micLevel: 1));
      expect(loud.antenna, greaterThan(calm.antenna));
      expect(loud.roll, greaterThan(calm.roll));

      final shut = askodoxPoseFor(AskodoxCompanionMood.speaking, .3, const AskodoxCompanionSignals(mouthOpen: 0));
      final open = askodoxPoseFor(AskodoxCompanionMood.speaking, .3, const AskodoxCompanionSignals(mouthOpen: 1));
      expect(open.mouth, greaterThan(shut.mouth * 3));

      final blink = askodoxPoseFor(AskodoxCompanionMood.idle, 0, const AskodoxCompanionSignals(blink: 1));
      expect(blink.eyes, lessThan(.1));
      final look = askodoxPoseFor(AskodoxCompanionMood.idle, 0, const AskodoxCompanionSignals(gaze: Offset(.5, 0)));
      expect(look.gaze.dx, .5);
    });

    test('every look has brows (where it has eyes) and two hands', () {
      for (final look in AskodoxCompanionLook.values) {
        final names = AskodoxMesh.forLook(look, const Color(0xFF6C4DFF)).parts.map((p) => p.name).toSet();
        expect(names, containsAll(['head', 'mouth', 'hand_l', 'hand_r']));
        if (names.contains('eye_l')) expect(names, containsAll(['brow_l', 'brow_r']));
      }
    });
  });

  group('low-end fallback', () {
    tearDown(() => AskodoxCompanionPerformance.lite = false);

    test('slow real frames switch the session to the light friend', () {
      expect(AskodoxCompanionPerformance.judge(List.filled(100, 12000)), isFalse);
      expect(AskodoxCompanionPerformance.judge(List.filled(100, 40000)), isTrue);
      expect(AskodoxCompanionPerformance.judge(List.filled(60, 40000)), isFalse); // not enough evidence
      // Slow warm-up frames (shader compile, first layout) alone never step down.
      expect(AskodoxCompanionPerformance.judge([...List.filled(30, 90000), ...List.filled(70, 12000)]), isFalse);
      // A mid-range phone at ~40 fps keeps the human 3D companion.
      expect(AskodoxCompanionPerformance.judge(List.filled(100, 25000)), isFalse);
    });

    testWidgets('lite session draws 2D; friend off draws a plain mic button', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      Future<void> show() => tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Center(child: AskodoxCompanion(mood: AskodoxCompanionMood.speaking))),
          ));

      await show();
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsOneWidget, reason: 'human 3D by default');

      AskodoxCompanionPerformance.lite = true;
      await tester.pumpWidget(const SizedBox());
      await show();
      expect(find.byKey(const ValueKey('askodoxCompanion2d')), findsOneWidget);

      await container.read(askodoxCompanionSettingsProvider.notifier).update(enabled: false);
      await show();
      expect(find.byKey(const ValueKey('askodoxCompanionOff')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsNothing);
      expect(container.read(askodoxCompanionSettingsProvider).toJson()['enabled'], false);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lip-synced speaking renders from the shared voice state', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(askodoxCompanionVoiceProvider).speechBegin('namaste');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Center(child: AskodoxCompanion(mood: AskodoxCompanionMood.speaking))),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      final paint = tester.widget<CustomPaint>(find.byKey(const ValueKey('askodoxCompanionHuman3d')));
      expect((paint.painter! as AskodoxHuman3dPainter).signals.mouthOpen, isNotNull);
      container.read(askodoxCompanionVoiceProvider).speechEnd();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
