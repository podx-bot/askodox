import 'package:flutter/material.dart';

abstract final class AskodoxDesignTokens {
  static const Color violet100 = Color(0xFFB48CFF);
  static const Color violet300 = Color(0xFF8A5CF6);
  static const Color violet500 = Color(0xFF603EFF);
  static const Color electricBlue = Color(0xFF2F7BFF);
  static const Color cyan = Color(0xFF39C8FF);
  static const Color ink = Color(0xFF05060A);
  static const Color navy = Color(0xFF090B1D);
  static const Color surface = Color(0xFF11142A);
  static const Color surfaceRaised = Color(0xFF191D38);
  static const Color outline = Color(0xFF30375F);
  static const Color white = Color(0xFFFFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [violet100, violet300, violet500, electricBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF070816), Color(0xFF11102A), Color(0xFF160D34)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
