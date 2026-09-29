import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_floating.dart';
import 'package:podx/features/companion/companion_performance_panel.dart';
import 'package:podx/features/companion/companion_vrm_engine.dart';
import 'package:podx/features/companion/companion_vrm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBubble extends AskodoxBubblePlatform {
  _FakeBubble({this.supported = true});
  bool canDraw = false;
  final bool supported;
  bool running = false;
  int settingsOpened = 0, starts = 0, stops = 0;

  @override
  Future<AskodoxBubbleStatus> status() async =>
      AskodoxBubbleStatus(supported: supported, canDrawOverlays: canDraw, running: running);
  @override
  Future<void> openPermissionSettings() async => settingsOpened++;
  @override
  Future<bool> start() async {
    starts++;
    running = true;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AskodoxCompanionPerformance.reset();
  });

  group('floating bubble (explicit opt-in, Android permission, no silent start)', () {
    test('turning it on without the permission opens Android settings; nothing runs yet', () async {
      final platform = _FakeBubble();
      final c = AskodoxBubbleController(platform);
      expect(c.state, AskodoxBubbleState.off, reason: 'off by default');
      expect(await c.enable(), AskodoxBubbleState.needsPermission);
      expect(platform.settingsOpened, 1);
      expect(platform.starts, 0);

      // User granted it and came back: the app (in the foreground) starts it.
      platform.canDraw = true;
      await c.sync();
      expect(c.state, AskodoxBubbleState.enabled);
      expect(platform.starts, 1);
      await c.disable();
      expect(platform.stops, 1);
      expect(c.state, AskodoxBubbleState.off);
      await c.sync();
      expect(platform.starts, 1, reason: 'turned off stays off');
    });

    test('unsupported Android versions say so and keep it off', () async {
      final c = AskodoxBubbleController(_FakeBubble(supported: false));
      expect(await c.enable(), AskodoxBubbleState.unsupported);
      expect((await SharedPreferences.getInstance()).getBool('askodox.bubble.enabled'), isFalse);
    });
  });

  group('Human HD (VRM) companion', () {
    test('new states map to the engine body language; choice is stored', () async {
      expect(askodoxVrmMood(AskodoxCompanionMood.understanding), 'thinking');
      expect(askodoxVrmMood(AskodoxCompanionMood.guiding), 'explaining');
      expect(askodoxVrmMood(AskodoxCompanionMood.speaking), 'speaking');
      expect(AskodoxCompanionSettings.fromJson({'companion': 'humanHd'}).companion, AskodoxCompanionSettings.humanHd);
    });

    testWidgets('Human HD renders through the engine; a failure hands over to the light human for the session',
        (tester) async {
      SharedPreferences.setMockInitialValues({'askodox.companion.v1': '{"companion":"humanHd"}'});
      void Function(String)? fail;
      AskodoxCompanionMood? shown;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          askodoxVrmViewBuilderProvider.overrideWithValue(({required mood, required size, required fallback, required onFallback}) {
            fail = onFallback;
            shown = mood;
            return const SizedBox(key: Key('fakeVrm'));
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: AskodoxCompanion(mood: AskodoxCompanionMood.suggesting, size: 96))),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('fakeVrm')), findsOneWidget);
      expect(shown, AskodoxCompanionMood.suggesting, reason: 'driven by the conversation mood');
      fail!('slow');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('fakeVrm')), findsNothing);
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsOneWidget);
      expect(AskodoxCompanionPerformance.vrmFallback, 'slow');
    });
  });

  testWidgets('performance panel reads frames, memory, battery / thermal and startup', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('test/device');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
          'batteryPercent': 76, 'charging': false, 'batteryTempC': 31.5, 'thermalStatus': 1, 'powerSave': false,
          'appPssKb': 204800, 'deviceAvailMb': 2100, 'deviceTotalMb': 5800, 'lowMemory': false, 'sdk': 34,
          'model': 'Test Phone', 'processUptimeMs': 5000,
        });
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AskodoxCompanionPerformancePanel(channel: channel)),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('76%'), findsOneWidget);
    expect(find.text('31.5 °C'), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
    expect(find.text('200 MB'), findsOneWidget);
    expect(find.text('Test Phone · Android SDK 34'), findsOneWidget);
    expect(find.text('Sustainable fps'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPerfCompanion')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('slow frames step down (lighter motion, still pose) and step back up after a quiet period', () {
    final t0 = DateTime(2026, 9, 29, 10);
    AskodoxCompanionPerformance.stepDown();
    AskodoxCompanionPerformance.steppedDownAt = t0;
    expect(AskodoxCompanionPerformance.level, 1);
    AskodoxCompanionPerformance.maybeStepUp(t0.add(const Duration(seconds: 30)));
    expect(AskodoxCompanionPerformance.level, 1, reason: 'not yet');
    AskodoxCompanionPerformance.maybeStepUp(t0.add(const Duration(minutes: 3)));
    expect(AskodoxCompanionPerformance.level, 0, reason: 'tries full quality again when the phone copes');
  });
}
