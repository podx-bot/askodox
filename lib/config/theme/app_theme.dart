import 'package:flutter/material.dart';

import 'askodox_design_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _theme(Brightness.dark);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: AskodoxDesignTokens.violet500,
      brightness: Brightness.dark,
      surface: AskodoxDesignTokens.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colors,
      scaffoldBackgroundColor: AskodoxDesignTokens.ink,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: AskodoxDesignTokens.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AskodoxDesignTokens.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AskodoxDesignTokens.surfaceRaised,
        prefixIconColor: AskodoxDesignTokens.violet100,
        suffixIconColor: AskodoxDesignTokens.violet100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AskodoxDesignTokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AskodoxDesignTokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AskodoxDesignTokens.violet300, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AskodoxDesignTokens.surfaceRaised,
        labelStyle: const TextStyle(color: Colors.white),
        side: const BorderSide(color: AskodoxDesignTokens.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: AskodoxDesignTokens.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}
