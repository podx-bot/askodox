import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
}

/// A message as ASKODOX uses it: what to show and which screen it opens.
class AskodoxPushMessage {
  const AskodoxPushMessage({this.title = '', this.body = '', this.route});
  final String title, body;
  final String? route;
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
}

class FirebasePushBackend implements AskodoxPushBackend {
  const FirebasePushBackend();

  static AskodoxPushMessage _of(RemoteMessage m) => AskodoxPushMessage(
        title: m.notification?.title ?? '',
        body: m.notification?.body ?? '',
        route: m.data['route'] is String ? m.data['route'] as String : null,
      );

  @override
  Future<bool> init() async {
    if (!AskodoxFirebaseConfig.configured) return false;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AskodoxFirebaseConfig.apiKey,
          appId: AskodoxFirebaseConfig.appId,
          messagingSenderId: AskodoxFirebaseConfig.senderId,
          projectId: AskodoxFirebaseConfig.projectId,
        ),
      );
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
  String? _lastToken;

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
  Future<AskodoxPushState> sync() async {
    if (!configured) return AskodoxPushState.notConfigured;
    if (authToken == null || authToken!.isEmpty) return AskodoxPushState.signedOut;
    try {
      if (!await backend.init()) return AskodoxPushState.notConfigured;
      if (!await backend.requestPermission()) return AskodoxPushState.permissionDenied;
      final ok = await _register(await backend.token());
      if (_subs.isEmpty) {
        _subs
          ..add(backend.tokenRefresh.listen((t) => _register(t)))
          ..add(backend.foregroundMessages.listen((m) => showForeground(m)))
          ..add(backend.openedMessages.listen((m) {
            if (m.route != null && m.route!.startsWith('/')) _opened.add(m.route!);
          }));
        final first = await backend.initialMessage();
        if (first?.route != null && first!.route!.startsWith('/')) _opened.add(first.route!);
      }
      return ok ? AskodoxPushState.registered : AskodoxPushState.failed;
    } catch (_) {
      return AskodoxPushState.failed;
    }
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
