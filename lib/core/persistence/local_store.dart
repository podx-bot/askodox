import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocalStore {
  Future<void> write(String key, Object? value);
  Future<T?> read<T>(String key);
  Future<void> remove(String key);
  Future<void> clear();
}

class MemoryLocalStore implements LocalStore {
  final Map<String, Object?> _values = {};

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<T?> read<T>(String key) async => _values[key] as T?;

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }
}

class SharedPreferencesLocalStore implements LocalStore {
  static const _prefix = 'askodox.local.';

  String _key(String key) => '$_prefix$key';

  @override
  Future<void> write(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), jsonEncode(value));
  }

  @override
  Future<T?> read<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;
    return jsonDecode(raw) as T?;
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(key));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

abstract final class LocalKeys {
  static const session = 'session';
  static const buyerPreferences = 'buyerPreferences';
  static const searchRadius = 'searchRadius';
  static const savedLocations = 'savedLocations';
  static const watchlist = 'watchlist';
  static const alertPreferences = 'alertPreferences';
  static const recentSearches = 'recentSearches';
  static const sellerDrafts = 'sellerDrafts';
  static const language = 'language';
  static const theme = 'theme';
}
