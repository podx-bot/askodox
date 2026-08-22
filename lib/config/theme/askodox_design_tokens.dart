import 'package:flutter/material.dart';

/// ASKODOX visual language shared by app surfaces.
///
/// These values are intentionally brand-only. Product/domain logic should not
/// depend on them so the visual system can evolve independently.
abstract final class AskodoxDesignTokens {
  static const Color violet100 = Color(0xFFB48CFF);
  static const Color violet300 = Color(0xFF8A5CF6);
  static const Color violet500 = Color(0xFF603EFF);
  static const Color violet700 = Color(0xFF4823B9);
  static const Color violet900 = Color(0xFF2B176F);

  static const Color electricBlue = Color(0xFF2F7BFF);
  static const Color cyan = Color(0xFF39C8FF);
  static const Color success = Color(0xFF36D17B);
  static const Color warning = Color(0xFFFFB84D);
  static const Color error = Color(0xFFFF5D67);

  static const Color ink = Color(0xFF05060A);
  static const Color surface = Color(0xFF0D0F16);
  static const Color surfaceRaised = Color(0xFF151823);
  static const Color surfaceSoft = Color(0xFF1B1F2B);
  static const Color outline = Color(0xFF2A3040);
  static const Color white = Color(0xFFFFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [violet100, violet300, violet500, electricBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [violet500, electricBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxShadow glow(Color color, {double blur = 28}) => BoxShadow(
        color: color.withValues(alpha: 0.34),
        blurRadius: blur,
        spreadRadius: 2,
      );

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius fieldRadius = BorderRadius.all(Radius.circular(22));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(16));
}
