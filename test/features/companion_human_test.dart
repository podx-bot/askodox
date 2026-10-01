import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_3d.dart';
import 'package:podx/features/companion/companion_avatar_packs.dart';
import 'package:podx/features/companion/companion_human.dart';
import 'package:podx/features/companion/companion_human2d.dart';
import 'package:podx/features/companion/companion_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _dist(AskodoxVec3 a, AskodoxVec3 b) {
  final d = a - b;
  return math.sqrt(d.dot(d));
}

int _paintTriangles(AskodoxHuman3dPainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(160, 160));
  recorder.endRecording().dispose();
  return AskodoxHuman3dPainter.lastTriangles;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AskodoxCompanionPerformance.level = 0;
  });

  group('human rig', () {
    test('every persona is a real 3D human on ONE shared rig (face, hair, hands), sized for phones', () {
      for (final persona in AskodoxPersona.values) {
        final mesh = AskodoxHumanRig.build(AskodoxHumanStyle.of(persona));
        final names = mesh.parts.map((p) => p.name).toSet();
        expect(mesh.isHuman, isTrue);
        expect(names, containsAll([
          'head', 'body_torso', 'body_neck', 'face_eye_l', 'face_eye_r', 'face_iris_l', 'face_iris_r',
          'face_brow_l', 'face_brow_r', 'face_nose', 'face_mouth', 'face_lip_upper', 'face_lip_lower',
          'head_hair_nape', 'hand_l', 'hand_r',
        ]), reason: '$persona');
        expect(mesh.triangleCount, inInclusiveRange(1500, 6000), reason: '$persona: real mesh, phone-sized');
      }
    });

    test('personas differ by look only (outfit + accessories), not by behaviour', () {
      Set<String> parts(AskodoxPersona p) =>
          AskodoxHumanRig.build(AskodoxHumanStyle.of(p)).parts.map((x) => x.name).toSet();
      expect(parts(AskodoxPersona.financeAdvisor), containsAll(['face_glasses_l', 'body_tie']));
      expect(parts(AskodoxPersona.travelGuide), contains('head_hat_brim'));
      expect(parts(AskodoxPersona.serviceExpert), contains('head_cap_brim'));
      expect(parts(AskodoxPersona.techExpert), contains('face_headset_mic'));
      expect(parts(AskodoxPersona.wellnessSupport), contains('body_scrubs'));
      expect(parts(AskodoxPersona.lifestyleFriend), contains('head_earring_l'));
      expect(parts(AskodoxPersona.educationMentor), contains('head_hair_back'));
      final outfits = {for (final p in AskodoxPersona.values) AskodoxHumanStyle.of(p).outfit.toARGB32()};
      expect(outfits.length, AskodoxPersona.values.length, reason: 'each persona is visually distinct');
      for (final p in AskodoxPersona.values) {
        expect(askodoxPersonaLabel(p), isNotEmpty);
        expect(askodoxPersonaLabel(p, telugu: true), isNot(askodoxPersonaLabel(p)));
      }
    });

    test('arms are jointed: two-bone IK keeps bone lengths', () {
      const s = AskodoxHumanRig.shoulderR;
      for (final hand in const [AskodoxVec3(.3, -1.08, -.6), AskodoxVec3(.82, .42, -.42), AskodoxVec3(.1, .18, -.6)]) {
        final elbow = askodoxElbow(s, hand, left: false);
        expect(_dist(s, elbow), closeTo(AskodoxHumanRig.upperArm, 1e-6));
        final reach = _dist(s, hand);
        if (reach < AskodoxHumanRig.upperArm + AskodoxHumanRig.forearm) {
          expect(_dist(elbow, hand), closeTo(AskodoxHumanRig.forearm, 1e-6));
        }
      }
    });
  });

  group('states, expressions and gestures', () {
    test('each state has its own gesture', () {
      AskodoxHumanPose p(AskodoxCompanionMood m, [double t = .1]) => askodoxHumanPoseFor(m, t);
      final idle = p(AskodoxCompanionMood.idle);
      expect(p(AskodoxCompanionMood.greeting).handR.y, greaterThan(.3), reason: 'waves');
      expect(p(AskodoxCompanionMood.listening).handL.y, greaterThan(.3), reason: 'hand at the ear');
      final think = p(AskodoxCompanionMood.thinking).handR;
      expect(think.y, inInclusiveRange(0, .35), reason: 'hand at the chin');
      expect(p(AskodoxCompanionMood.explaining).handR.x, greaterThan(.9), reason: 'points at the results');
      final happy = p(AskodoxCompanionMood.success);
      expect(happy.handL.y > 0 && happy.handR.y > 0, isTrue, reason: 'both hands up');
      expect(happy.smile, 1);
      final concern = p(AskodoxCompanionMood.help);
      expect(concern.shrug, greaterThan(0));
      expect(concern.smile, lessThan(0));
      expect(concern.face.browTilt, lessThan(0), reason: 'concerned brows');
      final a = p(AskodoxCompanionMood.speaking, .1), b = p(AskodoxCompanionMood.speaking, .6);
      expect(a.handL.y != b.handL.y || a.handR.y != b.handR.y, isTrue, reason: 'talks with the hands');
      expect(idle.handL.y, lessThan(-.9), reason: 'rests');
    });

    test('lip-sync, blink and gaze from the existing voice hooks drive the face', () {
      final closed = askodoxHumanPoseFor(AskodoxCompanionMood.speaking, .2, const AskodoxCompanionSignals(mouthOpen: 0));
      final open = askodoxHumanPoseFor(AskodoxCompanionMood.speaking, .2, const AskodoxCompanionSignals(mouthOpen: 1));
      expect(open.face.mouth, greaterThan(closed.face.mouth * 3));
      final blink = askodoxHumanPoseFor(AskodoxCompanionMood.idle, 0, const AskodoxCompanionSignals(blink: 1));
      expect(blink.face.eyes, lessThan(.1));
      final look = askodoxHumanPoseFor(AskodoxCompanionMood.idle, 0, const AskodoxCompanionSignals(gaze: Offset(.6, .2)));
      expect(look.face.gaze, const Offset(.6, .2));
      final loud = askodoxHumanPoseFor(AskodoxCompanionMood.listening, 0, const AskodoxCompanionSignals(micLevel: 1));
      final calm = askodoxHumanPoseFor(AskodoxCompanionMood.listening, 0);
      expect(loud.lean, greaterThan(calm.lean), reason: 'leans in when the user speaks louder');
    });

    test('every persona x state paints a bounded number of lit triangles', () {
      for (final persona in AskodoxPersona.values) {
        final mesh = AskodoxHumanRig.build(AskodoxHumanStyle.of(persona));
        for (final mood in AskodoxCompanionMood.values) {
          final drawn = _paintTriangles(AskodoxHuman3dPainter(mesh: mesh, mood: mood, t: .3));
          expect(drawn, inInclusiveRange(700, 4000), reason: '$persona/$mood');
        }
      }
    });

    test('a broken mesh reports an error instead of crashing (widget falls back)', () {
      var failed = false;
      final broken = AskodoxMesh([
        AskodoxMeshPart('head', const [AskodoxVec3(0, 0, 0)], const [0, 5, 9], Colors.brown),
      ], meta: const {'rig': 'human'});
      final recorder = ui.PictureRecorder();
      AskodoxHuman3dPainter(mesh: broken, mood: AskodoxCompanionMood.idle, t: 0, onError: () => failed = true)
          .paint(Canvas(recorder), const Size(100, 100));
      recorder.endRecording().dispose();
      expect(failed, isTrue);
    });

    test('rendering stays light: average frame paint time on this machine', () {
      final mesh = AskodoxHumanRig.build(AskodoxHumanStyle.of(AskodoxPersona.financeAdvisor));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 60; i++) {
        _paintTriangles(AskodoxHuman3dPainter(mesh: mesh, mood: AskodoxCompanionMood.speaking, t: i / 60));
      }
      final perFrameMs = watch.elapsedMicroseconds / 60 / 1000;
      // ignore: avoid_print
      print('HUMAN3D paint ${perFrameMs.toStringAsFixed(2)} ms/frame, ${AskodoxHuman3dPainter.lastTriangles} triangles');
      expect(perFrameMs, lessThan(40));
    });
  });

  group('selection, automatic persona and fallbacks', () {
    Future<void> show(WidgetTester tester, ProviderContainer c, {AskodoxCompanionMood mood = AskodoxCompanionMood.idle}) =>
        tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(home: Center(child: AskodoxCompanion(mood: mood))),
        ));

    testWidgets('default is the approved natural human companion (2D photo states), the same everywhere',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman2d')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsNothing, reason: 'no low-poly default');
      // The brain's domain no longer swaps the face: one identity.
      c.read(askodoxCompanionDomainProvider.notifier).state = 'SERVICE';
      await tester.pump();
      expect(find.byKey(const ValueKey('askodoxCompanionHuman2d')), findsOneWidget);
      expect(askodoxPersonaForDomain('LEDGER'), AskodoxPersona.financeAdvisor);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a chosen persona is kept (also across restarts); invalid stored values fall back to Automatic',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(askodoxCompanionSettingsProvider.notifier).update(companion: AskodoxPersona.financeAdvisor.name);
      c.read(askodoxCompanionDomainProvider.notifier).state = 'SERVICE';
      await show(tester, c);
      expect(find.bySemanticsLabel(RegExp('Finance Advisor')), findsOneWidget, reason: 'a manual choice wins');

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      restarted.read(askodoxCompanionSettingsProvider);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(restarted.read(askodoxCompanionSettingsProvider).companion, 'financeAdvisor');
      expect(AskodoxCompanionSettings.fromJson({'companion': 'dragon'}).companion, AskodoxCompanionSettings.automatic);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Robot (Lite) only when chosen; still photo, slow phone and friend off keep the same human',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(askodoxCompanionSettingsProvider.notifier);

      await n.update(companion: AskodoxCompanionSettings.robotLite);
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanion3d')), findsOneWidget);

      await n.update(companion: AskodoxCompanionSettings.automatic, render3d: false);
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman2d')), findsOneWidget, reason: 'still photo, same face');

      await n.update(render3d: true);
      for (final level in [1, 2]) {
        AskodoxCompanionPerformance.level = level;
        await show(tester, c);
        expect(find.byKey(const ValueKey('askodoxCompanionHuman2d')), findsOneWidget, reason: 'level $level');
      }
      AskodoxCompanionPerformance.level = 0;

      await n.update(enabled: false);
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanionOff')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an experimental 3D pick that fails comes back to the approved human, never the robot',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(askodoxCompanionSettingsProvider.notifier).update(companion: AskodoxPersona.techExpert.name);
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsOneWidget, reason: 'explicit 3D pick');
      AskodoxCompanionPerformance.level = 2;
      await show(tester, c);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsOneWidget, reason: 'same face, still pose');
      AskodoxCompanionPerformance.level = 0;
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the docked companion is present in every state, idle included', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      for (final mood in AskodoxCompanionMood.values) {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(home: Scaffold(body: AskodoxCompanionBar(mood: mood, telugu: false))),
        ));
        expect(find.byType(AskodoxCompanion), findsOneWidget, reason: '$mood');
        expect(tester.getSize(find.byType(AskodoxCompanion)).height, greaterThanOrEqualTo(64));
      }
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: AskodoxCompanionBar(mood: AskodoxCompanionMood.idle, telugu: false))),
      ));
      expect(find.byType(AskodoxCompanion), findsOneWidget, reason: 'idle keeps the companion');
      expect(find.text('Anything else? Just ask.'), findsNothing,
          reason: 'APK 1274: no generic follow-up bubble after every reply');
      expect(find.byKey(const Key('askodoxCompanionLine')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('background pauses the companion; foreground resumes it', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await show(tester, c, mood: AskodoxCompanionMood.speaking);
      double t() => tester.widget<AskodoxHuman2d>(find.byType(AskodoxHuman2d)).t;
      await tester.pump(const Duration(milliseconds: 300));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final frozen = t();
      await tester.pump(const Duration(milliseconds: 500));
      expect(t(), frozen, reason: 'no animation in the background');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(t(), isNot(frozen), reason: 'animates again in the foreground');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Profile picker: Automatic, 9 humans, Robot (Lite), 3D off -- choice remembered', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: AskodoxCompanionPicker(telugu: false))),
      ));
      for (final id in ['auto', ...AskodoxPersona.values.map((p) => p.name), 'robot', 'off3d']) {
        final option = find.byKey(ValueKey('askodoxPersona-$id'));
        await tester.scrollUntilVisible(option, 200, scrollable: find.byType(Scrollable).first);
        expect(option, findsOneWidget, reason: id);
      }
      final tech = find.byKey(const ValueKey('askodoxPersona-techExpert'));
      await tester.scrollUntilVisible(tech, -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(tech);
      await tester.pump();
      expect(c.read(askodoxCompanionSettingsProvider).companion, 'techExpert');
      final robot = find.byKey(const ValueKey('askodoxPersona-robot'));
      await tester.scrollUntilVisible(robot, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(robot);
      await tester.pump();
      expect(find.byKey(const ValueKey('askodoxLook-friendlyFace')), findsOneWidget, reason: 'robot looks appear');
      await tester.tap(find.byKey(const ValueKey('askodoxPersona-off3d')));
      await tester.pump();
      expect(c.read(askodoxCompanionSettingsProvider).render3d, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('optional avatar packs (lazy, validated, never required)', () {
    Map<String, Object?> pack({int extraTriangles = 0, bool human = true, bool mouth = true}) {
      final base = AskodoxHumanRig.build(AskodoxHumanStyle.of(AskodoxPersona.friendlyAssistant));
      return {
        'meta': {'rig': human ? 'human' : 'robot'},
        'parts': [
          for (final p in base.parts)
            if (mouth || p.name != 'face_mouth')
              {
                'name': p.name,
                'color': '#${(p.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                'vertices': [for (final v in p.vertices) [v.x, v.y, v.z]],
                'triangles': [...p.triangles, for (var i = 0; i < extraTriangles; i++) ...[0, 1, 2]],
              },
        ],
      };
    }

    test('a valid pack in the rig format loads; anything else is rejected', () {
      expect(AskodoxAvatarPacks.parse(jsonEncode(pack()))?.isHuman, isTrue);
      expect(AskodoxAvatarPacks.parse(jsonEncode(pack(human: false))), isNull);
      expect(AskodoxAvatarPacks.parse(jsonEncode(pack(mouth: false))), isNull, reason: 'needs the lip-sync part');
      expect(AskodoxAvatarPacks.parse(jsonEncode(pack(extraTriangles: 1000))), isNull, reason: 'too heavy for phones');
      expect(AskodoxAvatarPacks.parse('not json'), isNull);
    });

    test('downloads only when a pack server is configured', () async {
      expect(await AskodoxAvatarPacks.load(AskodoxPersona.techExpert, base: ''), isNull);
      final requested = <Uri>[];
      final mesh = await AskodoxAvatarPacks.load(
        AskodoxPersona.techExpert,
        base: 'https://cdn.example/avatars',
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response(jsonEncode(pack()), 200);
        }),
      );
      expect(requested.single.toString(), 'https://cdn.example/avatars/techExpert.json');
      expect(mesh?.isHuman, isTrue);
      final failed = await AskodoxAvatarPacks.load(AskodoxPersona.techExpert,
          base: 'https://cdn.example/avatars', client: MockClient((_) async => http.Response('', 404)));
      expect(failed, isNull, reason: 'procedural rig stays');
    });
  });
}
