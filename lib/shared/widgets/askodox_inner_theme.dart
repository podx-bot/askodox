import 'package:flutter/material.dart';

/// The look of every inner page (redesign, owner 2026-11-13: "all inner pages in this model").
/// Soft grey page, white cards with a thin border and round corners, dark-navy text and primary
/// buttons, blue links. Home is NOT wrapped (owner: Home stays as it is).
const askodoxInnerBg = Color(0xFFF4F5F7);
const askodoxInnerInk = Color(0xFF10204A);
const askodoxInnerMuted = Color(0xFF5A6478);
const askodoxInnerLine = Color(0xFFE6E9EF);
const askodoxInnerBlue = Color(0xFF2450C8);
const askodoxInnerGreen = Color(0xFF17784C);

ThemeData askodoxInnerTheme(ThemeData base) {
  final radius14 = BorderRadius.circular(14);
  final scheme = base.colorScheme.copyWith(
    primary: askodoxInnerInk,
    onPrimary: Colors.white,
    secondary: askodoxInnerBlue,
    surface: Colors.white,
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
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: askodoxInnerInk),
      iconTheme: const IconThemeData(color: askodoxInnerInk),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
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
      titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: askodoxInnerInk),
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: askodoxInnerMuted),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFEEF0F4), thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: askodoxInnerInk,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: askodoxInnerInk,
        minimumSize: const Size(48, 46),
        side: const BorderSide(color: Color(0xFFDCE0E8)),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: askodoxInnerBlue, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: Color(0xFFDCE0E8))),
      enabledBorder: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: Color(0xFFDCE0E8))),
      focusedBorder: OutlineInputBorder(borderRadius: radius14, borderSide: const BorderSide(color: askodoxInnerBlue, width: 1.5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? askodoxInnerGreen : const Color(0xFFC9CED8)),
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: askodoxInnerMuted, letterSpacing: .4)),
      );
}
