import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/home/presentation/question_mic.dart';
import 'package:podx/features/location/application/location_controller.dart' show deviceLocationGatewayProvider;
import 'package:podx/features/location/domain/device_location_gateway.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/bill_steps_screen.dart';
import 'package:podx/features/steps/presentation/checkin_steps_screen.dart';
import 'package:podx/features/steps/presentation/day_steps_screen.dart';
import 'package:podx/features/steps/presentation/dues_steps_screen.dart';

/// Owner 2026-11-22: every second page in 3 pieces, every job in 3 steps. Made-up shop data only.
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

/// The phone's place in a test (owner 2026-11-23 attendance: location is compulsory; a fake-GPS fix says so).
class _Place extends DeviceLocationGateway {
  _Place(this.point, {this.allowed = true});
  final GeoPoint? point;
  final bool allowed;
  @override
  Future<LocationPermissionStatus> ensurePermission() async =>
      allowed ? LocationPermissionStatus.granted : LocationPermissionStatus.denied;
  @override
  Future<LocationPermissionStatus> checkPermission() => ensurePermission();
  @override
  Future<GeoPoint?> getCurrentPosition() async => point;
  @override
  Stream<GeoPoint> watchPosition({int distanceFilterMetres = 300}) => const Stream.empty();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child, {DeviceLocationGateway? place}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp phone
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
      if (place != null) deviceLocationGatewayProvider.overrideWithValue(place),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

const _menu = {
  'items': [
    {'id': 'p1', 'name': 'Chicken skinless', 'unit': 'kg', 'price_paise': 24000, 'item_no': 12, 'available': true},
    {'id': 'p2', 'name': 'Eggs', 'unit': 'pcs', 'price_paise': 600, 'item_no': 3, 'available': true},
    {'id': 'p3', 'name': 'Mutton', 'unit': 'kg', 'price_paise': 75000, 'item_no': 21, 'available': false},
  ],
};

Object? _common(String method, String path) {
  if (path == '/api/shops/b1') return {'name': 'Test Chicken Centre'};
  if (path == '/api/me/payment-methods') return {'methods': []};
  return null;
}

void main() {
  testWidgets('bill: tap the tiles (kg goes 1, 1½), next, Cash -> one real bill and the big ✓', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/desk/menu')) return _menu;
      if (path.endsWith('/quick-bill')) {
        return {'id': 'inv1', 'number': 'B1/26-27/000007', 'totals': {'grand_total_paise': 36600}, 'pending_paise': 0};
      }
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxBillStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxBillSteps1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStepBar')), findsOneWidget);
    expect(find.text('What did they take?'), findsOneWidget);
    expect(find.byKey(const Key('askodoxBillTile-p3')), findsNothing, reason: 'sold out today');
    await tester.tap(find.byKey(const Key('askodoxBillTile-p1')));
    await tester.tap(find.byKey(const Key('askodoxBillTile-p1')));
    await tester.tap(find.byKey(const Key('askodoxBillTile-p2')));
    await tester.pump();
    expect(find.text('1½'), findsOneWidget);
    expect(find.text('Next · ₹366'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillStepsNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBillSteps2')), findsOneWidget);
    expect(find.text('How did they pay?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillPayCash')));
    await tester.pumpAndSettle();
    final body = api.calls['POST /api/pos/businesses/b1/quick-bill']! as Map;
    expect(body['method'], 'cash');
    expect(body['advance_paise'], 36600);
    expect((body['lines'] as List).first,
        {'item_no': 12, 'name': 'Chicken skinless', 'amount_paise': 36000, 'rate_paise': 24000, 'qty_milli': 1500});
    expect((body['lines'] as List)[1], {'item_no': 3, 'name': 'Eggs', 'amount_paise': 600, 'rate_paise': 600, 'qty_milli': 1000});
    expect(find.byKey(const Key('askodoxBillSteps3')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStepDone')), findsOneWidget);
    expect(find.text('Bill B1/26-27/000007 · cash'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillStepsNew')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBillSteps1')), findsOneWidget);
    expect(find.text('1½'), findsNothing);
  });

  testWidgets('calculator bill (owner 2026-11-26): qty x rate rows are added to the bill and billed as real lines', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/desk/menu')) return _menu;
      if (path.endsWith('/quick-bill')) {
        return {'id': 'inv3', 'number': 'B1/26-27/000009', 'totals': {'grand_total_paise': 5500}, 'pending_paise': 0};
      }
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxBillStepsScreen(businessId: 'b1'));
    await tester.tap(find.byKey(const Key('askodoxStepMore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBillStepsCalc')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxBillCalcName-0')), 'Rope');
    await tester.enterText(find.byKey(const Key('askodoxBillCalcQty-0')), '2');
    await tester.enterText(find.byKey(const Key('askodoxBillCalcRate-0')), '12.50');
    await tester.tap(find.byKey(const Key('askodoxBillCalcAddRow')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxBillCalcQty-1')), '3');
    await tester.enterText(find.byKey(const Key('askodoxBillCalcRate-1')), '10');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBillCalcTotal')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('askodoxBillCalcTotal'))).data, '₹55');
    await tester.tap(find.byKey(const Key('askodoxBillCalcOk')));
    await tester.pumpAndSettle();
    expect(find.text('Next · ₹55'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillStepsNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBillPayCash')));
    await tester.pumpAndSettle();
    final lines = (api.calls['POST /api/pos/businesses/b1/quick-bill']! as Map)['lines'] as List;
    expect(lines[0], {'name': 'Rope', 'amount_paise': 2500, 'qty_milli': 2000, 'rate_paise': 1250});
    expect(lines[1], {'name': 'Item', 'amount_paise': 3000, 'qty_milli': 3000, 'rate_paise': 1000});
  });

  testWidgets('bill by voice: "12 number 2, UPI" fills the tile and pre-selects Online -- nothing is billed by itself',
      (tester) async {
    final api = _Api((method, path, body) => path.endsWith('/desk/menu') ? _menu : (_common(method, path) ?? {}));
    await _pump(tester, api, const AskodoxBillStepsScreen(businessId: 'b1'));
    tester.widget<AskodoxQuestionMic>(find.byType(AskodoxQuestionMic)).onText('12 number 2, UPI');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBillSteps2')), findsOneWidget);
    expect(find.text('You said'), findsOneWidget);
    expect(find.text('₹480'), findsOneWidget);
    expect(api.calls.keys.where((k) => k.endsWith('/quick-bill')), isEmpty);
    await tester.tap(find.byKey(const Key('askodoxStepBack')));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('bill with no items yet: type the amount, then Due asks the name and the pay date', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/desk/menu')) return {'items': []};
      if (path.endsWith('/quick-bill')) {
        return {'id': 'inv2', 'number': 'B1/26-27/000008', 'totals': {'grand_total_paise': 50000}, 'pending_paise': 50000};
      }
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxBillStepsScreen(businessId: 'b1'));
    expect(find.text('How much?'), findsOneWidget);
    for (final k in ['5', '00']) {
      await tester.tap(find.byKey(Key('askodoxStepKey-$k')));
      await tester.pump();
    }
    expect(find.text('Next · ₹500'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillStepsNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBillPayDue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxBillDueName')), 'Ravi');
    await tester.tap(find.byKey(const Key('askodoxBillDueOk')));
    await tester.pumpAndSettle();
    final body = api.calls['POST /api/pos/businesses/b1/quick-bill']! as Map;
    expect(body['name'], 'Ravi');
    expect(body['advance_paise'], 0);
    expect(body['lines'], [
      {'name': '', 'amount_paise': 50000},
    ]);
    expect(api.calls.keys.any((k) => k.startsWith('PUT /api/pos/businesses/b1/dues/inv2/date')), isTrue);
    expect(find.byKey(const Key('askodoxBillSteps3')), findsOneWidget);
    expect(find.textContaining('Due ₹500'), findsOneWidget);
  });

  testWidgets('dues: who -> how much (keypad, quick ₹1,000) -> received; the money goes on the oldest bill first',
      (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/dues')) {
        return {
          'total_paise': 150000,
          'people': [
            {
              'name': 'Ramesh',
              'last4': '4321',
              'due_paise': 150000,
              'oldest': '2026-11-10',
              'bills': [
                {'id': 'i2', 'number': 'B/2', 'local_date': '2026-11-15', 'due_paise': 100000, 'total_paise': 100000},
                {'id': 'i1', 'number': 'B/1', 'local_date': '2026-11-10', 'due_paise': 50000, 'total_paise': 50000},
              ],
            },
          ],
        };
      }
      if (path.endsWith('/settle')) return {'due_paise': 0};
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxDuesStepsScreen(businessId: 'b1'));
    expect(find.text('Who paid?'), findsOneWidget);
    expect(find.text('₹1,500'), findsWidgets);
    await tester.tap(find.byKey(const Key('askodoxDuesStepsPerson-Ramesh-4321')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDuesSteps2')), findsOneWidget);
    expect(find.text('How much did they pay?'), findsOneWidget);
    // The whole due is only a suggestion: typing replaces it (was ₹1,500 + "200" = ₹15,00,200).
    for (final k in ['2', '00']) {
      await tester.ensureVisible(find.byKey(Key('askodoxStepKey-$k')));
      await tester.pump();
      await tester.tap(find.byKey(Key('askodoxStepKey-$k')));
      await tester.pump();
    }
    expect(find.text('₹200'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('askodoxStepQuick-1000')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxStepQuick-1000')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxDuesStepsGot')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/pos/businesses/b1/bills/i1/settle']! as Map)['amount_paise'], 50000);
    expect((api.calls['POST /api/pos/businesses/b1/bills/i2/settle']! as Map)['amount_paise'], 50000);
    expect(find.byKey(const Key('askodoxDuesSteps3')), findsOneWidget);
    expect(find.text('₹1,000 received'), findsOneWidget);
    expect(find.text('Still due ₹500'), findsOneWidget);
  });

  testWidgets('check-in: one round button from the person\'s own day (in -> leaving -> done)', (tester) async {
    AskodoxJson? me;
    final api = _Api((method, path, body) {
      if (path.endsWith('/attendance/today')) {
        return {'boss': true, 'people': [], 'settings': {'start_time': '09:00'}, 'me': me};
      }
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCheckInSteps1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCheckInStepsGo-in')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCheckInStepsLeave')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    me = {'in_at': '2026-11-22T09:02:00+05:30', 'out_at': null, 'status': 'P'};
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCheckInStepsGo-out')), findsOneWidget, reason: 'the owner checked in: now "leaving"');
    expect(find.byKey(const Key('askodoxCheckInStepsLeave')), findsNothing);
    await tester.pumpWidget(const SizedBox());

    me = {'in_at': '2026-11-22T09:02:00+05:30', 'out_at': '2026-11-22T21:10:00+05:30', 'status': 'P'};
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCheckInStepsFinished')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('check-in (owner 2026-11-23): location off, far away, no shop pin and fake GPS each stop it in words',
      (tester) async {
    var pin = <String, Object?>{'lat': 16.3650, 'lng': 80.8470};
    final sent = <Object?>[];
    final api = _Api((method, path, body) {
      if (path.endsWith('/attendance/today')) return {'boss': true, 'people': [], 'settings': {'start_time': '09:00'}, 'me': null};
      if (path.endsWith('/attendance/settings') && method == 'GET') {
        return {'radius_m': 150, 'require_location': true, 'require_live_face': true, 'outside_needs_ok': true, 'pin': pin};
      }
      if (path.endsWith('/attendance/settings') && method == 'PUT') {
        pin = {'lat': (body as Map)['pin_lat'], 'lng': body['pin_lng']};
        return {'radius_m': 150, 'require_location': true, 'require_live_face': false, 'pin': pin};
      }
      if (path.endsWith('/attendance/check')) {
        sent.add(body);
        return {'in_at': '2026-11-23T09:01:00+05:30', 'status': 'P', 'distance_m': 0, 'far': false, 'method': 'device_lock'};
      }
      return _common(method, path) ?? {};
    });
    // location off
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'), place: _Place(null, allowed: false));
    await tester.tap(find.byKey(const Key('askodoxCheckInStepsGo-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCheckInOpenLocation')), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing is marked without a place');
    await tester.pumpWidget(const SizedBox());
    // 2.3 km away: ask the owner or go back -- never marked silently
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'), place: _Place(const GeoPoint(16.385, 80.847)));
    await tester.tap(find.byKey(const Key('askodoxCheckInStepsGo-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCheckInAskOwner')), findsOneWidget);
    expect(find.textContaining('2.2 km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // fake GPS: sent as such -- the server refuses and tells the owner
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'),
        place: _Place(const GeoPoint(16.3651, 80.8471, mocked: true)));
    await tester.tap(find.byKey(const Key('askodoxCheckInStepsGo-in')));
    await tester.pumpAndSettle();
    expect((sent.last as Map)['mocked'], isTrue);
    await tester.pumpWidget(const SizedBox());
    // no shop pin yet, the owner is in the shop: "yes, this is the shop" sets it once
    pin = {};
    await _pump(tester, api, const AskodoxCheckInStepsScreen(businessId: 'b1'), place: _Place(const GeoPoint(16.3651, 80.8471)));
    await tester.tap(find.byKey(const Key('askodoxCheckInStepsGo-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxCheckInPinHere')));
    await tester.pumpAndSettle();
    expect(pin['lat'], 16.3651);
    expect(api.calls.keys, contains('PUT /api/pos/businesses/b1/attendance/settings'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('day close: online right? -> drawer cash -> asked once -> closed, sent on WhatsApp from ✓', (tester) async {
    var closed = false;
    final api = _Api((method, path, body) {
      final day = {
        'invoices': 5,
        'sales_paise': 500000,
        'tax_paise': 0,
        'payments': {
          'cash': {'net_paise': 300000},
          'upi': {'net_paise': 200000},
        },
        'closed': closed ? {'counted_cash_paise': 300000, 'expected_cash_paise': 300000, 'difference_paise': 0} : null,
      };
      if (path.contains('/day/')) return day;
      if (path.endsWith('/day-close')) {
        closed = true;
        return {...day, 'closed': {'counted_cash_paise': 300000, 'expected_cash_paise': 300000, 'difference_paise': 0}};
      }
      return _common(method, path) ?? {};
    });
    await _pump(tester, api, const AskodoxDayStepsScreen(businessId: 'b1'));
    expect(find.text('Is the online money right?'), findsOneWidget);
    expect(find.text('₹2,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDayStepsOnlineOk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxDaySteps2')), findsOneWidget);
    for (final k in ['3', '0', '0', '0']) {
      await tester.tap(find.byKey(Key('askodoxStepKey-$k')));
      await tester.pump();
    }
    expect(find.text('Exact ✓'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDayStepsClose')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.where((k) => k.endsWith('/day-close')), isEmpty, reason: 'closing is final: it asks first');
    await tester.tap(find.byKey(const Key('askodoxDayStepsConfirm')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/pos/businesses/b1/day-close']! as Map)['counted_cash_paise'], 300000);
    expect(find.byKey(const Key('askodoxDaySteps3')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDayStepsClosed')), findsOneWidget);
    expect(find.text('Drawer exact ✓'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // A day already closed opens straight on the ✓.
    await _pump(tester, api, const AskodoxDayStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxDaySteps3')), findsOneWidget);
  });
}
