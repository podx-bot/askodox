import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  AppSettings build() => const AppSettings();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setLocale(Locale locale) => state = AppSettings(
        themeMode: state.themeMode,
        locale: locale,
      );

  void useSystemLocale() => state = AppSettings(
        themeMode: state.themeMode,
        locale: null,
      );
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
