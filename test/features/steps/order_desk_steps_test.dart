import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/config/environment.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/order_desk_steps_screen.dart';

/// Owner 2026-11-25: Menu & order in 3 steps (made-up data only).
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path.split('?').first, null);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => home),
        GoRoute(path: '/order-desk/track/:oid', builder: (_, s) => Text('TRACK ${s.pathParameters['oid']}')),
      ]),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Map<String, Object?> _shop({List<String> modes = const ['dine_in', 'takeaway']}) => {
      'open': true,
      'business': {'id': 'b1', 'name': 'Test Hotel', 'gst': false},
      'modes': modes,
      'menu': [
        {'id': 'idli', 'name': 'Idli', 'price_paise': 3000, 'unit': 'plate', 'available': true, 'menu_group': 'Tiffin'},
        {'id': 'dosa', 'name': 'Dosa', 'price_paise': 5000, 'unit': 'pcs', 'available': true, 'menu_group': 'Tiffin'},
        {'id': 'tea', 'name': 'Tea', 'price_paise': 1000, 'unit': 'cup', 'available': false, 'menu_group': 'Drinks'},
      ],
      'last_items': <Object>[],
    };

void main() {
  testWidgets('menu & order: tap items, choose the way, ONE Send order', (tester) async {
    final api = _Api((m, path, b) {
      if (m == 'POST' && path.endsWith('/order-desk/orders')) return {'id': 'o7'};
      if (path.endsWith('/resolve')) return _shop();
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxOrderDeskStepsScreen(code: 'ASKODOX-ORDER:b1'));
    expect(find.byKey(const Key('askodoxOrderDeskSteps')), findsOneWidget);
    expect(find.text('What would you like?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsItem-idli')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsItem-idli')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsItem-dosa')));
    await tester.pump();
    expect(find.text('×2'), findsOneWidget);
    expect(find.textContaining('3 items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsNext')));
    await tester.pump();
    expect(find.text('How do you want it?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsKind-takeaway')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsNext')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxOrderDeskStepsTotal')), findsOneWidget);
    expect(find.text('₹110.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsSend')));
    await tester.pumpAndSettle();
    final sent = api.calls['POST /api/pos/order-desk/orders'] as Map;
    expect(sent['kind'], 'takeaway');
    expect(sent['items'], [
      {'product_id': 'idli', 'qty': 2.0},
      {'product_id': 'dosa', 'qty': 1.0},
    ]);
    expect(find.text('TRACK o7'), findsOneWidget);
  });

  testWidgets('menu & order: one way only skips the second question; a cart from the chat opens the last step', (tester) async {
    final api = _Api((m, path, b) => path.endsWith('/resolve') ? _shop(modes: const ['takeaway']) : <String, Object?>{});
    await _pump(tester, api, const AskodoxOrderDeskStepsScreen(code: 'ASKODOX-ORDER:b1', kind: 'takeaway', cart: 'idli:2'));
    expect(find.byKey(const Key('askodoxOrderDeskStepsTotal')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrderDeskStepsSend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxStepBack')));
    await tester.pump();
    expect(find.text('What would you like?'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
  });

  testWidgets('menu & order: a closed shop shows its message and no button', (tester) async {
    final api = _Api((m, path, b) => {'open': false, 'message': 'Closed now. Opens at 7 AM.', 'business': {'name': 'Test Hotel'}});
    await _pump(tester, api, const AskodoxOrderDeskStepsScreen(code: 'ASKODOX-ORDER:b1'));
    expect(find.byKey(const Key('askodoxOrderDeskStepsClosed')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrderDeskStepsNext')), findsNothing);
  });

  testWidgets('menu & order (owner 2026-11-26): item photos lead the rows; "Try it" only where the shop kit offers it', (tester) async {
    Map<String, Object?> shop(String tryOn) => {
          ..._shop(),
          'try_on': tryOn,
          'menu': [
            {'id': 'shirt', 'name': 'Shirt', 'price_paise': 49900, 'unit': 'pcs', 'available': true, 'has_photo': true},
            {'id': 'belt', 'name': 'Belt', 'price_paise': 19900, 'unit': 'pcs', 'available': true, 'has_photo': false},
          ],
        };
    Future<void> pumpWith(String tryOn) async {
      final api = _Api((m, path, b) => path.endsWith('/resolve') ? shop(tryOn) : <String, Object?>{});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
          appConfigProvider.overrideWithValue(AppConfig(
              environment: AppEnvironment.development,
              backendProvider: BackendProvider.mock,
              apiBaseUrl: Uri.parse('https://api.example.test'),
              storageUrl: null,
              authSettings: const {'otpEnabled': 'false'},
              mapsProvider: 'mock',
              loggingLevel: LoggingLevel.none)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const AskodoxOrderDeskStepsScreen(code: 'ASKODOX-ORDER:b1')),
            GoRoute(
                path: '/try-on',
                builder: (_, s) => Text('TRYON ${s.uri.queryParameters['mode']} ${s.uri.queryParameters['name']} ${s.uri.queryParameters['image']}')),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await pumpWith('on_me');
    expect(find.byKey(const Key('askodoxStepRowPhoto')), findsOneWidget, reason: 'only the item that has a photo');
    expect(find.byKey(const Key('askodoxOrderDeskStepsTry-shirt')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrderDeskStepsTry-belt')), findsNothing, reason: 'no photo, nothing to try');
    await tester.tap(find.byKey(const Key('askodoxOrderDeskStepsTry-shirt')));
    await tester.pumpAndSettle();
    expect(find.text('TRYON on_me Shirt https://api.example.test/api/pos/shops/b1/photo/product/shirt'), findsOneWidget);
  });

  testWidgets('menu & order: a shop whose kit offers no try-on shows photos but no "Try it"', (tester) async {
    final api = _Api((m, path, b) => path.endsWith('/resolve')
        ? {
            ..._shop(),
            'try_on': '',
            'menu': [
              {'id': 'shirt', 'name': 'Shirt', 'price_paise': 49900, 'unit': 'pcs', 'available': true, 'has_photo': true}
            ],
          }
        : <String, Object?>{});
    await _pump(tester, api, const AskodoxOrderDeskStepsScreen(code: 'ASKODOX-ORDER:b1'));
    expect(find.byKey(const Key('askodoxOrderDeskStepsTry-shirt')), findsNothing);
  });
}
