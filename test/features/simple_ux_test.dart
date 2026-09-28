import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_3d.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/notifications/application/askodox_notifications.dart';
import 'package:podx/features/notifications/presentation/notification_settings_screen.dart';
import 'package:podx/features/notifications/presentation/updates_screen.dart';
import 'package:podx/features/orders/data/order_repository.dart';
import 'package:podx/features/privacy/presentation/privacy_center_screen.dart';
import 'package:podx/shared/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple, real UX: one place per function, no mock/placeholder screens,
/// silent real notifications, privacy actions that do something.
class _Auth extends AuthController {
  _Auth(super.manager, {bool signedIn = true}) {
    if (signedIn) {
      state = AuthSession(
        user: const AuthUser(id: 'phone-919876500001', role: UserRole.buyer, displayName: 'Test'),
        status: AuthStatus.loggedIn,
        tokenPlaceholder: 'test-token',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
    }
  }
}

class _Orders implements OrderRepository {
  List<Order> mine = [];

  @override
  Future<List<Order>> myOrders({int limit = 50}) async => mine;

  @override
  Future<List<Order>> incomingOrders({int limit = 50}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Growth implements GrowthRepository {
  @override
  Future<List<AskodoxLead>> leads() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Device extends AskodoxDeviceNotifications {
  _Device({this.systemOn = true});
  bool? systemOn;
  final shown = <String>[];
  bool openedSettings = false;

  @override
  Future<bool?> enabledInSystem() async => systemOn;
  @override
  Future<bool?> requestPermission() async => false;
  @override
  Future<void> openSystemSettings() async => openedSettings = true;
  @override
  Future<bool> show({required int id, required String title, required String body, String? route}) async {
    shown.add('$title|$body|$route');
    return true;
  }

  @override
  Future<String?> consumeLaunchRoute() async => null;
}

Order _order(String id, String status) => Order(
      id: id,
      buyerUserId: 'app-phone-919876500001',
      sellerUserId: 'app-seller',
      productId: '42',
      productTitle: 'Chicken 5 kg',
      status: status,
    );

List<Override> _overrides({bool signedIn = true, _Orders? orders, _Device? device}) => [
      authSessionProvider.overrideWith((ref) => _Auth(ref.watch(sessionManagerProvider), signedIn: signedIn)),
      orderRepositoryProvider.overrideWithValue(orders ?? _Orders()),
      growthRepositoryProvider.overrideWithValue(_Growth()),
      askodoxDeviceNotificationsProvider.overrideWithValue(device ?? _Device()),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AI friend: every mood draws in every look (no assets/3D needed), look persists', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final render3d in [true, false]) {
      for (final look in AskodoxCompanionLook.values) {
        // The robot is the Lite companion; its looks stay selectable.
        await container
            .read(askodoxCompanionSettingsProvider.notifier)
            .update(look: look, render3d: render3d, companion: AskodoxCompanionSettings.robotLite);
        for (final mood in AskodoxCompanionMood.values) {
          await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: Center(child: AskodoxCompanion(mood: mood))),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: '$look / $mood / 3d=$render3d');
          expect(find.byKey(ValueKey(render3d ? 'askodoxCompanion3d' : 'askodoxCompanion2d')), findsOneWidget);
        }
      }
    }
    // Reduced motion on the phone -> the flat 2D friend, even with 3D on.
    await container.read(askodoxCompanionSettingsProvider.notifier).update(render3d: true);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Center(child: AskodoxCompanion(mood: AskodoxCompanionMood.thinking))),
      ),
    ));
    expect(find.byKey(const ValueKey('askodoxCompanion2d')), findsOneWidget);
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    await tester.pump(const Duration(milliseconds: 50));
    restarted.read(askodoxCompanionSettingsProvider);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(restarted.read(askodoxCompanionSettingsProvider).look, AskodoxCompanionLook.simpleOrb);
    expect(askodoxCompanionLine(AskodoxCompanionMood.success, telugu: false, results: 1), 'Found 1 option');
    expect(askodoxCompanionLine(AskodoxCompanionMood.idle, telugu: false), 'Ready');
  });

  test('3D friend: a real lit mesh per look; meshes load from data (future avatars)', () {
    for (final look in AskodoxCompanionLook.values) {
      final mesh = AskodoxMesh.forLook(look, const Color(0xFF7A4DFF));
      expect(mesh.triangleCount, greaterThan(300), reason: '$look is a 3D mesh, not a flat icon');
      expect(mesh.parts.map((p) => p.name), contains('head'));
    }
    final loaded = AskodoxMesh.fromJson({
      'parts': [
        {'name': 'head', 'color': '#1769FF', 'vertices': [[0, 0, 0], [1, 0, 0], [0, 1, 0]], 'triangles': [0, 1, 2]},
      ],
    });
    expect(loaded.triangleCount, 1);
    expect(loaded.parts.single.color, const Color(0xFF1769FF));
  });

  test('notifications: ON and silent by default, choices persist across restarts', () async {
    final first = ProviderContainer();
    await first.read(askodoxNotificationSettingsProvider.notifier).ready;
    expect(first.read(askodoxNotificationSettingsProvider).enabled, isTrue);
    await first.read(askodoxNotificationSettingsProvider.notifier).setKind(AskodoxUpdateKind.leads, false);
    await first.read(askodoxNotificationSettingsProvider.notifier).setEnabled(false);
    first.dispose();

    final restarted = ProviderContainer();
    await restarted.read(askodoxNotificationSettingsProvider.notifier).ready;
    final settings = restarted.read(askodoxNotificationSettingsProvider);
    expect(settings.enabled, isFalse);
    expect(settings.muted, {AskodoxUpdateKind.leads});
    restarted.dispose();
  });

  test('a real request status change becomes ONE silent notification that opens the request', () async {
    final orders = _Orders()..mine = [_order('7', 'PLACED')];
    final device = _Device();
    final container = ProviderContainer(overrides: _overrides(orders: orders, device: device));
    await container.read(askodoxNotificationSettingsProvider.notifier).ready;
    final notifier = container.read(askodoxUpdateNotifierProvider);

    expect(await notifier.check(), 0, reason: 'first run only records the current state');
    orders.mine = [_order('7', 'ACCEPTED')];
    expect(await notifier.check(), 1);
    expect(device.shown.single, 'Chicken 5 kg|Accepted|/orders/mine');
    expect(await notifier.check(), 0, reason: 'never repeated');

    orders.mine = [_order('7', 'FULFILLED')];
    await container.read(askodoxNotificationSettingsProvider.notifier).setEnabled(false);
    expect(await notifier.check(), 0, reason: 'switched off means nothing is shown');
    container.dispose();
  });

  testWidgets('Updates: guests are offered sign-in; signed-in users see real request status', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(signedIn: false),
      child: const MaterialApp(home: Scaffold(body: UpdatesScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxUpdatesSignIn')), findsOneWidget);

    final orders = _Orders()..mine = [_order('9', 'PLACED')];
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: _overrides(orders: orders),
      child: const MaterialApp(home: Scaffold(body: UpdatesScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Chicken 5 kg'), findsOneWidget);
    expect(find.text('Waiting for the seller to accept'), findsOneWidget);
    expect(find.textContaining('Demo'), findsNothing);
  });

  testWidgets('Android notifications off: a simple "Notifications are off" + Enable opens settings', (tester) async {
    final device = _Device(systemOn: false);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(device: device),
      child: const MaterialApp(home: NotificationSettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxEnableNotifications')));
    await tester.pumpAndSettle();
    expect(device.openedSettings, isTrue);
    // One switch; per-kind choices are hidden until asked for.
    expect(find.byKey(const Key('askodoxNotificationsSwitch')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxNotify-leads')), findsNothing);
  });

  testWidgets('Privacy: plain promises, no mock text, delete needs typed confirmation', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: const MaterialApp(home: PrivacyCenterScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Exact location stays private'), findsOneWidget);
    for (final word in ['mock', 'Mock', 'Placeholder', 'placeholder', 'Production']) {
      expect(find.textContaining(word), findsNothing, reason: '"$word" must never reach users');
    }
    await tester.tap(find.byKey(const Key('askodoxDeleteAccount')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('askodoxConfirmDelete'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('askodoxDeleteConfirmField')), 'delete');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('bottom bar: 5 distinct purposes; the centre button starts voice (not a 2nd Home)', (tester) async {
    final container = ProviderContainer(overrides: _overrides(signedIn: false));
    addTearDown(container.dispose);
    Widget page(String name) => Center(child: Text(name));
    final router = GoRouter(routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final (path, name) in [('/', 'HOME'), ('/search', 'X'), ('/watchlist', 'HISTORY'), ('/updates', 'UPDATES'), ('/profile', 'PROFILE')])
            StatefulShellBranch(routes: [GoRoute(path: path, builder: (context, state) => page(name))]),
        ],
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    for (final key in ['askodoxNavHome', 'askodoxNavHistory', 'askodoxNavSpeak', 'askodoxNavUpdates', 'askodoxNavProfile']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('askodoxNavUpdates')));
    await tester.pumpAndSettle();
    expect(find.text('UPDATES'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxNavSpeak')));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(container.read(askodoxChatRequestProvider)?.voice, isTrue);
  });
}
