import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/plans/data/plans_repository.dart';
import 'package:podx/features/plans/presentation/plans_screen.dart';

class _Api implements ApiClient {
  _Api({this.payable = false});
  final bool payable;
  final posts = <Object?>[];
  String purchaseStatus = 'PENDING';

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    if (path == '/api/plans/catalogue') {
      return ApiSuccess(<String, Object?>{
        'items': [
          {'code': 'free', 'name': 'Free', 'price': 0, 'period_days': 30, 'trial_days': 0, 'available': true},
          {'code': 'plus', 'name': 'Plus', 'price': 499, 'period_days': 30, 'trial_days': 0, 'available': false},
          {'code': 'pro', 'name': 'Pro', 'price': 999, 'period_days': 30, 'trial_days': 7, 'available': false},
        ],
      } as T);
    }
    if (path == '/api/billing/options' && payable) {
      return ApiSuccess(<String, Object?>{
        'provider': 'razorpay',
        'mode': 'test',
        'items': [
          {'plan_code': 'plus', 'payable': true},
          {'plan_code': 'pro', 'payable': false, 'reason': 'TEST_MODE_TESTERS_ONLY'},
        ],
      } as T);
    }
    if (path == '/api/billing/purchases/bp_1') {
      return ApiSuccess(<String, Object?>{'purchase': {'id': 'bp_1', 'status': purchaseStatus}} as T);
    }
    return ApiSuccess(<String, Object?>{'subscription': null} as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add(body);
    if (path == '/api/billing/checkout') {
      return ApiSuccess(<String, Object?>{
        'purchase_id': 'bp_1',
        'pay_url': 'https://example.test/billing/pay/bp_1?t=1.x',
        'checkout': {'provider': 'razorpay'},
      } as T);
    }
    return ApiSuccess(<String, Object?>{'subscription': {'plan_code': 'free', 'status': 'ACTIVE'}} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

void main() {
  testWidgets('Free / Plus Rs 499 / Pro Rs 999 + 7-day trial: only available plans can be chosen', (tester) async {
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [plansRepositoryProvider.overrideWithValue(PlansRepository(api, authToken: 't'))],
      child: const MaterialApp(home: AskodoxPlansScreen()),
    ));
    await tester.pumpAndSettle();
    for (final code in ['free', 'plus', 'pro']) {
      expect(find.byKey(ValueKey('askodoxPlan-$code')), findsOneWidget);
    }
    expect(find.textContaining('₹499'), findsOneWidget);
    expect(find.textContaining('7-day trial'), findsOneWidget);
    expect(find.textContaining('Not available yet'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('askodoxPlanChoose-plus')), findsNothing, reason: 'not on sale -> no button');
    expect(find.byKey(const ValueKey('askodoxPlanChoose-pro')), findsNothing);
    expect(find.byKey(const Key('askodoxPlansBillingNote')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPlanChoose-free')));
    await tester.pumpAndSettle();
    expect(api.posts.single, {'plan_code': 'free'});
    expect(find.text('Plan updated.'), findsOneWidget);
  });

  testWidgets('TEST mode: Pay only where the server allows it; sends only the plan code; status comes from the server',
      (tester) async {
    final api = _Api(payable: true);
    final opened = <Uri>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        plansRepositoryProvider.overrideWithValue(PlansRepository(api, authToken: 't')),
        askodoxPayLauncherProvider.overrideWithValue((url) async {
          opened.add(url);
          return true;
        }),
      ],
      child: const MaterialApp(home: AskodoxPlansScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPlanPay-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPlanPay-pro')), findsNothing, reason: 'server said not payable');
    expect(find.byKey(const Key('askodoxPlansTestMode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPlanPay-plus')));
    await tester.pumpAndSettle();
    expect(api.posts.single, {'plan_code': 'plus'}, reason: 'never an amount from the app');
    expect(opened.single.path, '/billing/pay/bp_1');
    await tester.tap(find.byKey(const Key('askodoxPayCheck')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not confirmed yet'), findsOneWidget);
    api.purchaseStatus = 'ACTIVE';
    await tester.tap(find.byKey(const Key('askodoxPayCheck')));
    await tester.pumpAndSettle();
    expect(find.text('Paid. Your plan is active.'), findsOneWidget);
  });
}
