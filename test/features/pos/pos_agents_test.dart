import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_agent_screens.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null);
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
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner sees only role agents and approves a sensitive proposal', (tester) async {
    var decided = false;
    final api = _Api((method, path, body) {
      if (path.endsWith('/agents')) {
        return {'agents': [
          {'id': 'finance', 'name_en': 'Finance agent', 'name_te': 'Finance agent', 'about_en': 'Dues', 'about_te': 'బాకీ'},
        ]};
      }
      if (path.contains('/agent-actions') && method == 'GET') {
        return {'actions': decided ? [] : [
          {'id': 'agt1', 'agent': 'finance', 'summary': 'Money received ₹500 by upi', 'mine': false, 'proposed_by': '…1a2b'},
        ]};
      }
      if (path.endsWith('/decision')) {
        decided = true;
        return {'id': 'agt1', 'status': 'DONE'};
      }
      return {'id': 'b1', 'my_role': 'owner', 'permissions': ['view']};
    });
    await _pump(tester, api, const AskodoxPosAgentsScreen(businessId: 'b1'));
    expect(find.text('Finance agent'), findsOneWidget);
    expect(find.text('Money received ₹500 by upi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxAgentApprove-agt1')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/pos/businesses/b1/agent-actions/agt1/decision'] as Map)['approve'], isTrue);
    expect(find.text('Money received ₹500 by upi'), findsNothing);
  });

  testWidgets('an agent answer says where it came from and shows the facts the AI used', (tester) async {
    final api = _Api((method, path, body) => {
          'agent': 'sales', 'answer': 'Call Ramu first.', 'answer_source': 'ai',
          'facts_text': ['Follow-ups due: 1 (1 overdue).'], 'suggestions': [],
        });
    await _pump(tester, api, const AskodoxPosAgentScreen(businessId: 'b1', agent: 'sales'));
    expect(find.text('Call Ramu first.'), findsOneWidget);
    expect(find.text('Follow-ups due: 1 (1 overdue).'), findsOneWidget);
    expect(find.text('AI re-worded your shop records.'), findsOneWidget);
    expect(askodoxAgentActionLabel('record_payment', false), contains('approval'));
  });
}
