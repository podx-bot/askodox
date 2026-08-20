import 'package:flutter/material.dart';

import 'askodox_design_tokens.dart';

abstract final class AppTheme {
  static const _seed = AskodoxDesignTokens.violet500;

  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final colors = base.copyWith(
      primary: dark
          ? AskodoxDesignTokens.violet100
          : AskodoxDesignTokens.violet700,
      secondary: AskodoxDesignTokens.electricBlue,
      tertiary: AskodoxDesignTokens.cyan,
      error: AskodoxDesignTokens.error,
      surface: dark ? AskodoxDesignTokens.surface : const Color(0xFFF7F5FC),
      surfaceContainerHighest:
          dark ? AskodoxDesignTokens.surfaceSoft : const Color(0xFFEDE9F7),
      outline: dark ? AskodoxDesignTokens.outline : const Color(0xFFD8D2E7),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor:
          dark ? AskodoxDesignTokens.ink : const Color(0xFFF8F7FC),
      cardColor: dark ? AskodoxDesignTokens.surfaceRaised : Colors.white,
      dividerColor: colors.outline.withValues(alpha: 0.65),
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? AskodoxDesignTokens.surfaceRaised : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: AskodoxDesignTokens.cardRadius,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? AskodoxDesignTokens.surfaceSoft
            : colors.surfaceContainerHighest,
        hintStyle: TextStyle(
          color: dark ? Colors.white54 : colors.onSurfaceVariant,
        ),
        border: const OutlineInputBorder(
          borderRadius: AskodoxDesignTokens.fieldRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AskodoxDesignTokens.fieldRadius,
          borderSide: BorderSide(
            color: colors.outline.withValues(alpha: 0.55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AskodoxDesignTokens.fieldRadius,
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor:
            dark ? AskodoxDesignTokens.surface : Colors.white,
        indicatorColor: colors.primary.withValues(alpha: dark ? 0.18 : 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? colors.primary : colors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark ? AskodoxDesignTokens.ink : Colors.transparent,
        foregroundColor: dark ? Colors.white : colors.onSurface,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.45)),
        selectedColor: colors.primary.withValues(alpha: dark ? 0.20 : 0.12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: AskodoxDesignTokens.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: AskodoxDesignTokens.buttonRadius,
          ),
          side: BorderSide(color: colors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}
