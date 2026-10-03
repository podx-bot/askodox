import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_3d.dart';
import 'package:podx/features/companion/companion_human.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const phase2 = [
    AskodoxCompanionMood.understanding,
    AskodoxCompanionMood.suggesting,
    AskodoxCompanionMood.guiding,
  ];

  test('every mood has a line in English, Telugu and Hindi', () {
    for (final lang in ['en', 'te', 'hi']) {
      final seen = <String>{};
      for (final mood in AskodoxCompanionMood.values) {
        final line = askodoxCompanionLine(mood, telugu: false, lang: lang, results: 2);
        expect(line.trim(), isNotEmpty, reason: '$lang ${mood.name}');
        seen.add(line);
      }
      expect(seen.length, AskodoxCompanionMood.values.length, reason: '$lang: each state reads differently');
    }
    // Hindi never assumes the companion's gender (no रहा/रही हूँ).
    for (final mood in AskodoxCompanionMood.values) {
      final hi = askodoxCompanionLine(mood, telugu: false, lang: 'hi');
      expect(hi, isNot(matches(RegExp('(रहा|रही) हूँ'))));
    }
    // Telugu stays Telugu whether passed as a flag or a code.
    expect(askodoxCompanionLine(AskodoxCompanionMood.guiding, telugu: true),
        askodoxCompanionLine(AskodoxCompanionMood.guiding, telugu: false, lang: 'te'));
  });

  test('suggesting explains what was understood and that one detail is missing', () {
    expect(askodoxCompanionLine(AskodoxCompanionMood.suggesting, telugu: false, subject: 'split AC repair'),
        'Got it: "split AC repair". One more detail and I can search.');
    expect(askodoxCompanionLine(AskodoxCompanionMood.suggesting, telugu: true, subject: 'చికెన్'), contains('చికెన్'));
    expect(askodoxCompanionLine(AskodoxCompanionMood.suggesting, telugu: false), 'One more detail and I can search.');
  });

  test('new states have their own gesture on the robot and on the human rig', () {
    for (final mood in phase2) {
      final robot = askodoxPoseFor(mood, .3);
      final idle = askodoxPoseFor(AskodoxCompanionMood.idle, .3);
      expect(robot.handR.x != idle.handR.x || robot.handR.y != idle.handR.y || robot.handL.y != idle.handL.y, isTrue,
          reason: mood.name);
      final human = askodoxHumanPoseFor(mood, .3);
      for (final v in [human.handL, human.handR]) {
        expect(v.x.isFinite && v.y.isFinite && v.z.isFinite, isTrue, reason: mood.name);
      }
    }
    // Guiding points toward the results (to the right), like explaining.
    expect(askodoxHumanPoseFor(AskodoxCompanionMood.guiding, 0).handR.x, greaterThan(.9));
    // Understanding holds what was sent with both hands in front.
    final reading = askodoxHumanPoseFor(AskodoxCompanionMood.understanding, 0);
    expect(reading.handL.x.abs(), lessThan(.3));
    expect(reading.handR.x.abs(), lessThan(.3));
  });

  testWidgets('the docked bar shows the state line in the conversation language', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final (lang, mood, expected) in [
      ('hi', AskodoxCompanionMood.guiding, 'आपका अनुरोध भेजा जा रहा है…'),
      ('en', AskodoxCompanionMood.understanding, 'Reading what you sent…'),
      ('te', AskodoxCompanionMood.suggesting, '"AC" అర్థమైంది. ఇంకో వివరం చెబితే వెతుకుతాను.'),
    ]) {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: AskodoxCompanionBar(mood: mood, telugu: lang == 'te', lang: lang, subject: 'AC')),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text(expected), findsOneWidget, reason: '$lang ${mood.name}');
      expect(find.bySemanticsLabel(RegExp('${mood.name}\$')), findsOneWidget);
    }
  });
}
