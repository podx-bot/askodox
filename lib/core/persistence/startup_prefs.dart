import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// How the app opens SharedPreferences on the startup path (tests replace it).
Future<SharedPreferences> Function() askodoxPrefsLoader = SharedPreferences.getInstance;

/// Phone storage could not be opened (the plugin failed or never answered).
class AskodoxStorageUnavailable implements Exception {
  const AskodoxStorageUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'AskodoxStorageUnavailable($reason)';
}

/// SharedPreferences for startup screens: never waits forever and never
/// throws an unexpected type -- a failure becomes [AskodoxStorageUnavailable]
/// so the screen can show "try again" instead of an endless spinner
/// (APK 1335: the storage plugin failed and the app stayed on a white
/// screen). Nothing is deleted: the stored data stays on the phone.
Future<SharedPreferences> askodoxStartupPrefs({Duration timeout = const Duration(seconds: 8)}) async {
  try {
    return await askodoxPrefsLoader().timeout(timeout);
  } on TimeoutException {
    throw const AskodoxStorageUnavailable('timeout');
  } catch (error) {
    throw AskodoxStorageUnavailable(error.runtimeType.toString());
  }
}
