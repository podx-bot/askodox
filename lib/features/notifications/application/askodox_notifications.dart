import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/backend_providers.dart';
import '../../growth/data/growth_repository.dart';
import '../../orders/data/order_repository.dart';

/// What the user may choose to receive (advanced; all ON by default).
enum AskodoxUpdateKind { requests, replies, leads }

/// Notifications: ON by default; routine ASKODOX updates are SILENT (no
/// sound/vibration). One switch for everyone, per-kind choices only under
/// "Choose what I receive". Persisted on the device.
class AskodoxNotificationSettings {
  const AskodoxNotificationSettings({this.enabled = true, this.muted = const {}});

  final bool enabled;
  final Set<AskodoxUpdateKind> muted;

  bool allows(AskodoxUpdateKind kind) => enabled && !muted.contains(kind);

  AskodoxNotificationSettings copyWith({bool? enabled, Set<AskodoxUpdateKind>? muted}) =>
      AskodoxNotificationSettings(enabled: enabled ?? this.enabled, muted: muted ?? this.muted);

  Map<String, Object?> toJson() => {'enabled': enabled, 'muted': [for (final k in muted) k.name]};

  static AskodoxNotificationSettings fromJson(Map<String, Object?> json) => AskodoxNotificationSettings(
        enabled: json['enabled'] != false,
        muted: {
          for (final name in (json['muted'] as List? ?? const []))
            for (final kind in AskodoxUpdateKind.values)
              if (kind.name == name) kind,
        },
      );
}

class AskodoxNotificationSettingsController extends StateNotifier<AskodoxNotificationSettings> {
  AskodoxNotificationSettingsController() : super(const AskodoxNotificationSettings()) {
    _ready = _load();
  }

  static const _key = 'askodox.notifications.v1';
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && mounted) {
        state = AskodoxNotificationSettings.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {
      // Unreadable settings fall back to the defaults (ON, silent).
    }
  }

  Future<void> setEnabled(bool enabled) => _save(state.copyWith(enabled: enabled));

  Future<void> setKind(AskodoxUpdateKind kind, bool on) =>
      _save(state.copyWith(muted: on ? ({...state.muted}..remove(kind)) : {...state.muted, kind}));

  Future<void> _save(AskodoxNotificationSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }
}

final askodoxNotificationSettingsProvider =
    StateNotifierProvider<AskodoxNotificationSettingsController, AskodoxNotificationSettings>(
  (ref) => AskodoxNotificationSettingsController(),
);

/// The Android side (MainActivity): OS permission, settings deep link, the
/// silent "ASKODOX updates" channel, and the route of a tapped notification.
class AskodoxDeviceNotifications {
  const AskodoxDeviceNotifications([this._channel = const MethodChannel('com.askodox.app/device')]);

  final MethodChannel _channel;

  Future<bool?> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args);
    } catch (_) {
      return null; // not Android / not available: callers treat as unknown
    }
  }

  /// null = unknown (not on a phone); false = the user turned them off in
  /// Android settings (ASKODOX cannot force them on).
  Future<bool?> enabledInSystem() => _call('notificationsEnabled');
  Future<bool?> requestPermission() => _call('requestNotificationPermission');
  Future<void> openSystemSettings() => _call('openNotificationSettings');
  Future<void> openAppSettings() => _call('openAppSettings');

  Future<bool> show({required int id, required String title, required String body, String? route}) async =>
      await _call('showNotification', {'id': id, 'title': title, 'body': body, 'route': route, 'important': false}) ??
      false;

  Future<String?> consumeLaunchRoute() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchRoute');
    } catch (_) {
      return null;
    }
  }
}

final askodoxDeviceNotificationsProvider = Provider<AskodoxDeviceNotifications>((ref) => const AskodoxDeviceNotifications());

/// One real update for the user (never demo data): a request they sent, a
/// request sent to them, or a customer lead for their service.
class AskodoxUpdate {
  const AskodoxUpdate({
    required this.key,
    required this.kind,
    required this.title,
    required this.status,
    required this.route,
    this.at,
  });

  final String key;
  final AskodoxUpdateKind kind;
  final String title;

