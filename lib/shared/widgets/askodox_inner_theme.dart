import 'package:flutter/material.dart';

import '../../config/theme/askodox_fonts.dart';
import '../../config/theme/askodox_look.dart';
import '../../core/ui/ui_switches.dart';

/// The look of every inner page (redesign, owner 2026-11-13: "all inner pages in this model").
/// Soft grey page, white cards with a thin border and round corners, dark-navy text and primary
/// buttons, blue links. Home is NOT wrapped (owner: Home stays as it is).
const askodoxInnerBg = Color(0xFF1F2432);
const askodoxInnerInk = Color(0xFFF7F9FC);
const askodoxInnerMuted = Color(0xFFB3BED5);
const askodoxInnerLine = Color(0xFF4A526B);
const askodoxInnerBlue = Color(0xFFA3C0FC);
const askodoxInnerGreen = Color(0xFF7CD3A2);

ThemeData askodoxInnerTheme(ThemeData base) {
  if (askodoxNewLookOn) return askodoxLookTheme();
  final radius14 = BorderRadius.circular(14);
  final scheme = base.colorScheme.copyWith(
    primary: askodoxInnerInk,
    onPrimary: AskodoxLook.sheet,
    secondary: askodoxInnerBlue,
    surface: AskodoxLook.sheet,
    onSurface: askodoxInnerInk,
    surfaceTint: Colors.transparent,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: askodoxInnerBg,
    canvasColor: askodoxInnerBg,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: askodoxInnerBg,
      foregroundColor: askodoxInnerInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(fontFamilyFallback: askodoxFontFallback, fontSize: 20, fontWeight: FontWeight.w800, color: askodoxInnerInk),
      iconTheme: const IconThemeData(color: askodoxInnerInk),
    ),
    cardTheme: CardThemeData(
      color: AskodoxLook.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: askodoxInnerLine),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: askodoxInnerBlue,
      textColor: askodoxInnerInk,
      titleTextStyle: TextStyle(fontFamilyFallback: askodoxFontFallback, fontSize: 15, fontWeight: FontWeight.w700, color: askodoxInnerInk),
      subtitleTextStyle: TextStyle(fontFamilyFallback: askodoxFontFallback, fontSize: 12.5, color: askodoxInnerMuted),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF1F2432), thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: askodoxInnerInk,
        foregroundColor: AskodoxLook.sheet,
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontFamilyFallback: askodoxFontFallback, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: askodoxInnerInk,
        minimumSize: const Size(48, 46),
        side: const BorderSide(color: Color(0xFF4A526B)),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontFamilyFallback: askodoxFontFallback, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: askodoxInnerBlue, textStyle: const TextStyle(fontFamilyFallback: askodoxFontFallback, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: AskodoxLook.sheet,
      border: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: Color(0xFF4A526B))),
      enabledBorder: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: Color(0xFF4A526B))),
      focusedBorder: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: askodoxInnerBlue, width: 1.5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => AskodoxLook.sheet),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? askodoxInnerGreen : const Color(0xFF9498A2)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: askodoxInnerInk,
      collapsedIconColor: askodoxInnerMuted,
    ),
  );
}

/// Wrap an inner page (its Scaffold) to give it the inner-page look.
class AskodoxInnerTheme extends StatelessWidget {
  const AskodoxInnerTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: askodoxInnerTheme(Theme.of(context)), child: child);
}

/// A small grey heading above a group of cards ("ఎవరెవరి ఫోన్‌లో మాట్లాడాలి").
class AskodoxSectionLabel extends StatelessWidget {
  const AskodoxSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text,
            style: const TextStyle(fontFamilyFallback: askodoxFontFallback, fontSize: 12, fontWeight: FontWeight.w700, color: askodoxInnerMuted, letterSpacing: .4)),
      );
}
