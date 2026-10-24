import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/meter_math.dart';

/// Light sensor (lux) and microphone level (dBFS) from the native
/// `com.askodox.app/hardware` channel (`AskodoxHardware.kt`). Readings are what
/// the phone reports; neither sensor is calibrated.
class AskodoxMeterException implements Exception {
  const AskodoxMeterException(this.code);

  /// no_sensor | permission_requested | no_reading | unsupported
  final String code;

  String message(bool te) => switch (code) {
        'no_sensor' => te ? 'ఈ ఫోన్‌లో ఈ సెన్సార్ లేదు.' : 'This phone does not have this sensor.',
        'permission_requested' => te ? 'అనుమతి అడిగాం — ఇచ్చిన తర్వాత మళ్ళీ నొక్కండి.' : 'Permission asked — allow it, then tap again.',
        'unsupported' => te ? 'ఈ యాప్ వెర్షన్‌లో ఇది లేదు — యాప్ అప్‌డేట్ చేయండి.' : 'This app version cannot do this — please update the app.',
        _ => te ? 'రీడింగ్ రాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'No reading came. Please try again.',
      };
}

class AskodoxPhoneMeters {
  const AskodoxPhoneMeters([this.channel = const MethodChannel('com.askodox.app/hardware')]);
  final MethodChannel channel;

  AskodoxMeterException _error(PlatformException e) =>
      AskodoxMeterException(const {'no_sensor', 'permission_requested'}.contains(e.code) ? e.code : 'no_reading');

  Future<double> lux() async {
    try {
      final v = await channel.invokeMethod<double>('lightLevel');
      if (v == null) throw const AskodoxMeterException('no_reading');
      return v;
    } on PlatformException catch (e) {
      throw _error(e);
    } on MissingPluginException {
      throw const AskodoxMeterException('unsupported');
    }
  }

  Future<AskodoxSoundReading> sound({int millis = 600}) async {
    try {
      final m = await channel.invokeMapMethod<String, Object?>('soundLevel', {'millis': millis});
      final dbfs = m?['dbfs'];
      if (dbfs is! num) throw const AskodoxMeterException('no_reading');
      final peak = m?['peak_dbfs'];
      return AskodoxSoundReading(dbfs: dbfs.toDouble(), peakDbfs: peak is num ? peak.toDouble() : dbfs.toDouble());
    } on PlatformException catch (e) {
      throw _error(e);
    } on MissingPluginException {
      throw const AskodoxMeterException('unsupported');
    }
  }
}

final askodoxPhoneMetersProvider = Provider<AskodoxPhoneMeters>((ref) => const AskodoxPhoneMeters());
