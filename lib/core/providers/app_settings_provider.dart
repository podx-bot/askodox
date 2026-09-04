import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/localization/askodox_language_catalog.dart';

enum VoicePreference { automatic, male, female }

extension VoicePreferenceStorage on VoicePreference {
  String get storageValue => name;

  static VoicePreference fromStorage(String? value) =>
      VoicePreference.values.where((item) => item.name == value).firstOrNull ??
      VoicePreference.automatic;
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.voicePreference = VoicePreference.automatic,
  });

  final ThemeMode themeMode;
  final Locale? locale;
  final VoicePreference voicePreference;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    VoicePreference? voicePreference,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        voicePreference: voicePreference ?? this.voicePreference,
      );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _localeKey = 'askodox.locale';
  static const _voicePreferenceKey = 'askodox.voice.preference';
  bool _localeChangedInSession = false;
  bool _voiceChangedInSession = false;

  @override
  AppSettings build() {
    Future.microtask(_restorePersistedSettings);
    return const AppSettings();
  }

  Future<void> _restorePersistedSettings() async {
    final preferences = await SharedPreferences.getInstance();

    var nextLocale = state.locale;
    var nextVoicePreference = state.voicePreference;

    if (!_localeChangedInSession) {
      final languageCode = preferences.getString(_localeKey);
      if (AskodoxLanguageCatalog.supports(languageCode)) {
        nextLocale = Locale(AskodoxLanguageCatalog.normalize(languageCode));
      }
    }

    if (!_voiceChangedInSession) {
      nextVoicePreference = VoicePreferenceStorage.fromStorage(
        preferences.getString(_voicePreferenceKey),
      );
    }

    state = AppSettings(
      themeMode: state.themeMode,
      locale: nextLocale,
      voicePreference: nextVoicePreference,
    );
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setLocale(Locale locale) {
    final normalizedCode = AskodoxLanguageCatalog.normalize(locale.languageCode);
    final normalizedLocale = Locale(normalizedCode);
    _localeChangedInSession = true;
    state = AppSettings(
      themeMode: state.themeMode,
      locale: normalizedLocale,
      voicePreference: state.voicePreference,
    );
    unawaited(_persistLocale(normalizedCode));
  }

  Future<void> _persistLocale(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_localeKey, languageCode);
  }

  void useSystemLocale() {
    _localeChangedInSession = true;
    state = AppSettings(
      themeMode: state.themeMode,
      locale: null,
      voicePreference: state.voicePreference,
    );
    unawaited(_clearPersistedLocale());
  }

  Future<void> _clearPersistedLocale() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_localeKey);
  }

  void setVoicePreference(VoicePreference preference) {
    _voiceChangedInSession = true;
    state = state.copyWith(voicePreference: preference);
    unawaited(_persistVoicePreference(preference));
  }

  Future<void> _persistVoicePreference(VoicePreference preference) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_voicePreferenceKey, preference.storageValue);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
