import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podx/app.dart';

Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _usePhoneViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders the localized ASKODOX home experience', (tester) async {
    await _usePhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await _pumpReady(tester);

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Discover near you'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('opens catalog search from bottom navigation', (tester) async {
    await _usePhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await _pumpReady(tester);

    final destinations = find.byType(NavigationDestination);
    expect(destinations, findsNWidgets(5));
    await tester.tap(destinations.at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Find your product'), findsOneWidget);
    expect(find.text('Browse categories'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
  });
}
