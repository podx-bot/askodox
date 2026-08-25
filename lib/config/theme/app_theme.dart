import 'package:flutter/material.dart';

import 'askodox_design_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: AskodoxDesignTokens.violet500,
      brightness: brightness,
      surface: isDark ? AskodoxDesignTokens.surface : Colors.white,
    );

    final foreground = isDark ? Colors.white : const Color(0xFF14213D);
    final muted = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF667085);
    final cardColor = isDark ? AskodoxDesignTokens.surfaceRaised : Colors.white;
    final outline = isDark ? AskodoxDesignTokens.outline : const Color(0xFFDCE4F2);
    final inputFill = isDark ? AskodoxDesignTokens.surfaceRaised : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: isDark ? AskodoxDesignTokens.ink : const Color(0xFFF7FAFF),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
          ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: isDark ? Colors.transparent : Colors.white,
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
        hintStyle: TextStyle(color: muted),
        prefixIconColor: isDark ? AskodoxDesignTokens.violet100 : const Color(0xFF1769FF),
        suffixIconColor: isDark ? AskodoxDesignTokens.violet100 : const Color(0xFF1769FF),
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
            color: isDark ? AskodoxDesignTokens.violet300 : const Color(0xFF1769FF),
            width: 1.7,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AskodoxDesignTokens.surfaceRaised : const Color(0xFFF2F6FF),
        labelStyle: TextStyle(color: foreground),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? AskodoxDesignTokens.surface : Colors.white,
        indicatorColor: isDark ? AskodoxDesignTokens.surfaceRaised : const Color(0xFFE9F7ED),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: foreground)),
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
