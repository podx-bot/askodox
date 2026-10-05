import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/features/home/presentation/deal_lifecycle_panel.dart';
import 'package:podx/features/orders/data/order_repository.dart';

class _Lifecycle extends OrderLifecycleRepository {
  _Lifecycle() : super(MockApiClient());

  @override
  Future<OrderDetail> detail(String orderId) async => const OrderDetail(
        order: Order(id: 'o1', buyerUserId: 'b', sellerUserId: 's', productId: 'p', productTitle: 'Shoes',
            status: 'PLACED'),
        sellerUnresponsive: true,
      );
}

Widget _app(bool seller) => ProviderScope(
      overrides: [orderLifecycleRepositoryProvider.overrideWithValue(_Lifecycle())],
      child: MaterialApp(home: Scaffold(body: AskodoxDealPanel(orderId: 'o1', te: false, sellerView: seller))),
    );

void main() {
  testWidgets('D29: the seller sees seller copy next to Accept / Decline, never buyer copy', (tester) async {
    await tester.pumpWidget(_app(true));
    await tester.pumpAndSettle();
    expect(find.text('New request — accept or decline'), findsOneWidget);
    expect(find.text('The customer is waiting for your reply.'), findsOneWidget);
    expect(find.textContaining('waiting for the seller'), findsNothing);
    expect(find.textContaining('The seller has not responded'), findsNothing);
  });

  testWidgets('the buyer still sees buyer copy', (tester) async {
    await tester.pumpWidget(_app(false));
    await tester.pumpAndSettle();
    expect(find.textContaining('waiting for the seller'), findsOneWidget);
    expect(find.text('The seller has not responded yet.'), findsOneWidget);
  });
}
