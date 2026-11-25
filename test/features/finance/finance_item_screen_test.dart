import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/finance/finance_item_screen.dart';

/// Owner 2026-11-25: finance item = answers from the company's document, call back only on a yes (made-up data).
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};
  final tokens = <String, String?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body, ApiRequestOptions options) async {
    calls['$method $path'] = body;
    tokens['$method $path'] = options.authToken;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null, options);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body, options);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body, options);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body, options);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('DELETE', path, null, options);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

class _Auth extends AuthController {
  _Auth(super.manager, {required bool signedIn}) {
    if (signedIn) {
      state = AuthSession(
        user: const AuthUser(id: 'phone-919000000321', role: UserRole.buyer, displayName: 'Test'),
        status: AuthStatus.loggedIn,
        tokenPlaceholder: 'test-token',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
    }
  }
}

Map<String, Object?> _item({bool canAsk = true}) => {
      'item_id': '7',
      'title': 'Suraksha Health Plan',
      'kind': 'insurance',
      'can_ask': canAsk,
      'points': canAsk ? ['Entry age 18 to 65 years', 'Sum insured 3 / 5 / 10 lakh'] : <Object>[],
      'questions': canAsk
          ? [
              {'id': 'fq_1', 'question': 'When are old diseases covered?', 'answer': 'After 36 months.', 'page': 2}
            ]
          : <Object>[],
    };

Future<void> _pump(WidgetTester tester, _Api api, {bool signedIn = true}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authSessionProvider.overrideWith((ref) => _Auth(ref.watch(sessionManagerProvider), signedIn: signedIn)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const AskodoxFinanceItemScreen(itemId: '7')),
        GoRoute(path: '/onboarding', builder: (_, __) => const Text('SIGN IN')),
      ]),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('only a finance catalog card opens the document answers', () {
    expect(askodoxFinanceItemIdOf('catalog-12', 'financial_offer'), '12');
    expect(askodoxFinanceItemIdOf('catalog-12', 'product'), isNull);
    expect(askodoxFinanceItemIdOf('catalog-12', null), isNull);
    expect(askodoxFinanceItemIdOf('listing-12', 'financial_offer'), isNull);
    expect(askodoxFinanceSourceLabel({'source': 'document', 'page': 2, 'document': 'brochure.pdf'}, false),
        '📄 brochure.pdf · page 2');
    expect(askodoxFinanceSourceLabel({'source': 'executive', 'page': 0}, false), contains('executive'));
  });

  testWidgets('a ready question is answered from the document with its page', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/ask')) {
        return {
          'found': true,
          'answer': 'Covered after 36 months.',
          'page': 2,
          'document': 'brochure.pdf',
          'source': 'document',
          'offer_callback': false,
          'not_advice': 'This is what the document says, not advice.',
        };
      }
      return _item();
    });
    await _pump(tester, api);
    expect(find.text('Entry age 18 to 65 years'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceReady-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/finance/items/7/ask'], {'question': 'When are old diseases covered?', 'language': 'en'});
    expect(find.text('Covered after 36 months.'), findsOneWidget);
    expect(find.text('📄 brochure.pdf · page 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxFinanceCallCard')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxFinanceAskMore')), findsOneWidget);
  });

  testWidgets('not in the document: the number goes only on "Yes, call me", and it can be cancelled', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/ask')) {
        return {'found': false, 'answer': 'This is not in the company\'s document.', 'page': 0, 'source': '', 'offer_callback': true};
      }
      if (path.endsWith('/callback')) return {'id': 'fc_1', 'status': 'new', 'again': false};
      if (m == 'DELETE') return {'ok': true};
      return _item();
    });
    await _pump(tester, api);
    await tester.enterText(find.byKey(const ValueKey('askodoxFinanceQuestion')), 'Is maternity covered?');
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceAsk')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('askodoxFinanceCallCard')), findsOneWidget);
    expect(api.calls.containsKey('POST /api/finance/items/7/callback'), isFalse);
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceWhen-evening')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceCallYes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/finance/items/7/callback'],
        {'question': 'Is maternity covered?', 'when': 'evening', 'consent': true});
    expect(api.tokens['POST /api/finance/items/7/callback'], 'test-token');
    expect(find.text('Our executive will call you this evening.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceCallCancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls.containsKey('DELETE /api/finance/callbacks/fc_1'), isTrue);
    expect(find.byKey(const ValueKey('askodoxFinanceQuestion')), findsOneWidget);
  });

  testWidgets('"No, thanks" sends nothing; a signed-out yes goes to sign-in, not to staff', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/ask')) return {'found': false, 'answer': 'Not in the document.', 'offer_callback': true};
      return _item();
    });
    await _pump(tester, api, signedIn: false);
    await tester.enterText(find.byKey(const ValueKey('askodoxFinanceQuestion')), 'Is maternity covered?');
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceAsk')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('askodoxFinanceCallYes')));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(api.calls.containsKey('POST /api/finance/items/7/callback'), isFalse);
  });

  testWidgets('an item whose document is not checked yet cannot be asked', (tester) async {
    final api = _Api((m, path, b) => _item(canAsk: false));
    await _pump(tester, api);
    expect(find.byKey(const ValueKey('askodoxFinanceQuestion')), findsNothing);
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('askodoxFinanceAsk')));
    expect(button.onPressed, isNull);
  });
}
