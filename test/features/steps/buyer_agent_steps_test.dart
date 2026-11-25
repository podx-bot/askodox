import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/buyer_agent_steps_screen.dart';

/// Owner 2026-11-25: My helper in 3 pieces (made-up data only).
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
  testWidgets('my helper: answers on open, asks again with the typed question', (tester) async {
    final asked = <String>[];
    final api = _Api((m, path, b) {
      final q = '${(b as Map?)?['question'] ?? ''}';
      asked.add(q);
      return {'answer': q.isEmpty ? 'You owe Test Shop ₹120.' : 'Answer for: $q'};
    });
    await _pump(tester, api, const AskodoxBuyerAgentStepsScreen());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBuyerAgentSteps')), findsOneWidget);
    expect(find.text('You owe Test Shop ₹120.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxBuyerAgentStepsQuestion')), 'advances');
    await tester.tap(find.byKey(const Key('askodoxBuyerAgentStepsAsk')));
    await tester.pumpAndSettle();
    expect(asked.last, 'advances');
    expect(find.text('Answer for: advances'), findsOneWidget);
    expect(api.calls.containsKey('POST /api/pos/me/agents/buyer/ask'), isTrue);
  });
}
