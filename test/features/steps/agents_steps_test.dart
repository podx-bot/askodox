import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/agents_steps_screens.dart';

/// Owner 2026-11-24: AI agents in 3 pieces (made-up data only).
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

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('agents: team map with the waiting count and the inbox button', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/agent-team')) {
        return {
          'pending': 1,
          'recent': <Object?>[],
          'settings': {'is_owner': true, 'agents_off': <Object?>[], 'approvers': 'owner_manager', 'all_agents': <Object?>[]},
          'agents': [
            {'id': 'sales', 'enabled': true, 'name_en': 'Sales agent', 'name_te': 'Sales agent', 'about_en': 'Leads and follow-ups', 'about_te': 'Leads'}
          ]
        };
      }
      return {'id': 'b1', 'my_role': 'owner'};
    });
    await _pump(tester, api, const AskodoxAgentsStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxAgentsSteps')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAgentsStepsAgent-sales')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.byKey(const Key('askodoxAgentsStepsReview')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAgentsStepsRule')), findsOneWidget);
  });

  testWidgets('agent: asks once on open and shows the answer', (tester) async {
    final api = _Api((m, path, b) => {'answer': 'Call two people today.', 'answer_source': 'records', 'suggestions': <Object?>[]});
    await _pump(tester, api, const AskodoxAgentStepsScreen(businessId: 'b1', agent: 'sales'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxAgentSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAgentStepsAnswer')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAgentStepsAsk')), findsOneWidget);
  });
}