  /// Plain words ("Waiting for the seller", "Accepted").
  final String status;
  final String route;
  final DateTime? at;
}

String askodoxOrderStatusWords(String raw, {required bool mine}) => switch (raw.toUpperCase()) {
      'PLACED' => mine ? 'Waiting for the seller to accept' : 'New request -- accept or decline',
      'ACCEPTED' => 'Accepted',
      'REJECTED' => 'Declined',
      'FULFILLED' => 'Completed',
      'CANCELLED' => 'Cancelled',
      'DISPUTED' => 'Problem reported',
      'CLOSED' => 'Closed',
      final other => other.replaceAll('_', ' ').toLowerCase(),
    };

/// Real updates from the user's own requests, incoming requests and leads.
/// Guests have none (identity is needed to have requests).
Future<List<AskodoxUpdate>> askodoxLoadUpdates(Ref ref) async {
  if (ref.read(authSessionProvider).user == null) return const [];
  final orders = ref.read(orderRepositoryProvider);
  final results = await Future.wait([
    orders.myOrders(limit: 30).catchError((_) => <Order>[]),
    orders.incomingOrders(limit: 30).catchError((_) => <Order>[]),
    ref.read(growthRepositoryProvider).leads().catchError((_) => <AskodoxLead>[]),
  ]);
  final mine = results[0] as List<Order>;
  final incoming = results[1] as List<Order>;
  final leads = results[2] as List<AskodoxLead>;
  final items = <AskodoxUpdate>[
    for (final order in mine)
      AskodoxUpdate(
        key: 'order:${order.id}',
        kind: AskodoxUpdateKind.requests,
        title: order.productTitle,
        status: askodoxOrderStatusWords(order.status, mine: true),
        route: '/orders/mine',
        at: order.updatedAt ?? order.createdAt,
      ),
    for (final order in incoming)
      AskodoxUpdate(
        key: 'incoming:${order.id}',
        kind: AskodoxUpdateKind.replies,
        title: order.productTitle,
        status: askodoxOrderStatusWords(order.status, mine: false),
        route: '/orders/incoming',
        at: order.updatedAt ?? order.createdAt,
      ),
    for (final lead in leads)
      AskodoxUpdate(
        key: 'lead:${lead.requestId}',
        kind: AskodoxUpdateKind.leads,
        title: lead.message,
        status: lead.responded ? 'You replied' : 'A customer needs this -- tap to reply',
        route: '/',
      ),
  ]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  return items;
}

final askodoxUpdatesProvider = FutureProvider.autoDispose<List<AskodoxUpdate>>((ref) {
  ref.watch(authSessionProvider);
  return askodoxLoadUpdates(ref);
});

/// While the app is open (and each time it comes back), new or changed
/// updates are shown as SILENT notifications -- once each, persisted, and
/// only as the user's settings and Android permission allow.
class AskodoxUpdateNotifier {
  AskodoxUpdateNotifier(this._ref);

  final Ref _ref;
  static const _seenKey = 'askodox.updates.seen.v1';

  Future<int> check() async {
    final settings = _ref.read(askodoxNotificationSettingsProvider);
    if (!settings.enabled) return 0;
    final updates = await askodoxLoadUpdates(_ref);
    final prefs = await SharedPreferences.getInstance();
    final firstRun = !prefs.containsKey(_seenKey);
    final seen = Map<String, String>.from(jsonDecode(prefs.getString(_seenKey) ?? '{}') as Map);
    var shown = 0;
    for (final update in updates) {
      final previous = seen[update.key];
      seen[update.key] = update.status;
      // First run only records the current state (no flood of old items).
      if (firstRun || previous == update.status || !settings.allows(update.kind)) continue;
      final ok = await _ref.read(askodoxDeviceNotificationsProvider).show(
            id: update.key.hashCode & 0x7fffffff,
            title: update.title,
            body: update.status,
            route: update.route,
          );
      if (ok) shown++;
    }
    await prefs.setString(_seenKey, jsonEncode(seen));
    return shown;
  }
}

final askodoxUpdateNotifierProvider = Provider<AskodoxUpdateNotifier>((ref) => AskodoxUpdateNotifier(ref));
