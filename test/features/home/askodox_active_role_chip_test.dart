import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the buyer chip in English', (tester) async {
    await tester.pumpWidget(
      wrap(const AskodoxActiveRoleChip(role: 'BUYER', te: false)),
    );

    expect(find.text('Buyer mode activated'), findsOneWidget);
    expect(find.text('🛒'), findsOneWidget);
  });

  testWidgets('shows the seller chip in Telugu', (tester) async {
    await tester.pumpWidget(
      wrap(const AskodoxActiveRoleChip(role: 'SELLER', te: true)),
    );

    expect(find.text('విక్రేత మోడ్ యాక్టివేట్ అయింది'), findsOneWidget);
  });

  testWidgets('shows the job seeker label for the WORKER capability',
      (tester) async {
    await tester.pumpWidget(
      wrap(const AskodoxActiveRoleChip(role: 'WORKER', te: false)),
    );

    expect(find.text('Job Seeker mode activated'), findsOneWidget);
  });

  testWidgets('shows the delivery partner chip', (tester) async {
    await tester.pumpWidget(
      wrap(const AskodoxActiveRoleChip(role: 'DELIVERY_PARTNER', te: false)),
    );

    expect(find.text('Delivery Partner mode activated'), findsOneWidget);
  });

  testWidgets('renders nothing for an unrecognised or empty role',
      (tester) async {
    await tester.pumpWidget(
      wrap(const AskodoxActiveRoleChip(role: 'UNKNOWN_CAPABILITY', te: false)),
    );

    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.textContaining('mode activated'), findsNothing);
  });
}
