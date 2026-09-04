import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/providers/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ASKODOX persists an Indian language from the central catalog', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider.notifier).setLocale(const Locale('ta'));
    await Future<void>.delayed(Duration.zero);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('askodox.locale'), 'ta');
    expect(container.read(appSettingsProvider).locale?.languageCode, 'ta');
  });

  test('ASKODOX restores a persisted scheduled Indian language', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.locale': 'bn',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appSettingsProvider).locale?.languageCode, 'bn');
  });

  test('unsupported explicit locale safely normalizes to English', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider.notifier).setLocale(const Locale('xx'));
    await Future<void>.delayed(Duration.zero);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('askodox.locale'), 'en');
    expect(container.read(appSettingsProvider).locale?.languageCode, 'en');
  });
}
