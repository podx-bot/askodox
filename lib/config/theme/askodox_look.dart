import 'package:flutter/material.dart';

import 'askodox_fonts.dart';

/// The NEW LOOK (owner 2026-11-27, design canvas "కొత్త లుక్"): a calm dark page, raised cards with a thin line, ONE
/// orange accent, soft white text, Noto Sans Telugu as the main letters and fixed-width figures for money.
///
/// This file is the ONLY place the new look's colours live. A page never writes a colour of its own: it reads the
/// theme, or these tokens. Turn the look on for the whole app with `askodoxNewLookOn` (lib/core/ui/ui_switches.dart);
/// off = the app looks exactly as before.
abstract final class AskodoxLook {
  // Page: a soft light at the top fading into the page colour.
  static const bgTop = Color(0xFF2E3550);
  static const bg = Color(0xFF1F2432);

  // Cards.
  static const cardA = Color(0xFF323950);
  static const cardB = Color(0xFF2B3145);
  static const raised = Color(0xFF3A4157);
  static const line = Color(0xFF4A526B);

  // Text.
  static const text = Color(0xFFF7F9FC);
  static const muted = Color(0xFFC9CFDD);

  // The one accent (buttons, chips, the number that matters) and the "all good" colour.
  static const accent = Color(0xFFFFA14A);
  static const onAccent = Color(0xFF231300);
  static const accentText = Color(0xFFFFB866);
  static const good = Color(0xFF5BE3A0);

  /// Main letters: Telugu first, the other scripts come from [askodoxFontFallback].
  static const font = 'NotoSansTelugu';

  /// Money and counts line up in columns.
  static const figures = <FontFeature>[FontFeature.tabularFigures()];

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardA, cardB],
  );

  static const pageGradient = RadialGradient(
    center: Alignment(0, -1),
    radius: 1.1,
    colors: [bgTop, bg],
    stops: [0, .62],
  );

  /// WCAG contrast ratio of two colours (4.5 is the least for small text).
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + .05) / (lo + .05);
  }
}

/// The whole app's theme in the new look. Used by `AppTheme.light` and `askodoxInnerTheme` when `askodoxNewLookOn`.
ThemeData askodoxLookTheme() {
  const text = AskodoxLook.text;
  final scheme = ColorScheme.fromSeed(
    seedColor: AskodoxLook.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AskodoxLook.accent,
    onPrimary: AskodoxLook.onAccent,
    secondary: AskodoxLook.accentText,
    onSecondary: AskodoxLook.onAccent,
    surface: AskodoxLook.cardB,
    onSurface: text,
    surfaceTint: Colors.transparent,
    outline: AskodoxLook.line,
  );
  final radius14 = BorderRadius.circular(14);
  final fieldBorder = OutlineInputBorder(
    borderRadius: radius14,
    borderSide: const BorderSide(color: AskodoxLook.line),
  );
  const label = TextStyle(
    fontFamily: AskodoxLook.font,
    fontFamilyFallback: askodoxFontFallback,
    fontWeight: FontWeight.w700,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AskodoxLook.bg,
    canvasColor: AskodoxLook.bg,
    textTheme: ThemeData(brightness: Brightness.dark).textTheme.apply(
          fontFamily: AskodoxLook.font,
          fontFamilyFallback: askodoxFontFallback,
          bodyColor: text,
          displayColor: text,
        ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AskodoxLook.bg,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: AskodoxLook.font,
        fontFamilyFallback: askodoxFontFallback,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AskodoxLook.cardA,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AskodoxLook.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AskodoxLook.line, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: AskodoxLook.accentText,
      textColor: text,
      titleTextStyle: TextStyle(
        fontFamily: AskodoxLook.font,
        fontFamilyFallback: askodoxFontFallback,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: AskodoxLook.font,
        fontFamilyFallback: askodoxFontFallback,
        fontSize: 12.5,
        color: AskodoxLook.muted,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AskodoxLook.accent,
        foregroundColor: AskodoxLook.onAccent,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: AskodoxLook.line),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AskodoxLook.accentText, textStyle: label),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AskodoxLook.bg,
      labelStyle: const TextStyle(
        fontFamily: AskodoxLook.font,
        fontFamilyFallback: askodoxFontFallback,
        color: AskodoxLook.accentText,
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: AskodoxLook.accent),
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AskodoxLook.cardB,
      hintStyle: const TextStyle(fontFamilyFallback: askodoxFontFallback, color: AskodoxLook.muted),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius14,
        borderSide: const BorderSide(color: AskodoxLook.accent, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AskodoxLook.good : AskodoxLook.raised,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: AskodoxLook.cardB,
      indicatorColor: AskodoxLook.raised,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontFamily: AskodoxLook.font, fontFamilyFallback: askodoxFontFallback, color: text),
      ),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(color: text)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: text,
      collapsedIconColor: AskodoxLook.muted,
    ),
  );
}
