import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/business/data/business_center_repository.dart';
import 'package:podx/features/business/presentation/business_center_screen.dart';
import 'package:podx/features/business/presentation/business_promotions_screen.dart';
import 'package:podx/features/profile/presentation/my_roles_screen.dart';
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
  _Repo() : super(_OffersApi());
  @override
  Future<BusinessCenter> load({String language = 'en'}) async =>
      const BusinessCenter(summary: {'listings': 1}, insights: [], basis: '');
}

class _OffersApi implements ApiClient {
  _OffersApi({this.open = true});
  final bool open;
  final posted = <Object?>[];
  final items = <Map<String, Object?>>[];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{'items': items} as T);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posted.add(body);
    if (!open) {
      return ApiError<T>(const ApiFailure(ApiFailureType.server, message: 'closed', statusCode: 409));
    }
    final data = Map<String, Object?>.from((body as Map)['data'] as Map);
    items.add({'id': 'mof_1', 'status': 'PENDING_REVIEW', 'data': data});
    return ApiSuccess(<String, Object?>{'id': 'mof_1'} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _app(GoRouter router, ApiClient api) => ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        apiClientProvider.overrideWithValue(api),
        businessCenterRepositoryProvider.overrideWithValue(_Repo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  testWidgets('Profile -> My Roles: one personal identity; each held role opens its real screens', (tester) async {
    SharedPreferences.setMockInitialValues({'askodox.roles.v1': '{"owned":["buyer","seller"],"active":"buyer"}'});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const MyRolesScreen()),
      GoRoute(path: '/business', builder: (_, __) => const Scaffold(body: Text('my business'))),
      GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('personal profile'))),
    ]);
    await tester.pumpWidget(_app(router, _OffersApi()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxRolesPersonal')), findsOneWidget, reason: 'identity once, not per role');
    expect(find.text('Service taker (services / jobs)'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxRoleTile-seller-business')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxRoleAdd-service_provider')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('askodoxRoleAdd-service_provider')), findsOneWidget,
        reason: 'a role not held offers to add it -- no fake sections');
    expect(find.byKey(const ValueKey('askodoxRoleTile-service_provider-business')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxRoleTile-seller-business')), -100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('askodoxRoleTile-seller-business')));
    await tester.pumpAndSettle();
    expect(find.text('my business'), findsOneWidget);
  });

  testWidgets('My Business lists its sections and each opens a real screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final opened = <String>[];
    Widget page(String name) => Scaffold(body: Text(name));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const BusinessCenterScreen()),
      for (final p in ['/profile', '/listings/mine', '/business/promotions', '/orders/incoming', '/opportunities'])
        GoRoute(path: p, builder: (_, __) {
          opened.add(p);
          return page(p);
        }),
    ]);
    await tester.pumpWidget(_app(router, _OffersApi()));
    await tester.pumpAndSettle();
    for (final id in ['profile', 'listings', 'promotions', 'orders', 'analytics']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('askodoxBusinessSection-$id')), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(ValueKey('askodoxBusinessSection-$id')), findsOneWidget, reason: id);
    }
    for (final section in askodoxBusinessSections(false)) {
      router.go('/');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(ValueKey('askodoxBusinessSection-${section.id}')), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(ValueKey('askodoxBusinessSection-${section.id}')));
      await tester.pumpAndSettle();
      expect(find.text(section.route), findsOneWidget, reason: '${section.id} opens ${section.route}');
    }
  });

  testWidgets('Promotions: a new offer is sent for ASKODOX review, never published directly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _OffersApi();
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const BusinessPromotionsScreen())]);
    await tester.pumpWidget(_app(router, api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxOffersEmpty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOfferCreate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxOfferTitle')), '10% off on tiles');
    await tester.enterText(find.byKey(const Key('askodoxOfferValue')), '10');
    await tester.tap(find.byKey(const Key('askodoxOfferSubmit')));
    await tester.pumpAndSettle();
    expect((api.posted.single as Map)['data'], {'title': '10% off on tiles', 'offer_kind': 'percent', 'value': 10});
    expect(find.text('Waiting for ASKODOX review'), findsOneWidget);
  });

  testWidgets('Promotions closed on the server: said honestly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const BusinessPromotionsScreen())]);
    await tester.pumpWidget(_app(router, _OffersApi(open: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxOfferCreate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxOfferTitle')), 'Diwali offer');
    await tester.tap(find.byKey(const Key('askodoxOfferSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Merchant offers are not open yet.'), findsOneWidget);
  });
}
