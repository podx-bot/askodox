import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/catalogue_steps_screen.dart';

/// Owner 2026-11-25: Ready list in 3 steps (made-up data only).
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
  testWidgets('ready list: group -> tick -> price + GST -> added', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/pos/businesses/b1/catalogue') {
        return {
          'template_key': 'grocery',
          'registration_type': 'regular',
          'choices': [
            {'key': 'grocery', 'name': {'en': 'Grocery'}}
          ],
          'categories': [
            {
              'key': 'staples',
              'name': {'en': 'Staples', 'te': 'సరుకులు'},
              'items': [
                {'key': 'rice', 'name': {'en': 'Rice'}, 'pos_unit': 'kg', 'sizes': ['1 kg', '5 kg']},
                {'key': 'salt', 'name': {'en': 'Salt'}, 'pos_unit': 'pkt', 'in_shop': true},
              ],
            }
          ],
        };
      }
      if (path == '/api/pos/businesses/b1/catalogue/import') {
        return {
          'added': [
            {'key': 'rice'}
          ],
          'skipped': <Object?>[],
        };
      }
      return {'id': 'b1', 'role': 'owner', 'permissions': ['settings']};
    });
    await _pump(tester, api, const AskodoxCatalogueStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCatalogueSteps')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueStepsGroup-staples')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueStepsItem-salt')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueStepsItem-rice')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxCatalogueStepsNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxCatalogueStepsPriceRow-rice')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxCatalogueStepsPriceRow-salt')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('askodoxCatalogueStepsPrice-rice')), '60');
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueStepsSize-rice-5 kg')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxCatalogueStepsAdd')));
    await tester.pumpAndSettle();
    expect(api.calls.containsKey('POST /api/pos/businesses/b1/catalogue/import'), isFalse, reason: 'GST % still missing');
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueStepsRate-rice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxCatalogueStepsAdd')));
    await tester.pumpAndSettle();
    final items = (api.calls['POST /api/pos/businesses/b1/catalogue/import'] as Map)['items'] as List;
    expect((items.single as Map)['price_paise'], 6000);
    expect((items.single as Map)['size'], '5 kg');
    expect((items.single as Map)['rate_bp'], 500);
  });
}
