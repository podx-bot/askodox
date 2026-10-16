import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_registration.dart' show AskodoxFirebaseConfig;

/// Firebase In-App Messaging: text / image banners and cards designed in the
/// Firebase Console, shown INSIDE ASKODOX.
///
/// * Opt-in only: off until the person switches "Offer messages in the app"
///   on (Notifications). While off, messages are suppressed AND Firebase
///   In-App Messaging collects nothing (auto data collection is off in the
///   AndroidManifest and only switched on with the opt-in).
/// * Frequency: the app raises its trigger event ("askodox_app_open") at most
///   once every [minHoursBetween] hours, on top of the campaign's own
///   frequency limit in the Firebase Console.
/// * Video ads / rich media are NOT done here: they stay in the ASKODOX
///   native content system (sponsored rows, offers, notices).
abstract class AskodoxInAppMessagingBackend {
  Future<bool> init();
  Future<void> setSuppressed(bool suppressed);
  Future<void> setDataCollection(bool enabled);
  Future<void> trigger(String event);
}

class FirebaseInAppMessagingBackend implements AskodoxInAppMessagingBackend {
  const FirebaseInAppMessagingBackend();

  @override
  Future<bool> init() => AskodoxFirebaseConfig.ensureInitialized();
  @override
  Future<void> setSuppressed(bool suppressed) => FirebaseInAppMessaging.instance.setMessagesSuppressed(suppressed);
  @override
  Future<void> setDataCollection(bool enabled) =>
      FirebaseInAppMessaging.instance.setAutomaticDataCollectionEnabled(enabled);
  @override
  Future<void> trigger(String event) => FirebaseInAppMessaging.instance.triggerEvent(event);
}

class AskodoxInAppMessaging {
  AskodoxInAppMessaging(this.backend, {this.configured = AskodoxFirebaseConfig.configured, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const optInKey = 'askodox.fiam.opt_in.v1';
  static const lastTriggerKey = 'askodox.fiam.last_trigger.v1';
  static const triggerEvent = 'askodox_app_open';
  static const minHoursBetween = 20;

  final AskodoxInAppMessagingBackend backend;
  final bool configured;
  final DateTime Function() _now;

  Future<bool> optedIn() async => (await SharedPreferences.getInstance()).getBool(optInKey) ?? false;

  /// The person's choice; applied to Firebase at once.
  Future<void> setOptIn(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(optInKey, on);
    await _apply(on);
  }

  Future<bool> _apply(bool on) async {
    if (!configured) return false;
    try {
      if (!await backend.init()) return false;
      await backend.setDataCollection(on);
      await backend.setSuppressed(!on);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// App opened (signed in): applies the choice, then raises the trigger
  /// event at most once per [minHoursBetween] hours. Returns true when the
  /// event was raised.
  Future<bool> onAppOpen() async {
    if (!configured) return false;
    final on = await optedIn();
    if (!await _apply(on) || !on) return false;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(lastTriggerKey);
    final now = _now();
    if (last != null && now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inHours < minHoursBetween) {
      return false;
    }
    try {
      await backend.trigger(triggerEvent);
    } catch (_) {
      return false;
    }
    await prefs.setInt(lastTriggerKey, now.millisecondsSinceEpoch);
    return true;
  }
}

final askodoxInAppMessagingBackendProvider =
    Provider<AskodoxInAppMessagingBackend>((ref) => const FirebaseInAppMessagingBackend());

final askodoxInAppMessagingProvider =
    Provider<AskodoxInAppMessaging>((ref) => AskodoxInAppMessaging(ref.watch(askodoxInAppMessagingBackendProvider)));
