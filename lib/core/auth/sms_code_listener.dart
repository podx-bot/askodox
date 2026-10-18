import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One answer from the OTP SMS listener: `listening`, `prompt`, `code` (with
/// [code]), `denied`, `no_code`, `timeout` or `error`.
class AskodoxSmsEvent {
  const AskodoxSmsEvent(this.event, [this.code]);
  final String event;
  final String? code;
}

/// Where a received OTP comes from (tests use a fake).
abstract class AskodoxSmsCodeSource {
  /// Starts listening for ONE OTP SMS (Android asks the person before the app
  /// sees it). False when not available (not Android / no Play services).
  Future<bool> start();
  Future<void> stop();
  Stream<AskodoxSmsEvent> get events;

  /// Why the app closed last time (native crash type + top frames; no user
  /// data), read once. Null when there was none.
  Future<String?> takeLastCrash();
}

/// Android SMS User Consent (native side: AskodoxSmsConsent.kt). No SMS
/// permission is ever requested; only the 6-digit code reaches Dart.
class AndroidSmsUserConsent implements AskodoxSmsCodeSource {
  AndroidSmsUserConsent._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final args = (call.arguments as Map?) ?? const {};
      _events.add(AskodoxSmsEvent('${args['event'] ?? 'error'}', args['code'] as String?));
    });
  }

  static final instance = AndroidSmsUserConsent._();
  static const _channel = MethodChannel('com.askodox.app/sms');
  final _events = StreamController<AskodoxSmsEvent>.broadcast();

  @override
  Stream<AskodoxSmsEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> takeLastCrash() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeLastCrash');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }
}

final askodoxSmsCodeSourceProvider = Provider<AskodoxSmsCodeSource>((ref) => AndroidSmsUserConsent.instance);

/// A received code is used only when it is exactly 6 digits.
bool askodoxValidOtp(String? code) => code != null && RegExp(r'^\d{6}$').hasMatch(code);

/// A native crash record ("type=X root=Y thread=T at=A.b:1;C.d:2") as trail
/// fields the diagnostics endpoint accepts (short values, letter keys).
Map<String, String> askodoxCrashFields(String record) {
  final out = <String, String>{};
  const frameKeys = ['frame_a', 'frame_b', 'frame_c', 'frame_d', 'frame_e', 'frame_f', 'frame_g', 'frame_h'];
  for (final part in record.split(' ')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final key = part.substring(0, i);
    final value = part.substring(i + 1);
    if (key == 'at') {
      final frames = value.split(';');
      for (var f = 0; f < frames.length && f < frameKeys.length; f++) {
        out[frameKeys[f]] = frames[f].length > 110 ? frames[f].substring(0, 110) : frames[f];
      }
    } else if (const {'type', 'root', 'thread'}.contains(key)) {
      out[key] = value.length > 110 ? value.substring(0, 110) : value;
    }
  }
  return out;
}

/// A crash inside an SMS broadcast receiver (APK 1339: Firebase's own receiver,
/// `Pattern.matcher` on a missing message in `onReceive`).
bool askodoxCrashFromSmsReceiver(String record) =>
    record.contains('Pattern.matcher') || record.contains('onReceive') || record.contains('AskodoxSmsConsent');
