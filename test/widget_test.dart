import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podx/app.dart';
import 'package:podx/core/offline/offline_models.dart';
import 'package:podx/core/offline/offline_services.dart';
import 'package:podx/core/providers/offline_providers.dart';

Widget _testApp() => ProviderScope(
      overrides: [
        connectivityServiceProvider.overrideWithValue(
          MockConnectivityService(ConnectivityStatus.online),
        ),
      ],
      child: const PodxApp(),
    );

Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pumpWidget(_testApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders the localized PODX home experience', (tester) async {
    await _pumpReady(tester);

    expect(find.text('PODX'), findsOneWidget);
    expect(find.text('Discover near you'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('opens catalog search from bottom navigation', (tester) async {
    await _pumpReady(tester);

    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Find your product'), findsOneWidget);
    expect(find.text('Browse categories'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
  });
}
