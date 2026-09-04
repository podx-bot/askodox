import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/search/application/product_discovery_controller.dart';
import 'package:podx/features/search/domain/search_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.askodox.app/device');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('voice stays speaking until native acknowledgement completes', () async {
    SharedPreferences.setMockInitialValues({});
    final speechCompletion = Completer<bool>();
    final calls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'startVoiceSearch':
          return 'I need chicken nearby';
        case 'speakAcknowledgement':
          return speechCompletion.future;
        default:
          return null;
      }
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seenStates = <VoiceSearchState>[];
    final subscription = container.listen<DiscoveryState>(
      productDiscoveryControllerProvider,
      (_, next) => seenStates.add(next.voiceState),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final voiceFuture = container
        .read(productDiscoveryControllerProvider.notifier)
        .startVoice();

    for (var i = 0; i < 30; i++) {
      if (container.read(productDiscoveryControllerProvider).voiceState ==
          VoiceSearchState.speaking) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      container.read(productDiscoveryControllerProvider).voiceState,
      VoiceSearchState.speaking,
    );
    expect(calls, containsAllInOrder(['startVoiceSearch', 'speakAcknowledgement']));
    expect(
      seenStates,
      containsAllInOrder([
        VoiceSearchState.listening,
        VoiceSearchState.processing,
        VoiceSearchState.speaking,
      ]),
    );

    speechCompletion.complete(true);
    await voiceFuture;

    final completed = container.read(productDiscoveryControllerProvider);
    expect(completed.voiceState, VoiceSearchState.result);
    expect(completed.voiceResult, 'I need chicken nearby');
  });

  test('TTS failure does not discard a valid voice request', () async {
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startVoiceSearch') return 'I need a ride';
      if (call.method == 'speakAcknowledgement') {
        throw PlatformException(code: 'tts_unavailable');
      }
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(productDiscoveryControllerProvider.notifier)
        .startVoice();

    final completed = container.read(productDiscoveryControllerProvider);
    expect(completed.voiceState, VoiceSearchState.result);
    expect(completed.voiceResult, 'I need a ride');
  });
}
