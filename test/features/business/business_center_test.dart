import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/business/data/business_center_repository.dart';
import 'package:podx/features/business/presentation/business_center_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919800000000', role: UserRole.seller, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _Repo extends BusinessCenterRepository {
  _Repo() : super(_NoClient());

  @override
  Future<BusinessCenter> load({String language = 'en'}) async => const BusinessCenter(
        summary: {'listings': 2, 'requests_waiting': 1, 'in_progress': 0, 'completed': 3, 'opportunities_new': 0},
        insights: [
          BusinessInsight(
              kind: 'CONFIRMED_FACT',
              label: 'Confirmed fact',
              severity: 'red',
              title: '1 customer request(s) waiting for your answer',
              actionLabel: 'Open requests',
              actionRoute: '/orders/incoming'),
          BusinessInsight(
              kind: 'RECOMMENDATION',
              label: 'Recommendation',
              severity: 'orange',
              title: "Add size 9 to 'walking shoes'",
              actionLabel: 'Edit listing',
              actionRoute: '/listings/mine'),
        ],
        basis: 'Your own orders, listings and demand alerts on ASKODOX.',
      );
}

class _NoClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('seller sees counted facts, labels and an action that opens the right screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const BusinessCenterScreen()),
      GoRoute(path: '/orders/incoming', builder: (_, __) => const Scaffold(body: Text('incoming orders'))),
      GoRoute(path: '/listings/mine', builder: (_, __) => const Scaffold(body: Text('my listings'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        businessCenterRepositoryProvider.overrideWithValue(_Repo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Waiting requests'), findsOneWidget);
    expect(find.text('Confirmed fact'), findsOneWidget);
    expect(find.text('Recommendation'), findsOneWidget);
    expect(find.byKey(const Key('askodoxBusinessInsight-CONFIRMED_FACT-red')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBusinessAction-/orders/incoming')));
    await tester.pumpAndSettle();
    expect(find.text('incoming orders'), findsOneWidget);
    // Every summary tile opens the screen behind it (no dead tiles).
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBusinessStat-/listings/mine-Listings')));
    await tester.pumpAndSettle();
    expect(find.text('my listings'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBusinessStat-/orders/incoming-Completed')));
    await tester.pumpAndSettle();
    expect(find.text('incoming orders'), findsOneWidget);
  });

  test('insight json parses action and tolerates missing fields', () {
    final i = BusinessInsight.fromJson({
      'kind': 'POSSIBLE_CAUSE',
      'label': 'Possible cause',
      'severity': 'orange',
      'title': 'x',
      'action': {'label': 'Review listings', 'route': '/listings/mine'},
    })!;
    expect(i.actionRoute, '/listings/mine');
    expect(BusinessInsight.fromJson({'title': 'y'})!.actionRoute, isNull);
    expect(BusinessInsight.fromJson('bad'), isNull);
  });
}
