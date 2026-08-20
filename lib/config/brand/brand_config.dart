import 'package:flutter/material.dart';

/// Single source of truth for user-facing ASKODOX branding.
///
/// Keep product behavior and backend contracts brand-agnostic so the visual
/// identity can evolve without touching domain logic.
abstract final class BrandConfig {
  static const String displayName = 'ASKODOX';
  static const String assistantName = 'ASKODOX AI';
  static const String tagline = 'Ask Anything. Get It Done.';
  static const String localPromise =
      'Ask anything local. Buy, sell, work, services or rides.';
  static const String askHint = 'Ask ASKODOX';
  static const String voiceHint = 'Speak to ASKODOX';

  static const Color seedColor = Color(0xFF603EFF);
}
