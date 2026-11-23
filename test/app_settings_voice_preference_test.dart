import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/providers/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ASKODOX persists the selected voice preference', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(appSettingsProvider.notifier)
        .setVoicePreference(VoicePreference.female);

    await Future<void>.delayed(Duration.zero);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('askodox.voice.preference'), 'female');
    expect(
      container.read(appSettingsProvider).voicePreference,
      VoicePreference.female,
    );
  });

  test('an old saved Male / Female choice is dropped: one app voice (owner 2026-11-23)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.voice.preference': 'male',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(appSettingsProvider).voicePreference,
      VoicePreference.automatic,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('askodox.voice.preference'), isFalse);
  });

  test('invalid persisted voice preference safely falls back to automatic', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.voice.preference': 'unsupported-value',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(appSettingsProvider).voicePreference,
      VoicePreference.automatic,
    );
  });
}
