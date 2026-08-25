import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.locale});

  final ThemeMode themeMode;
  final Locale? locale;

  AppSettings copyWith({ThemeMode? themeMode, Locale? locale}) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _localeKey = 'askodox.locale';
  bool _localeChangedInSession = false;

  @override
  AppSettings build() {
    Future.microtask(_restoreLocale);
    return const AppSettings();
  }

  Future<void> _restoreLocale() async {
    final preferences = await SharedPreferences.getInstance();
    if (_localeChangedInSession) return;

    final languageCode = preferences.getString(_localeKey);
    if (languageCode == null || languageCode.trim().isEmpty) return;

    state = AppSettings(
      themeMode: state.themeMode,
      locale: Locale(languageCode),
    );
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setLocale(Locale locale) {
    _localeChangedInSession = true;
    state = AppSettings(
      themeMode: state.themeMode,
      locale: locale,
    );
    unawaited(_persistLocale(locale.languageCode));
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
    );
    unawaited(_clearPersistedLocale());
  }

  Future<void> _clearPersistedLocale() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_localeKey);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
