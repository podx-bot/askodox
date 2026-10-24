import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_printer.dart';
import 'package:podx/features/pos/data/pos_raster.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/domain/escpos.dart';
import 'package:podx/features/pos/domain/pos_commands.dart';
import 'package:podx/features/pos/domain/pos_money.dart';
import 'package:podx/features/pos/domain/pos_tax.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Routes by path; `fail` makes a path answer like the network is down.
class _Api implements ApiClient {
  _Api(this.reply, {this.offline = const {}});
  final Object? Function(String method, String path, Object? body) reply;
  final Set<String> offline;
  final calls = <String>[];

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls.add('$method $path');
    if (offline.any(path.endsWith)) {
      return const ApiError(ApiFailure(ApiFailureType.network, message: 'offline'));
    }
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

class _Printer implements AskodoxPrinterTransport {
  final sent = <Uint8List>[];
  @override
  Future<void> write(String deviceId, Uint8List bytes) async => sent.add(bytes);
}

final _items = [
  const AskodoxPosItemRef(id: 'p1', name: 'Chicken curry cut', nameTe: 'చికెన్', unit: 'kg'),
  const AskodoxPosItemRef(id: 'p2', name: 'Eggs', nameTe: 'గుడ్లు', unit: 'pcs'),
  const AskodoxPosItemRef(id: 'p3', name: 'Basmati rice', unit: 'kg'),
  const AskodoxPosItemRef(id: 'p4', name: 'Sona rice', unit: 'kg'),
];

void main() {
  group('GST preview matches the server (shared vectors)', () {
    test('every vector in test/fixtures/pos_tax_vectors.json', () {
      final data = jsonDecode(File('test/fixtures/pos_tax_vectors.json').readAsStringSync()) as Map;
      for (final raw in data['cases'] as List) {
        final c = Map<String, Object?>.from(raw as Map);
        final lines = [for (final l in c['lines'] as List) AskodoxLineInput.fromJson(Map<String, Object?>.from(l as Map))];
        final r = askodoxInvoicePreview(lines,
            registrationType: '${c['registration_type']}',
            businessState: '${c['business_state']}',
            placeOfSupply: c['place_of_supply'] as String?);
        final exp = Map<String, Object?>.from(c['expected'] as Map);
        final totals = Map<String, Object?>.from(exp['totals'] as Map);
        expect(r.documentType, exp['document_type'], reason: '${c['name']}');
        expect(r.interState ? 'inter' : 'intra', exp['mode'], reason: '${c['name']}');
        expect(r.stateTaxLabel, exp['state_tax_label'], reason: '${c['name']}');
        expect(r.taxablePaise, totals['taxable_paise'], reason: '${c['name']} taxable');
        expect(r.cgstPaise, totals['cgst_paise'], reason: '${c['name']} cgst');
        expect(r.sgstPaise, totals['sgst_paise'], reason: '${c['name']} sgst');
        expect(r.igstPaise, totals['igst_paise'], reason: '${c['name']} igst');
        expect(r.cessPaise, totals['cess_paise'], reason: '${c['name']} cess');
        expect(r.totalPaise, totals['grand_total_paise'], reason: '${c['name']} total');
      }
    });

    test('an inclusive price is always exactly what the customer pays', () {
      for (var price = 1; price < 5000; price += 13) {
        final t = askodoxLineTax(AskodoxLineInput(qtyMilli: 1000, unitPricePaise: price, rateBp: 1800, priceIncludesTax: true),
            interState: false, collectTax: true);
        expect(t.totalPaise, price);
      }
    });
  });

  group('money and quantities are exact', () {
    test('parse and format', () {
      expect(askodoxParsePaise('0.1')! + askodoxParsePaise('0.2')!, askodoxParsePaise('0.3'));
      expect(askodoxParsePaise('₹1,234.50'), 123450);
      expect(askodoxParsePaise('1.234'), isNull);
      expect(askodoxParsePaise('-5'), isNull);
      expect(askodoxParseMilli('1.235'), 1235);
      expect(askodoxPaise(1234567), '₹12,345.67');
      expect(askodoxPaise(1234567890), '₹1,23,45,678.90');
      expect(askodoxQty(1235, 'kg'), '1.235 kg');
      expect(askodoxQty(2000, 'pcs'), '2 pcs');
      expect(askodoxRate(1800), '18%');
      expect(askodoxRate(25), '0.25%');
      expect(askodoxFinancialYear(DateTime(2026, 3, 31)), '2526');
      expect(askodoxFinancialYear(DateTime(2026, 4, 1)), '2627');
    });
  });

  group('counter commands (proposals only)', () {
    test('English and Telugu quantities, units and prices', () {
      var c = askodoxParsePosCommand('add 2 kg chicken at 240 per kg', _items);
      expect((c.kind, c.item?.id, c.qtyMilli, c.pricePaise), (AskodoxPosCommandKind.add, 'p1', 2000, 24000));
      c = askodoxParsePosCommand('chicken 500 g', _items);
      expect((c.item?.id, c.qtyMilli), ('p1', 500));
      c = askodoxParsePosCommand('అర కిలో చికెన్', _items);
      expect((c.item?.id, c.qtyMilli), ('p1', 500));
      c = askodoxParsePosCommand('12 eggs', _items);
      expect((c.item?.id, c.qtyMilli), ('p2', 12000));
      c = askodoxParsePosCommand('2 dozen eggs', _items);
      expect(c.qtyMilli, 24000);
      c = askodoxParsePosCommand('remove chicken', _items);
      expect((c.kind, c.item?.id), (AskodoxPosCommandKind.remove, 'p1'));
      c = askodoxParsePosCommand('discount 10%', _items);
      expect((c.kind, c.discountBp), (AskodoxPosCommandKind.discount, 1000));
      c = askodoxParsePosCommand('discount 20', _items);
      expect(c.discountPaise, 2000);
    });

    test('ambiguous or impossible commands are never applied', () {
      final rice = askodoxParsePosCommand('2 kg rice', _items);
      expect(rice.needsChoice, isTrue);
      expect(rice.candidates.map((c) => c.id), ['p3', 'p4']);
      expect(askodoxParsePosCommand('2 kg eggs', _items).kind, AskodoxPosCommandKind.unknown);
      expect(askodoxParsePosCommand('hello there', _items).item, isNull);
    });
  });

  group('ESC/POS', () {
    test('commands and raster', () {
      final b = AskodoxEscPos().init().align(1).bold(true).text('Hi').cut().bytes();
      expect(b.sublist(0, 2), [0x1B, 0x40]);
      expect(b.sublist(2, 5), [0x1B, 0x61, 1]);
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x03]);
      expect(() => AskodoxEscPos().text('చికెన్'), throwsArgumentError);
      expect(askodoxNeedsRaster('₹10'), isTrue);
      // 9 x 1 image: dark, light, dark ... -> 2 bytes per row
      final rgba = Uint8List(9 * 4);
      for (var x = 0; x < 9; x++) {
        final v = x.isEven ? 0 : 255;
        rgba.setAll(x * 4, [v, v, v, 255]);
      }
      final mono = askodoxMonochrome(rgba, 9, 1);
      expect(mono.widthBytes, 2);
      expect(mono.bytes, [0xAA, 0x80]);
      final raster = AskodoxEscPos().raster(mono.bytes, widthBytes: 2, height: 1).bytes();
      expect(raster.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 2, 0, 1, 0]);
    });

