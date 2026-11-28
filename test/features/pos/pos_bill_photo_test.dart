import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_bill_photo_screen.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    bodies['$method $path'] = body;
    final out = reply(method, path, body);
    if (out is ApiFailure) return ApiError(out);
    return ApiSuccess(out as T);
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

final _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class _Picker implements AskodoxMediaPicker {
  @override
  Future<List<ChatAttachment>> pick(String source) async =>
      [ChatAttachment(name: 'bill.png', bytes: _png1x1, mimeType: 'image/png')];
}

void main() {
  // Owner 2026-11-26 (hand-written bill for live birds: 3 rows of one item, "Total 130 kg", date 24/11): the selling
  // price is never demanded; the date shows; the written total is checked against the rows -- ask, then save.
  testWidgets('bill photo: no selling price needed, date shown, written total checked before saving', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Map<String, Object?> line(int milli) => {'name': 'Birds Kg.', 'unit': 'kg', 'qty_milli': milli, 'cost_paise': 9800,
          'rate_bp': 0, 'new': true, 'product_id': null, 'price_paise': null, 'ask': <String>[]};
    final api = _Api((method, path, body) {
      if (path.endsWith('/purchases/photo')) {
        return {'read': true, 'supplier': {'name': 'Star Broilers', 'gstin': '', 'phone': ''}, 'supplier_id': null,
          'supplier_name': 'Star Broilers', 'bill_no': '65', 'bill_date': '2026-11-24', 'total_paise': null,
          'total_qty_milli': 130000, 'lines': [line(42600), line(44600), line(43200)], 'ask': <String>[], 'new_items': 3};
      }
      if (path.endsWith('/purchases/from-photo')) return {'id': 'pur1', 'created_items': 1};
      return <String, Object?>{};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
        askodoxMediaPickerProvider.overrideWithValue(_Picker()),
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<bool>(builder: (_) => const AskodoxPosBillPhotoScreen(businessId: 'b1'))),
                  child: const Text('OPEN')))),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosBillPhotoGallery')));
    await tester.pumpAndSettle();
    expect(find.text('24-11-2026'), findsOneWidget, reason: 'the date written on the bill is shown');
    expect(find.textContaining('130.4 kg'), findsWidgets, reason: 'the rows are added up');
    expect(find.textContaining('does not match'), findsOneWidget, reason: 'the bill says 130 kg');
    expect(find.textContaining('42.6 × ₹98 = ₹4174.80'), findsOneWidget, reason: 'each row shows its amount');
    await tester.tap(find.byKey(const Key('askodoxPosBillPhotoSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosBillPhotoConfirm')), findsOneWidget, reason: 'asked before saving');
    expect(api.bodies.containsKey('POST /api/pos/businesses/b1/purchases/from-photo'), isFalse);
    await tester.tap(find.byKey(const Key('askodoxPosBillPhotoConfirmYes')));
    await tester.pumpAndSettle();
    final sent = api.bodies['POST /api/pos/businesses/b1/purchases/from-photo'] as Map;
    expect(sent['bill_date'], '2026-11-24');
    final lines = sent['lines'] as List;
    expect(lines.length, 3);
    expect((lines.first as Map).containsKey('price_paise'), isFalse, reason: 'no selling price was typed and none is sent');
  });

  // Owner 2026-11-28 (design "Purchase"): GST bill or hand slip, GST shown on the rows, then another bill.
  testWidgets('bill photo: GST bill shows its GST; a hand slip has none; save and add another bill', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((method, path, body) {
      if (path.endsWith('/purchases/photo')) {
        return {'read': true, 'supplier': {'name': 'Sample Farm', 'gstin': '36ABCDE1234F1Z5', 'phone': ''}, 'supplier_id': null,
          'supplier_name': 'Sample Farm', 'bill_no': '7', 'bill_date': '2026-11-24', 'total_paise': null, 'total_qty_milli': null,
          'lines': [
            {'name': 'Oil', 'unit': 'L', 'qty_milli': 15000, 'cost_paise': 12000, 'rate_bp': 500, 'new': true, 'product_id': null, 'price_paise': null, 'ask': <String>[]},
          ], 'ask': <String>[], 'new_items': 1};
      }
      if (path.endsWith('/purchases/from-photo')) return {'id': 'pur1', 'created_items': 1};
      return <String, Object?>{};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
        askodoxMediaPickerProvider.overrideWithValue(_Picker()),
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<bool>(builder: (_) => const AskodoxPosBillPhotoScreen(businessId: 'b1'))),
                  child: const Text('OPEN')))),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosBillPhotoGallery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹90'), findsWidgets, reason: '5% of 15 L x Rs 120 = Rs 90');
    expect(find.byKey(const Key('askodoxPosBillPhotoTotalWithGst')), findsOneWidget);
    await tester.tap(find.text('No GST / hand slip'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosBillPhotoGst')), findsNothing, reason: 'a hand slip has no GST');
    await tester.ensureVisible(find.byKey(const Key('askodoxPosBillPhotoSaveNext')));
    await tester.tap(find.byKey(const Key('askodoxPosBillPhotoSaveNext')));
    await tester.pumpAndSettle();
    final sent = api.bodies['POST /api/pos/businesses/b1/purchases/from-photo'] as Map;
    expect((sent['supplier'] as Map)['gstin'], '');
    expect(((sent['lines'] as List).first as Map)['rate_bp'], 0);
    expect(find.byKey(const Key('askodoxPosBillPhotoGallery')), findsOneWidget, reason: 'ready for the next bill');
    expect(find.byKey(const Key('askodoxPosBillPhotoSupplier')), findsNothing);
  });
}
