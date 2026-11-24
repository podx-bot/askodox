import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/desk_menu_steps_screens.dart';

/// Owner 2026-11-24: the desk menu in 3 pieces (made-up data only).
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
  testWidgets('menu: count, list, item sheet, add in 2 steps', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/desk/menu/parse')) {
        return {
          'items': [
            {'name': 'Idli', 'price_paise': 3000},
            {'name': 'Dosa', 'price_paise': 5000},
          ],
          'gst': false,
        };
      }
      if (path.endsWith('/desk/menu/import')) return {'created': 2, 'updated': 0};
      if (path.endsWith('/desk/menu')) {
        return {
          'items': [
            {'id': 'i1', 'name': 'Biryani', 'price_paise': 18000, 'available': true, 'item_no': 1},
            {'id': 'i2', 'name': 'Tea', 'price_paise': 1000, 'available': false},
          ]
        };
      }
      return {'ok': true};
    });
    await _pump(tester, api, const AskodoxDeskMenuStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxDeskMenuSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDeskMenuStepsItem-i1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeskMenuStepsItem-i2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDeskMenuStepsAvail-i2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeskMenuStepsAvail-i2')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('POST') || k.startsWith('PUT') || k.startsWith('PATCH')), isTrue);
    await tester.tap(find.byKey(const Key('askodoxDeskMenuStepsAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxDeskMenuStepsText')), 'Idli 30\nDosa 50');
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxDeskMenuStepsCheck')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDeskMenuSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeskMenuStepsSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDeskMenuSteps3')), findsOneWidget);
    expect(api.calls.keys.any((k) => k.contains('/desk/menu/import')), isTrue);
  });
}