    test('receipt text fits the paper and shows the GST split', () {
      final invoice = {
        'number': 'SL/2627/000001',
        'local_date': '2026-10-23',
        'title': 'Tax Invoice',
        'business_snapshot': {'name': 'Sri Lakshmi Stores', 'gstin': '36AAPFU0939F1ZV'},
        'customer_snapshot': {'name': 'Walk-in customer'},
        'lines': [
          {'name': 'Biscuits', 'unit': 'pcs', 'qty_milli': 2000, 'unit_price_paise': 11800, 'total_paise': 23600, 'hsn_sac': '1905'},
        ],
        'totals': {'taxable_paise': 20000, 'cgst_paise': 1800, 'sgst_paise': 1800, 'grand_total_paise': 23600, 'state_tax_label': 'sgst'},
        'payments': [{'method': 'cash', 'amount_paise': 23600}],
      };
      final lines = askodoxReceiptLines(invoice, columns: 32);
      expect(lines.every((l) => l.length <= 32), isTrue, reason: lines.join('\n'));
      expect(lines, contains('CGST${' ' * 23}18.00'));
      expect(lines.any((l) => l.startsWith('TOTAL Rs') && l.endsWith('236.00')), isTrue);
      expect(askodoxChunks(Uint8List(450), 180).map((c) => c.length), [180, 180, 90]);
    });
  });

  testWidgets('Telugu names go to the raster path (bands of at most 255 rows)', (tester) async {
    final invoice = {
      'number': 'A/2627/000001',
      'lines': [
        {'name': 'చికెన్', 'unit': 'kg', 'qty_milli': 1000, 'unit_price_paise': 24000, 'total_paise': 24000},
      ],
    };
    expect(askodoxInvoiceNeedsRaster(invoice), isTrue);
    expect(askodoxInvoiceNeedsRaster({'number': 'A/1', 'lines': const []}), isFalse);
    final bytes = await tester.runAsync(() => askodoxRasterReceipt(askodoxReceiptLines(invoice, asciiOnly: false)));
    expect(bytes!.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(2, 6), [0x1D, 0x76, 0x30, 0x00]);
    expect(bytes[6], 48, reason: '384 dots = 48 bytes per row on 58 mm paper');
    expect(bytes[9], 0, reason: 'band height high byte: never more than 255 rows');
  });

  group('offline queue', () {
    test('device series numbers, sync, and rejected sales are kept', () async {
      SharedPreferences.setMockInitialValues({});
      final fy = askodoxFinancialYear(DateTime.now());
      var rejectNext = false;
      final api = _Api((method, path, body) {
        if (path.endsWith('/device-series')) return {'prefix': 'SD1', 'fy': fy, 'next_number': 4};
        if (path.endsWith('/invoices')) {
          if (rejectNext) {
            return const ApiFailure(ApiFailureType.validation, statusCode: 409, message: 'That invoice number is already used.');
          }
          return {'id': 'inv1', 'replayed': false};
        }
        return <String, Object?>{};
      });
      final queue = AskodoxPosOfflineQueue(AskodoxPosRepository(api, authToken: 't'));
      await queue.ensureSeries('b1');
      expect(await queue.takeNumber('b1', fy), 'SD1/$fy/000004');
      expect(await queue.takeNumber('b1', fy), 'SD1/$fy/000005');
      expect(await queue.takeNumber('b1', '9900'), isNull);
      await queue.ensureSeries('b1'); // server still says 4: the phone never goes backwards
      expect(await queue.takeNumber('b1', fy), 'SD1/$fy/000006');
      await queue.add('b1', {'client_txn_id': 'txn-00000001'});
      var result = await queue.sync();
      expect((result.sent, result.pending), (1, 0));
      rejectNext = true;
      await queue.add('b1', {'client_txn_id': 'txn-00000002'});
      result = await queue.sync();
      expect((result.sent, result.rejected), (0, 1));
      final kept = await queue.pending();
      expect(kept.single['error'], contains('already used'));
    });
  });

  group('sale screen', () {
    Map<String, Object?> business() => {
          'id': 'b1',
          'name': 'Sri Lakshmi Chicken',
          'registration_type': 'regular',
          'state_code': '36',
          'my_role': 'cashier',
          'permissions': ['view', 'sell', 'customers', 'collect', 'drafts'],
          'rules': <String, Object?>{},
        };
    final products = [
      {'id': 'p1', 'name': 'Chicken curry cut', 'name_te': 'చికెన్', 'unit': 'kg', 'price_paise': 24000, 'rate_bp': 0,
        'category': 'exempt', 'price_includes_tax': true, 'stock_milli': 20000},
    ];

    Future<_Api> pump(WidgetTester tester, {Set<String> offline = const {}}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fy = askodoxFinancialYear(DateTime.now());
      final api = _Api((method, path, body) {
        if (path == '/api/pos/businesses/b1') return business();
        if (path.endsWith('/products')) return {'products': products};
        if (path.endsWith('/device-series')) return {'prefix': 'SD1', 'fy': fy, 'next_number': 1};
        if (path.endsWith('/invoices')) return {'id': 'inv9', 'number': 'SLB/$fy/000001'};
        return <String, Object?>{};
      }, offline: offline);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
          askodoxPrinterTransportProvider.overrideWithValue(_Printer()),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const AskodoxPosSaleScreen(businessId: 'b1')),
            GoRoute(path: '/pos/b1/invoice/:iid', builder: (_, state) => Scaffold(body: Text('INVOICE ${state.pathParameters['iid']}'))),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('typed command asks for confirmation before changing the bill', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('askodoxPosCommand')), '1.5 kg chicken');
      await tester.tap(find.byKey(const Key('askodoxPosCommandGo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxPosConfirmCommand')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsNothing, reason: 'nothing changes before Yes');
      await tester.tap(find.byKey(const Key('askodoxPosConfirmYes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsOneWidget);
      expect(find.text('₹360.00'), findsWidgets);
    });

    testWidgets('weighed item: tare is subtracted, then the server issues the bill', (tester) async {
      final api = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('askodoxPosProduct-p1')));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '1.335');
      await tester.enterText(fields.at(1), '0.100');
      await tester.tap(find.byKey(const Key('askodoxPosQtyOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxPosTotal')), findsOneWidget);
      expect(find.text('₹296.40'), findsWidgets);
      await tester.tap(find.byKey(const Key('askodoxPosPay')));
      await tester.pumpAndSettle();
      expect(find.textContaining('QR'), findsNothing, reason: 'cash selected by default');
      await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosIssue')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('POST /api/pos/businesses/b1/invoices'));
      expect(find.text('INVOICE inv9'), findsOneWidget, reason: 'the server-issued bill opens');
    });

    testWidgets('no internet: kept on the phone with this device\'s own bill number', (tester) async {
      await pump(tester, offline: {'/invoices'});
      await tester.enterText(find.byKey(const Key('askodoxPosCommand')), '2 kg chicken');
      await tester.tap(find.byKey(const Key('askodoxPosCommandGo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosConfirmYes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosPay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosIssue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxPosOfflineIssued')), findsOneWidget);
      expect(find.textContaining('SD1/'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final queued = jsonDecode(prefs.getString(askodoxPosQueueKey)!) as List;
      final body = (queued.single as Map)['body'] as Map;
      expect(body['offline'], isTrue);
      expect('${body['invoice_number']}', startsWith('SD1/'));
      expect(body['payments'], [
        {'method': 'cash', 'amount_paise': 48000, 'reference': ''},
      ]);
    });
  });
}
