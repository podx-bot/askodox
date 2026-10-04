import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/mobility/data/mobility_repository.dart';
import 'package:podx/features/mobility/presentation/mobility_screen.dart';
import 'package:podx/features/mobility/presentation/order_fulfilment_panel.dart';

class _Repo implements MobilityRepository {
  OrderFulfilment value = const OrderFulfilment(
      responsibility: 'TO_BE_DECIDED', deliveryStatus: 'TO_BE_DECIDED', commerceStatus: 'ACCEPTED');
  final calls = <String>[];

  @override
  Future<MobilityResult<OrderFulfilment>> fulfilment(String orderId) async => MobilityResult.ok(value);

  @override
  Future<MobilityResult<OrderFulfilment>> setFulfilment(String orderId, String mode,
      {Map<String, Object?>? pickup, Map<String, Object?>? drop}) async {
    calls.add(mode);
    value = OrderFulfilment(
        responsibility: mode,
        deliveryStatus: mode == 'CUSTOMER_PICKUP' ? 'NOT_REQUIRED' : 'NOT_STARTED',
        commerceStatus: 'ACCEPTED');
    return MobilityResult.ok(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

void main() {
  test('the service comes from the user\'s own words (en / te)', () {
    expect(askodoxMobilityKind('need an auto to Benz Circle'), 'ride_auto');
    expect(askodoxMobilityKind('bike taxi to the bus stand'), 'ride_bike');
    expect(askodoxMobilityKind('cab to the airport'), 'ride_airport');
    expect(askodoxMobilityKind('send a parcel to Guntur'), 'parcel');
    expect(askodoxMobilityKind('documents to the court'), 'documents');
    expect(askodoxMobilityKind('carpool to Hyderabad tomorrow'), 'carpool');
    expect(askodoxMobilityKind('టాక్సీ కావాలి'), 'ride_taxi');
    expect(askodoxMobilityKind('పార్సెల్ పంపాలి'), 'parcel');
    expect(askodoxMobilityKind('walking shoes size 9'), isNull);
    expect(askodoxMobilityKind('automatic washing machine'), isNull, reason: '"auto" only as its own word');
  });

  test('scheduled trips are sent as local date-time', () {
    expect(askodoxScheduleText(DateTime(2026, 10, 9, 7, 5)), '2026-10-09T07:05');
  });

  testWidgets('order delivery responsibility is shown apart from the order status', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [mobilityRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: AskodoxFulfilmentPanel(orderId: '42', te: false))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Who delivers is not decided yet'), findsOneWidget,
        reason: 'an ACCEPTED order is not a delivery confirmation');
    await tester.tap(find.byKey(const ValueKey('askodoxFulfilmentChoose-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I will pick it up').last);
    await tester.pumpAndSettle();
    expect(repo.calls, ['CUSTOMER_PICKUP']);
    expect(find.text('No delivery'), findsOneWidget);
  });
}
