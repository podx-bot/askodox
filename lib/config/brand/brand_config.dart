import 'package:flutter/material.dart';

/// Single source of truth for user-facing branding.
///
/// Keep product behavior and backend contracts brand-agnostic so the visual
/// identity can evolve without touching domain logic.
abstract final class BrandConfig {
  static const String displayName = 'ASKODOX';
  static const String assistantName = 'ASKODOX AI';
  static const String askHint = 'Ask ASKODOX';
  static const String voiceHint = 'Speak to ASKODOX';

  static const Color seedColor = Color(0xFF7C8CFF);
}
