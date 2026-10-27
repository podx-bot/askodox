import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_collect_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    bodies['$method $path'] = body;
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

class _Reader implements AskodoxQrReader {
  _Reader(this.text);
  final String text;
  @override
  Future<String?> read(String source) async => text;
}

Widget _app(_Api api, Widget home, {AskodoxQrReader? reader}) => ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
        if (reader != null) askodoxQrReaderProvider.overrideWithValue(reader),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('any app QR photo becomes a saved UPI ID (read, confirm, save)', (tester) async {
    var saved = <Map<String, Object?>>[];
    final api = _Api((m, p, b) {
      if (p == '/api/me/payment-methods/read-qr') return {'upi_id': 'lk@ybl', 'payee_name': 'Lakshmi Kirana'};
      if (p == '/api/me/payment-methods' && m == 'POST') {
        saved = [
          {'id': 'pm_1', 'kind': 'upi', 'upi_id': 'lk@ybl', 'payee_name': 'Lakshmi Kirana', 'app': 'PhonePe', 'is_default': true}
        ];
        return {'methods': saved};
      }
      return {'methods': saved};
    });
    await tester.pumpWidget(_app(api, const AskodoxMyPaymentMethodsScreen(),
        reader: _Reader('upi://pay?pa=lk@ybl&pn=Lakshmi%20Kirana')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayMethodsEmpty')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPayOptionsNotice')), findsOneWidget);
    expect(find.textContaining('not a bank confirmation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayMethodQrPhoto')));
    await tester.pumpAndSettle();
    expect(find.text('lk@ybl'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'PhonePe');
    await tester.tap(find.byKey(const Key('askodoxPayMethodSave')));
    await tester.pumpAndSettle();
    final body = api.bodies['POST /api/me/payment-methods'] as Map;
    expect(body['kind'], 'upi');
    expect(body['qr_text'], 'upi://pay?pa=lk@ybl&pn=Lakshmi%20Kirana');
    expect(body['app'], 'PhonePe');
    expect(find.byKey(const ValueKey('askodoxPayMethod-pm_1')), findsOneWidget);
  });

  testWidgets('collect: amount QR to the shop UPI, a matched notification never confirms by itself', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var status = 'pending';
    Map<String, Object?> req() => {
          'id': 'ppr_1', 'amount_paise': 25000, 'label': 'INV-12', 'upi_id': 'lk@ybl', 'payee': 'Lakshmi Kirana',
          'upi_link': 'upi://pay?pa=lk@ybl&pn=Lakshmi&am=250.00&cu=INR', 'status': status,
        };
    final api = _Api((m, p, b) {
      if (p.endsWith('/collect')) {
        return {'method': {'id': 'pm_1', 'upi_id': 'lk@ybl', 'payee_name': 'Lakshmi Kirana'}, 'options': <Object?>[], 'can_edit': false};
      }
      if (p.endsWith('/collect/requests') && m == 'POST') return req();
      if (p.endsWith('/collect/requests')) return {'requests': [req()]};
      if (p.endsWith('/collect/requests/ppr_1')) {
        status = 'confirmed';
        return req();
      }
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosCollectScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();
    expect(find.text('lk@ybl'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.byKey(const Key('askodoxPosCollectShow')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/businesses/b1/collect/requests'], {'amount_paise': 25000, 'label': ''});
    expect(find.byKey(const Key('askodoxPosCollectQr')), findsOneWidget);
    expect(find.text('₹250'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('askodoxPosCollectStatus')), matching: find.textContaining('Waiting')),
        findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('askodoxPosCollectStatus'))).data, contains('Waiting for the customer'));
    await tester.tap(find.byKey(const Key('askodoxPosCollectConfirm')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/businesses/b1/collect/requests/ppr_1'], {'action': 'confirm'});
    expect(find.text('Confirmed by the shop'), findsWidgets);
  });
}
