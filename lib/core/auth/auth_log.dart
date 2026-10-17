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
  askodoxAuthTrail.add(event, fields);
}

/// The ordered trail of ONE sign-in attempt ("+<ms> event key=value"), reset
/// on each Send OTP tap: callback order, app lifecycle (browser step), Firebase
/// codes and timings. Sent to the server as a diagnostic when an attempt ends
/// (`/onboarding/diagnostics/trace`). Number-like values are redacted and the
/// masked number field is left out entirely.
class AskodoxAuthTrail {
  static const maxLines = 80;
  static const _private = {'number', 'mobile', 'phone', 'otp', 'token', 'id_token', 'verification_id'};
  final _lines = <String>[];
  final _clock = Stopwatch();

  void reset() {
    _lines.clear();
    _clock
      ..reset()
      ..start();
  }

  void add(String event, [Map<String, Object?> fields = const {}]) {
    if (!_clock.isRunning) _clock.start();
    final parts = [
      for (final e in fields.entries)
        if (!_private.contains(e.key)) '${e.key}=${_value(e.value)}',
    ];
    if (_lines.length >= maxLines) _lines.removeAt(0);
    _lines.add(['+${_clock.elapsedMilliseconds}ms', event, ...parts].join(' '));
  }

  static String _value(Object? value) {
    final text = askodoxRedactDigits('$value').replaceAll(RegExp(r'[\s=]+'), '_');
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  List<String> get lines => List.unmodifiable(_lines);
}

final askodoxAuthTrail = AskodoxAuthTrail();

String askodoxRedactDigits(String value) =>
    value.replaceAll(RegExp(r'\+?\d[\d\s-]{3,}\d'), '[redacted]').replaceAll(RegExp(r'\d{5,}'), '[redacted]');
