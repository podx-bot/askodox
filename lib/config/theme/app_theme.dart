import 'package:flutter/material.dart';

import '../../core/ui/ui_switches.dart';
import 'askodox_design_tokens.dart';
import 'askodox_look.dart';
import 'askodox_fonts.dart';

abstract final class AppTheme {
  static ThemeData get light => askodoxNewLookOn ? askodoxLookTheme() : _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: AskodoxDesignTokens.violet500,
      brightness: brightness,
      surface: isDark ? AskodoxDesignTokens.surface : AskodoxLook.sheet,
    );

    final foreground = isDark ? AskodoxLook.sheet : const Color(0xFFF7F9FC);
    final muted = isDark ? const Color(0xFF4A526B) : const Color(0xFFAEB9D0);
    final cardColor = isDark ? AskodoxDesignTokens.surfaceRaised : AskodoxLook.sheet;
    final outline = isDark ? AskodoxDesignTokens.outline : const Color(0xFF3E485A);
    final inputFill = isDark ? AskodoxDesignTokens.surfaceRaised : AskodoxLook.sheet;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: isDark ? AskodoxDesignTokens.ink : const Color(0xFF1F2432),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
            fontFamilyFallback: askodoxFontFallback,
          ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: isDark ? Colors.transparent : AskodoxLook.sheet,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(fontFamilyFallback: askodoxFontFallback, color: muted),
        prefixIconColor: isDark ? AskodoxDesignTokens.violet100 : const Color(0xFF8EB7FF),
        suffixIconColor: isDark ? AskodoxDesignTokens.violet100 : const Color(0xFF8EB7FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: isDark ? AskodoxDesignTokens.violet300 : const Color(0xFF8EB7FF),
            width: 1.7,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AskodoxDesignTokens.surfaceRaised : const Color(0xFF272E3C),
        labelStyle: TextStyle(fontFamilyFallback: askodoxFontFallback, color: foreground),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? AskodoxDesignTokens.surface : AskodoxLook.sheet,
        indicatorColor: isDark ? AskodoxDesignTokens.surfaceRaised : const Color(0xFF1B3424),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamilyFallback: askodoxFontFallback, color: foreground)),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: foreground)),
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
