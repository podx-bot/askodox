import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/config/theme/askodox_look.dart';
import 'package:podx/core/ui/ui_switches.dart';
import 'package:podx/shared/widgets/askodox_inner_theme.dart';

void main() {
  tearDown(() => askodoxNewLookOn = false);

  test('new look is off by default', () {
    expect(askodoxNewLookOn, isFalse);
    expect(AppTheme.light.brightness, Brightness.light);
  });

  test('text and accent colours are readable on the page and the cards', () {
    for (final bg in [AskodoxLook.bg, AskodoxLook.bgTop, AskodoxLook.cardA, AskodoxLook.cardB]) {
      expect(AskodoxLook.contrast(AskodoxLook.text, bg), greaterThanOrEqualTo(4.5));
      expect(AskodoxLook.contrast(AskodoxLook.muted, bg), greaterThanOrEqualTo(4.5));
      expect(AskodoxLook.contrast(AskodoxLook.accentText, bg), greaterThanOrEqualTo(4.5));
      expect(AskodoxLook.contrast(AskodoxLook.good, bg), greaterThanOrEqualTo(4.5));
    }
    expect(AskodoxLook.contrast(AskodoxLook.onAccent, AskodoxLook.accent), greaterThanOrEqualTo(4.5));
  });

  test('one switch gives the whole app the new look, Telugu letters first', () {
    askodoxNewLookOn = true;
    for (final t in [AppTheme.light, askodoxInnerTheme(AppTheme.light)]) {
      expect(t.scaffoldBackgroundColor, AskodoxLook.bg);
      expect(t.colorScheme.primary, AskodoxLook.accent);
      expect(t.textTheme.bodyMedium?.fontFamily, AskodoxLook.font);
    }
  });
}
