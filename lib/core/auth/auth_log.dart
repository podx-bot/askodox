import 'package:flutter/foundation.dart';

/// Where sign-in diagnostic lines go (logcat via debugPrint; tests replace it).
void Function(String line) askodoxAuthLogSink = (line) => debugPrint(line);

/// One diagnostic line for sign-in: `askodox.auth <event> key=value ...`.
///
/// Callers pass only non-sensitive fields (stage, path, HTTP status, Firebase
/// error code, a masked number "••••3210"). As a safety net every value is
/// redacted again: any run of 5 or more digits (a phone number, an OTP) is
/// replaced, so neither can reach the log even by mistake.
void askodoxAuthLog(String event, [Map<String, Object?> fields = const {}]) {
  final parts = [for (final e in fields.entries) '${e.key}=${askodoxRedactDigits('${e.value}')}'];
  askodoxAuthLogSink(['askodox.auth', event, ...parts].join(' '));
}

String askodoxRedactDigits(String value) =>
    value.replaceAll(RegExp(r'\+?\d[\d\s-]{3,}\d'), '[redacted]').replaceAll(RegExp(r'\d{5,}'), '[redacted]');
