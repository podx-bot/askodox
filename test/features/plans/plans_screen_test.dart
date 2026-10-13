import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/plans/data/plans_repository.dart';
import 'package:podx/features/plans/presentation/plans_screen.dart';

class _Api implements ApiClient {
  final posts = <Object?>[];

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
    return ApiSuccess(<String, Object?>{'subscription': null} as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add(body);
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
}
