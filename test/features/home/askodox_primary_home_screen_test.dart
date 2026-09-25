import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:podx/services/askodox_voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/services/video_analysis_service.dart';

/// Records calls without touching the real microphone/audio plugins, so
/// widget tests can verify the Main Chat voice flow without a device.
class _FakeAskodoxVoiceService extends AskodoxVoiceService {
  _FakeAskodoxVoiceService({this.transcript});
  final String? transcript;
  final List<String> calls = [];

  @override
  Future<void> startListening() async {
    calls.add('startListening');
  }

  @override
  Future<String?> stopAndTranscribe({required String locale}) async {
    calls.add('stopAndTranscribe:$locale');
    return transcript;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
  }

  @override
  Future<bool> speak(
    String text, {
    required Future<void> Function() onSarvamUnavailable,
  }) async {
    calls.add('speak:$text');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.askodox.app/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'primary home orb records in-app instead of opening the external '
      'Google speech-recognition popup', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyChannelCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      legacyChannelCalls.add(call);
      return null;
    });
    // Empty transcript keeps this test hermetic: _send()'s real network
    // call is only reached for non-empty text, matching how the previous
    // version of this test used an empty startVoiceSearch result for the
    // same reason.
    final fakeVoice = _FakeAskodoxVoiceService(transcript: null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AskodoxPrimaryHomeScreen(voiceService: fakeVoice),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxHomeOrb')));
    await tester.pump();

    expect(fakeVoice.calls, ['startListening']);
    expect(tester.takeException(), isNull);

    // Tapping again stops the in-app recording (ASKODOX controls when
    // speech ends, not a platform silence timer) and transcribes it.
    await tester.tap(find.byKey(const Key('askodoxHomeOrb')));
    await tester.pump();

    expect(fakeVoice.calls, ['startListening', 'stopAndTranscribe:en']);
    // The primary Main Chat voice flow never calls the legacy
    // RecognizerIntent-backed native channel method.
    expect(
      legacyChannelCalls.where((call) => call.method == 'startVoiceSearch'),
      isEmpty,
    );
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