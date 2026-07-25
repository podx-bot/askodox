import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/seller/presentation/seller_dashboard_screen.dart';

void main() {
  testWidgets('dashboard presents seller inventory and request metrics', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SellerDashboardScreen())));
    expect(find.text('Seller dashboard'), findsOneWidget);
    expect(find.text('Total products'), findsOneWidget);
    expect(find.text('Price updates'), findsOneWidget);
    expect(find.text('New requests'), findsOneWidget);
  });
}
