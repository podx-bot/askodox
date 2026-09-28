import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Names the customer's GPS point ("Vuyyuru, Andhra Pradesh"):
/// 1. the phone's own geocoder (Android, no API key);
/// 2. the backend's `GET /api/discover/place` (Geocoding, then the nearest
///    Places locality when Geocoding is not enabled on the key).
///
/// Returns null when neither could name it. The app then keeps saying
/// "Current location" and never claims a place it did not resolve.
class PlaceNameService {
  const PlaceNameService({http.Client? client, MethodChannel? device})
      : _client = client,
        _device = device;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;
  final MethodChannel? _device;

  Future<String?> resolve(double latitude, double longitude) async =>
      await _onDevice(latitude, longitude) ?? await _fromBackend(latitude, longitude);

  Future<String?> _onDevice(double latitude, double longitude) async {
    try {
      final place = await (_device ?? const MethodChannel('com.askodox.app/device'))
          .invokeMapMethod<String, Object?>('reverseGeocode', {'latitude': latitude, 'longitude': longitude});
      if (place == null) return null;
      String clean(Object? value) {
        final text = '${value ?? ''}'.trim();
        return text == 'null' ? '' : text;
      }

      final town = clean(place['locality']).isNotEmpty ? clean(place['locality']) : clean(place['subLocality']);
      if (town.isEmpty) return null;
      final state = clean(place['adminArea']);
      return [town, if (state.isNotEmpty && state != town) state].join(', ');
    } catch (_) {
      return null; // not Android / no geocoder: ask the backend
    }
  }

  Future<String?> _fromBackend(double latitude, double longitude) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/api/discover/place').replace(queryParameters: {
            'latitude': '$latitude',
            'longitude': '$longitude',
          }))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['resolved'] != true) return null;
      final label = decoded['label']?.toString().trim() ?? '';
      return label.isEmpty ? null : label;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
