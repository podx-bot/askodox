import 'dart:async';

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_models.dart';
import '../core/providers/backend_providers.dart';
import '../features/notifications/application/askodox_notifications.dart';

/// Firebase Cloud Messaging client.
///
/// Firebase is initialised from build-time values (`--dart-define`, from the
/// Live Build's repository variables) -- they are public client identifiers,
/// not secrets, so no google-services.json is committed. Without them the app
/// says push is not configured and keeps its local notifications.
class AskodoxFirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static const bool configured = apiKey != '' && appId != '' && senderId != '' && projectId != '';

  /// Firebase for this build, initialised once (push, phone sign-in and
  /// in-app messaging share it). False when the build has no Firebase values.
  static Future<bool>? _initializing;

  static Future<bool> ensureInitialized() async {
    if (!configured) return false;
    // One initialisation even when push, sign-in and in-app messaging ask at
    // the same moment; a failure is retried on the next call.
    final pending = _initializing ??= _initialize();
    try {
      return await pending;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  static Future<bool> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
        ),
      );
    }
    return true;
  }
}

/// Data-only messages that arrive while ASKODOX is in the background or
/// closed. Notification messages are shown by Android itself (channel
/// "askodox_updates", AndroidManifest default); nothing else is done here, so
/// no message is ever shown twice.
@pragma('vm:entry-point')
Future<void> askodoxPushBackgroundHandler(RemoteMessage message) async {}

/// A message as ASKODOX uses it: what to show and which screen it opens.
class AskodoxPushMessage {
  const AskodoxPushMessage({this.title = '', this.body = '', this.route, this.id});
  final String title, body;
  final String? route;

  /// FCM message id (one message is shown once even if delivered twice).
  final String? id;
}

/// Everything Firebase-specific behind one seam (tests use a fake).
abstract class AskodoxPushBackend {
  Future<bool> init();
  Future<bool> requestPermission();
  Future<String?> token();
  Stream<String> get tokenRefresh;
  Stream<AskodoxPushMessage> get foregroundMessages;
  Stream<AskodoxPushMessage> get openedMessages;
  Future<AskodoxPushMessage?> initialMessage();
  Future<void> deleteToken();

  /// Firebase Installation ID (In-App Messaging "test on device"); null when
  /// not available.
  Future<String?> installationId();
}

class FirebasePushBackend implements AskodoxPushBackend {
  const FirebasePushBackend();

  static AskodoxPushMessage _of(RemoteMessage m) => AskodoxPushMessage(
        title: m.notification?.title ?? '',
        body: m.notification?.body ?? '',
        route: m.data['route'] is String ? m.data['route'] as String : null,
        id: m.messageId,
      );

  static bool _backgroundHandlerSet = false;

  @override
  Future<bool> init() async {
    if (!await AskodoxFirebaseConfig.ensureInitialized()) return false;
    if (!_backgroundHandlerSet && !kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(askodoxPushBackgroundHandler);
      _backgroundHandlerSet = true;
    }
    return true;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<AskodoxPushMessage> get foregroundMessages => FirebaseMessaging.onMessage.map(_of);

  @override
  Stream<AskodoxPushMessage> get openedMessages => FirebaseMessaging.onMessageOpenedApp.map(_of);

  @override
  Future<AskodoxPushMessage?> initialMessage() async {
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : _of(m);
  }

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Future<String?> installationId() async {
    if (!await AskodoxFirebaseConfig.ensureInitialized()) return null;
    return FirebaseInstallations.instance.getId();
  }
}

/// not_configured (no Firebase values in this build) / permission_denied /
/// registered / failed / signed_out.
enum AskodoxPushState { notConfigured, signedOut, permissionDenied, registered, failed }

class AskodoxPushRegistration {
  AskodoxPushRegistration({
    required this.backend,
    required this.client,
    required this.authToken,
    required this.showForeground,
    this.configured = AskodoxFirebaseConfig.configured,
  });

  final AskodoxPushBackend backend;
  final ApiClient client;
  final String? authToken;
  final bool configured;

  /// Shows a message that arrives while ASKODOX is open (Android does not).
  final Future<void> Function(AskodoxPushMessage message) showForeground;

  final _opened = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  final List<String> _seen = [];
  String? _lastToken;
  AskodoxPushState? _lastState;

