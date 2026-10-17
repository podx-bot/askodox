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
