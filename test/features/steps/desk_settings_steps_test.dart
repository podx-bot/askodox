import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/desk_settings_steps_screens.dart';

/// Owner 2026-11-24: order desk settings in 3 pieces (made-up data only).
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
  Object? reply(String m, String path, Object? b) {
    if (path.endsWith('/desk/settings')) {
      return {
        'people': [
          {'id': 'p1', 'label': 'Me', 'role': 'owner', 'you': true},
          {'id': 'p2', 'label': 'Ravi', 'role': 'cashier'},
        ],
        'routing': {
          'new': ['p2']
        },
      };
    }
    if (path.endsWith('/desk/request-settings')) {
      return {
        'requests': [
          {'key': 'water', 'en': 'Water', 'te': 'నీళ్లు', 'enabled': true},
          {'key': 'bill', 'en': 'Bill', 'te': 'బిల్', 'enabled': true},
        ]
      };
    }
    if (path.endsWith('/welcome')) {
      return {'enabled': true, 'hello': '', 'again': '', 'thanks': '', 'defaults': {'hello': 'Hi', 'again': 'Hi again', 'thanks': 'Thanks'}};
    }
    return {'ok': true};
  }

  testWidgets('desk settings: four steps, pick people, table asks, welcome', (tester) async {
    final api = _Api(reply);
    await _pump(tester, api, const AskodoxDeskSettingsStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxDeskSettingsSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDeskStepsPick-kitchen')), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeskStepsPick-kitchen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxDeskStepsRoute-kitchen-p2')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('PUT') || k.startsWith('POST')), isTrue);
  });

  testWidgets('desk settings: table asks and welcome open from the menu', (tester) async {
    final api = _Api(reply);
    await _pump(tester, api, const AskodoxDeskSettingsStepsScreen(businessId: 'b1'));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxDeskStepsMoreTable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDeskStepsTable')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDeskStepsReq-water')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeskStepsTableDone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDeskSettingsSteps')), findsOneWidget);
  });
}
