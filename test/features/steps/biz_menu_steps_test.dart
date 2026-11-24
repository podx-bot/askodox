import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/biz_menu_steps_screens.dart';

/// Owner 2026-11-24: the menu sections in 3 pieces (made-up data only).
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
  Object? reply(String m, String path, Object? b) => {
        'items': [
          {'id': 'i1', 'name': 'Biryani', 'price_paise': 18000, 'available': true, 'item_no': 1, 'menu_group': 'Rice'},
          {'id': 'i2', 'name': 'Pulao', 'price_paise': 15000, 'available': false, 'menu_group': 'Rice'},
          {'id': 'i3', 'name': 'Tea', 'price_paise': 1000, 'available': true, 'menu_group': 'Drinks'},
        ]
      };

  testWidgets('menu sections: count, section rows', (tester) async {
    await _pump(tester, _Api(reply), const AskodoxBizMenuStepsScreen(businessId: 'b1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBizMenuSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizMenuStepsSection-Rice')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizMenuStepsSection-Drinks')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizMenuStepsAdd')), findsOneWidget);
  });

  testWidgets('one section: its items only, out today shown', (tester) async {
    await _pump(tester, _Api(reply), const AskodoxBizSectionStepsScreen(businessId: 'b1', section: 'Rice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBizSectionSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizSectionStepsItem-i1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizSectionStepsItem-i2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBizSectionStepsItem-i3')), findsNothing);
  });
}