  /// What the last [sync] found (diagnostics show it).
  AskodoxPushState? get lastState => _lastState;

  /// True the first time a message id is seen (a re-delivered message is
  /// never shown twice). Messages without an id are always shown.
  bool _firstTime(AskodoxPushMessage m) {
    final id = m.id;
    if (id == null || id.isEmpty) return true;
    if (_seen.contains(id)) return false;
    _seen.add(id);
    if (_seen.length > 50) _seen.removeAt(0);
    return true;
  }

  /// Routes from tapped notifications (the shell navigates).
  Stream<String> get openedRoutes => _opened.stream;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<bool> _register(String? token) async {
    if (token == null || token.length < 20) return false;
    final result = await client.post<Map<String, Object?>>('/api/me/push-token',
        body: {'token': token, 'platform': 'android'}, options: _auth);
    if (result is ApiSuccess) _lastToken = token;
    return result is ApiSuccess;
  }

  /// Idempotent: call on start / resume. The user's own notification
  /// switches still decide what the server sends.
  Future<AskodoxPushState> sync() async => _lastState = await _sync();

  Future<AskodoxPushState> _sync() async {
    if (!configured) return AskodoxPushState.notConfigured;
    if (authToken == null || authToken!.isEmpty) return AskodoxPushState.signedOut;
    try {
      if (!await backend.init()) return AskodoxPushState.notConfigured;
      // Android 13+: the system permission prompt appears here -- after
      // sign-in, when there is something to be notified about.
      if (!await backend.requestPermission()) return AskodoxPushState.permissionDenied;
      final ok = await _register(await backend.token());
      if (_subs.isEmpty) {
        _subs
          ..add(backend.tokenRefresh.listen((t) => _register(t)))
          ..add(backend.foregroundMessages.listen((m) {
            if (_firstTime(m)) showForeground(m);
          }))
          ..add(backend.openedMessages.listen((m) {
            if (_firstTime(m) && m.route != null && m.route!.startsWith('/')) _opened.add(m.route!);
          }));
        final first = await backend.initialMessage();
        if (first != null && _firstTime(first) && first.route != null && first.route!.startsWith('/')) {
          _opened.add(first.route!);
        }
      }
      return ok ? AskodoxPushState.registered : AskodoxPushState.failed;
    } catch (_) {
      return AskodoxPushState.failed;
    }
  }

  /// The current FCM token of this phone (diagnostics / sign-out), or null.
  Future<String?> currentToken() async {
    if (_lastToken != null) return _lastToken;
    if (!configured) return null;
    try {
      if (!await backend.init()) return null;
      return await backend.token();
    } catch (_) {
      return null;
    }
  }

  /// Sign-out of THIS phone: the server already unlinked this token
  /// (POST /api/me/logout); the token is deleted locally so the next account
  /// gets a fresh one. The account's other phones keep their pushes.
  Future<void> signOutDevice() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      if (configured && await backend.init()) await backend.deleteToken();
    } catch (_) {}
    _lastToken = null;
    _lastState = AskodoxPushState.signedOut;
  }

  /// Sign-out / account deletion: this phone stops receiving pushes.
  Future<void> unregister() async {
    try {
      await client.delete<Map<String, Object?>>('/api/me/push-token', options: _auth);
      if (configured) await backend.deleteToken();
    } catch (_) {}
    _lastToken = null;
  }

  String? get lastToken => _lastToken;

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _opened.close();
  }
}

final askodoxPushBackendProvider = Provider<AskodoxPushBackend>((ref) => const FirebasePushBackend());

final askodoxPushRegistrationProvider = Provider<AskodoxPushRegistration>((ref) {
  final session = ref.watch(authSessionProvider);
  final device = ref.watch(askodoxDeviceNotificationsProvider);
  final registration = AskodoxPushRegistration(
    backend: ref.watch(askodoxPushBackendProvider),
    client: ref.watch(apiClientProvider),
    authToken: session.user == null ? null : session.tokenPlaceholder,
    showForeground: (m) async {
      if (m.title.isEmpty && m.body.isEmpty) return;
      await device.show(id: m.hashCode & 0x7fffffff, title: m.title, body: m.body, route: m.route);
    },
  );
  ref.onDispose(registration.dispose);
  return registration;
});
