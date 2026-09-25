import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/services/video_analysis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.askodox.app/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('primary home orb starts voice inside Main Chat', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startVoiceRecording') return null;
      return null;
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AskodoxPrimaryHomeScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxHomeOrb')));
    await tester.pump();

    // Main Chat voice records in-app for the Sarvam-first backend
    // transcription; it never opens the system RecognizerIntent.
    expect(calls, hasLength(1));
    expect(calls.single.method, 'startVoiceRecording');
    expect(calls.single.arguments, {'languageCode': 'en'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary home attachment menu includes universal video input',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AskodoxPrimaryHomeScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add attachment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('video evidence uses the same request seed contract', () {
    const service = VideoAnalysisService();
    expect(
      service.combinedRequest(
        userText: 'Find help for this video',
        visualSummary: 'A leaking pipe',
        spokenTranscript: 'Water is coming from the joint',
      ),
      contains('Video spoken evidence: Water is coming from the joint'),
    );
  });
}