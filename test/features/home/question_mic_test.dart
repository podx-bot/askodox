import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:podx/features/home/presentation/question_mic.dart';
import 'package:podx/services/voice_transcription_service.dart';

class _Stt extends VoiceTranscriptionService {
  const _Stt();
  @override
  Future<String?> transcribeFile(String path, {required String locale}) async => 'does it inflate bike tyres';
}

void main() {
  testWidgets('the centre mic records INTO the video question (never closes the page)', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.askodox.app/device'),
        (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'startVoiceRecording' => true,
        'stopVoiceRecording' => '/tmp/q.m4a',
        _ => null,
      };
    });
    final heard = <String>[];
    late ProviderContainer container;
    final show = ValueNotifier(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxVoiceTranscriptionServiceProvider.overrideWithValue(const _Stt())],
      child: MaterialApp(
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, __) => visible ? AskodoxQuestionMic(onText: heard.add) : const SizedBox());
        })),
      ),
    ));
    await tester.pump();
    expect(container.read(askodoxQuestionMicTargetsProvider), 1, reason: 'the page registers its own mic');
    // The shell's centre mic bumps the trigger: start, then stop.
    container.read(askodoxQuestionMicTriggerProvider.notifier).state++;
    await tester.pump();
    expect(calls, contains('startVoiceRecording'));
    container.read(askodoxQuestionMicTriggerProvider.notifier).state++;
    await tester.pump();
    await tester.pump();
    expect(calls, contains('stopVoiceRecording'));
    expect(heard, ['does it inflate bike tyres']);
    show.value = false;
    await tester.pump();
    expect(container.read(askodoxQuestionMicTargetsProvider), 0, reason: 'leaving the page gives the mic back to chat');
  });
}
