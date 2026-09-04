import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/providers/app_settings_provider.dart';
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

  test('selected ASKODOX locale and voice preference reach native TTS', () async {
    SharedPreferences.setMockInitialValues({});
    final arguments = <String, Object?>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      arguments[call.method] = call.arguments;
      if (call.method == 'startVoiceSearch') return 'నాకు చికెన్ కావాలి';
      if (call.method == 'speakAcknowledgement') return true;
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingsProvider.notifier)
      ..setLocale(const Locale('te'))
      ..setVoicePreference(VoicePreference.female);

    await container
        .read(productDiscoveryControllerProvider.notifier)
        .startVoice();

    expect(arguments['startVoiceSearch'], {'languageCode': 'te'});
    expect(
      arguments['speakAcknowledgement'],
      {'languageCode': 'te', 'voicePreference': 'female'},
    );
    expect(
      container.read(productDiscoveryControllerProvider).voiceResult,
      'నాకు చికెన్ కావాలి',
    );
  });

  test('catalog locale outside legacy four reaches native STT and TTS unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    final arguments = <String, Object?>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      arguments[call.method] = call.arguments;
      if (call.method == 'startVoiceSearch') return 'எனக்கு உதவி வேண்டும்';
      if (call.method == 'speakAcknowledgement') return true;
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingsProvider.notifier)
      ..setLocale(const Locale('ta'))
      ..setVoicePreference(VoicePreference.automatic);

    await container
        .read(productDiscoveryControllerProvider.notifier)
        .startVoice();

    expect(arguments['startVoiceSearch'], {'languageCode': 'ta'});
    expect(
      arguments['speakAcknowledgement'],
      {'languageCode': 'ta', 'voicePreference': 'automatic'},
    );
    expect(
      container.read(productDiscoveryControllerProvider).voiceResult,
      'எனக்கு உதவி வேண்டும்',
    );
  });

  test('voice preference persists and restores across provider recreation', () async {
    SharedPreferences.setMockInitialValues({});

    final first = ProviderContainer();
    first
        .read(appSettingsProvider.notifier)
        .setVoicePreference(VoicePreference.male);
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(appSettingsProvider);

    for (var i = 0; i < 20; i++) {
      if (second.read(appSettingsProvider).voicePreference ==
          VoicePreference.male) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      second.read(appSettingsProvider).voicePreference,
      VoicePreference.male,
    );
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
