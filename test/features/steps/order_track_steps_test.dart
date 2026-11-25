import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/order_track_steps_screen.dart';

/// Owner 2026-11-25: My order in 3 pieces (made-up data only).
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
  testWidgets('my order: where it is, steps + items, pay cash from the big button', (tester) async {
    final api = _Api((m, path, b) {
      final cash = m == 'POST' && path.endsWith('/pay-choice');
      return {
        'id': 'o1',
        'business_name': 'Test Hotel',
        'kind': 'takeaway',
        'stage': 'cooking',
        'stage_text': {'en': 'Being cooked', 'te': 'వండుతున్నారు'},
        'flow': ['placed', 'accepted', 'cooking', 'ready', 'done'],
        'timeline': [
          {'stage': 'placed', 'at': '2026-11-25T10:00:00'},
          {'stage': 'accepted', 'at': '2026-11-25T10:02:00'},
          {'stage': 'cooking', 'at': '2026-11-25T10:05:00'},
        ],
        'items': [
          {'name': 'Idli', 'qty': 2, 'price_paise': 3000}
        ],
        'estimate_paise': 6000,
        'pay_choice': cash ? 'cash' : null,
        'can_cancel': false,
      };
    });
    await _pump(tester, api, const AskodoxOrderTrackStepsScreen(orderId: 'o1'));
    expect(find.byKey(const Key('askodoxOrderTrackSteps')), findsOneWidget);
    expect(find.text('Being cooked'), findsOneWidget);
    expect(find.text('2 × Idli'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrderTrackStepsPay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxOrderTrackStepsCash')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/pos/order-desk/mine/o1/pay-choice'] as Map)['choice'], 'cash');
    await tester.pumpWidget(const SizedBox());
  });
}
