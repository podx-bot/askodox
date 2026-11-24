import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/branches_steps_screen.dart';

/// Owner 2026-11-24: All my branches in 3 pieces (made-up data only).
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
  testWidgets('branches: total, a row, link button, remove asks once', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/overview')) {
        return {
          'total': {'sales_paise': 150000, 'invoices': 7, 'delivery_done': 2, 'dues_paise': 0},
          'branches': [
            {'id': 'b1', 'name': 'Shop One', 'sales_paise': 100000, 'invoices': 4},
            {'id': 'b2', 'name': 'Shop Two', 'sales_paise': 50000, 'invoices': 3},
          ],
        };
      }
      if (m == 'GET') {
        return {
          'my_shops': [
            {'id': 'b1', 'name': 'Shop One'},
            {'id': 'b2', 'name': 'Shop Two'}
          ],
          'groups': [
            {'id': 'g1', 'name': 'Mine'}
          ],
        };
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxBranchesStepsScreen());
    expect(find.byKey(const Key('askodoxBranchesSteps')), findsOneWidget);
    expect(find.text('₹1500'), findsWidgets);
    expect(find.byKey(const ValueKey('askodoxBranchesStepsRow-b1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBranchesStepsAdd')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxBranchesStepsRow-b2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBranchesStepsRemoveYes')), findsOneWidget);
  });

  testWidgets('branches: nothing linked says so', (tester) async {
    final api = _Api((m, path, b) => {'my_shops': <Object?>[], 'groups': <Object?>[]});
    await _pump(tester, api, const AskodoxBranchesStepsScreen());
    expect(find.byKey(const Key('askodoxBranchesStepsAdd')), findsNothing);
    expect(find.text('₹0'), findsOneWidget);
  });
}
