import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/app_router.dart';
import '../api/api_client.dart';
import '../api/api_models.dart';
import '../providers/backend_providers.dart';

/// Test Mode Diagnostics (owner request 2026-10-29; server:
/// backend/app/services/test_diagnostics.py).
///
/// Only a STAFF number can turn it on (Profile), it switches itself off after
/// a week, and while it is on the app sends small events -- screens opened,
/// chat turns (typed / voice), replies (live-checked or not, honesty guard),
/// how each reply was spoken (server audio or the phone's fallback voice),
/// what the guide spoke, and app errors -- so a test can be read back without
/// screenshots. Off = nothing is collected or sent. Text is masked again on
/// the server.
class AskodoxTestLog {
  AskodoxTestLog._();

  static final AskodoxTestLog instance = AskodoxTestLog._();

  bool enabled = false;
  Future<void> Function(List<Map<String, Object?>> events)? _sink;
  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;
  String currentScreen = '';

  void configure({required bool on, Future<void> Function(List<Map<String, Object?>> events)? sink}) {
    enabled = on && sink != null;
    _sink = sink;
    if (!enabled) {
      _queue.clear();
      _timer?.cancel();
      _timer = null;
    }
  }

  void add(String kind, {String? screen, Map<String, Object?> detail = const {}}) {
    if (!enabled) return;
    _queue.add({
      'kind': kind,
      'screen': screen ?? currentScreen,
      'at': DateTime.now().toIso8601String(),
      'detail': {for (final e in detail.entries) e.key: _short(e.value)},
    });
    if (_queue.length >= 20) {
      unawaited(flush());
    } else {
      _timer ??= Timer(const Duration(seconds: 10), () => unawaited(flush()));
    }
  }

  static Object? _short(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is List) return [for (final v in value.take(10)) _short(v)];
    final text = '$value';
    return text.length > 500 ? '${text.substring(0, 500)}…' : text;
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final sink = _sink;
    if (!enabled || sink == null || _queue.isEmpty) return;
    final batch = List<Map<String, Object?>>.of(_queue.take(50));
    _queue.removeRange(0, batch.length);
    try {
      await sink(batch);
    } catch (_) {
      // Diagnostics never disturb the app.
    }
  }

  @visibleForTesting
  List<Map<String, Object?>> get pending => List.unmodifiable(_queue);
}

/// Shortcut used at the hook points (no-op unless Test Mode is on).
void askodoxTestLog(String kind, {String? screen, Map<String, Object?> detail = const {}}) =>
    AskodoxTestLog.instance.add(kind, screen: screen, detail: detail);

@immutable
class AskodoxTestModeState {
  const AskodoxTestModeState({this.enabled = false, this.allowed = false, this.expiresAt});
  final bool enabled;

  /// This number is linked to an ASKODOX staff member (only they see the switch).
  final bool allowed;
  final String? expiresAt;
}

class AskodoxTestModeController extends StateNotifier<AskodoxTestModeState> {
  AskodoxTestModeController(this._client, this._token, this._router) : super(const AskodoxTestModeState()) {
    _load();
  }

  final ApiClient _client;
  final String? _token;
  final GoRouter? _router;
  final String _session = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  FlutterExceptionHandler? _previousOnError;

  bool get _signedIn => _token != null && _token!.isNotEmpty && _token != 'DEMO_ONLY';
  ApiRequestOptions get _auth => ApiRequestOptions(authToken: _token);

  Future<void> _load() async {
    if (!_signedIn) return;
    try {
      final result = await _client.get<Map<String, Object?>>('/api/me/test-mode', options: _auth);
      if (result is ApiSuccess<Map<String, Object?>>) _apply(result.data);
    } catch (_) {}
  }

  Future<bool> setEnabled(bool on) async {
    if (!_signedIn) return false;
    try {
      final result = await _client.put<Map<String, Object?>>('/api/me/test-mode', body: {'enabled': on}, options: _auth);
      if (result is ApiSuccess<Map<String, Object?>>) {
        _apply(result.data);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _apply(Map<String, Object?> data) {
    if (!mounted) return;
    state = AskodoxTestModeState(
      enabled: data['enabled'] == true,
      allowed: data['allowed'] == true,
      expiresAt: data['expires_at']?.toString(),
    );
    _wire(state.enabled);
  }

  void _wire(bool on) {
    AskodoxTestLog.instance.configure(on: on, sink: on ? _send : null);
    final info = _router?.routeInformationProvider;
    if (on) {
      info?.addListener(_onRoute);
      _onRoute();
      _previousOnError ??= FlutterError.onError;
      FlutterError.onError = (details) {
        askodoxTestLog('error', detail: {'error': details.exceptionAsString().split('\n').first});
        (_previousOnError ?? FlutterError.presentError)(details);
      };
    } else {
      info?.removeListener(_onRoute);
      if (_previousOnError != null) {
        FlutterError.onError = _previousOnError;
        _previousOnError = null;
      }
    }
  }

  void _onRoute() {
    final path = _router?.routeInformationProvider.value.uri.path ?? '';
    if (path.isEmpty || path == AskodoxTestLog.instance.currentScreen) return;
    AskodoxTestLog.instance.currentScreen = path;
    askodoxTestLog('screen', screen: path);
  }

  Future<void> _send(List<Map<String, Object?>> events) async {
    await _client.post<Map<String, Object?>>('/api/diagnostics/test-events',
        body: {'events': events, 'session': _session}, options: _auth);
  }

  @override
  void dispose() {
    unawaited(AskodoxTestLog.instance.flush());
    _wire(false);
    super.dispose();
  }
}

final askodoxTestModeProvider =
    StateNotifierProvider<AskodoxTestModeController, AskodoxTestModeState>((ref) {
  final session = ref.watch(authSessionProvider);
  GoRouter? router;
  try {
    router = ref.read(appRouterProvider);
  } catch (_) {}
  return AskodoxTestModeController(
      ref.watch(apiClientProvider), session.user == null ? null : session.tokenPlaceholder, router);
});

/// Keeps Test Mode loaded for the signed-in person (mounted once in the app).
class AskodoxTestModeHost extends ConsumerWidget {
  const AskodoxTestModeHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(askodoxTestModeProvider);
    return child;
  }
}
