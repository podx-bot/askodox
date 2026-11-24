
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/branches_screen.dart';
import 'package:podx/features/pos/presentation/collect_qr_sheet.dart';

/// Owner 2026-11-24: branches (link own shops, all-branches today) and the owner-UPI QR sheet.
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
  testWidgets('branches: two shops need ticking, then the group shows today for every branch', (tester) async {
    var linked = false;
    final api = _Api((method, path, body) {
      if (method == 'PUT') {
        linked = true;
        return {'groups': [], 'my_shops': []};
      }
      if (path.endsWith('/overview')) {
        return {
          'group': {'id': 'g1', 'name': 'Sai Sweets'},
          'branches': [
            {'id': 'b1', 'name': 'Vuyyuru', 'invoices': 3, 'sales_paise': 150000, 'delivery_done': 1, 'dues_paise': 0},
            {'id': 'b2', 'name': 'Gudivada', 'invoices': 2, 'sales_paise': 50000, 'delivery_done': 0, 'dues_paise': 2000},
          ],
          'total': {'invoices': 5, 'sales_paise': 200000, 'delivery_done': 1, 'dues_paise': 2000},
        };
      }
      return {
        'groups': linked ? [{'id': 'g1', 'name': 'Sai Sweets', 'branches': []}] : [],
        'my_shops': [
          {'id': 'b1', 'name': 'Vuyyuru'},
          {'id': 'b2', 'name': 'Gudivada'},
        ],
      };
    });
    await _pump(tester, api, const AskodoxBranchesScreen());
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('askodoxBranchLink'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('askodoxBranchPick-b1')));
    await tester.tap(find.byKey(const ValueKey('askodoxBranchPick-b2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('askodoxBranchLink')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls['PUT /api/pos/me/branches'], {'name': '', 'business_ids': ['b1', 'b2']});
    expect(find.textContaining('₹2000'), findsOneWidget);
    expect(find.text('Gudivada'), findsWidgets);
  });

  testWidgets('owner QR sheet shows the amount and a confirm button', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/collect/for')) {
        return {'id': 'r1', 'amount_paise': 60000, 'label': 'Token 4 Blouse', 'status': 'pending', 'upi_link': 'upi://pay?pa=a@b'};
      }
      return {'requests': []};
    });
    await _pump(
        tester,
        api,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => askodoxShowCollectQr(context, ref, businessId: 'b1', kind: 'job', refId: 'j1'),
              child: const Text('open'),
            ),
          ),
        ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.calls['POST /api/pos/businesses/b1/collect/for'], {'kind': 'job', 'ref_id': 'j1'});
    expect(find.text('₹600'), findsOneWidget);
    expect(find.byKey(const Key('askodoxCollectQr')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCollectQrConfirm')), findsOneWidget);
  });
}
