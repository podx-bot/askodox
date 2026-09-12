import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:podx/live_test_main.dart' as live_app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Point 1 E2E harness boots ASKODOX Android validation app', (tester) async {
    live_app.main();
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('ASKODOX Live Test'), findsOneWidget);
    expect(find.text('ASKODOX Android build is installed and running.'), findsOneWidget);
    expect(find.text('Backend configuration'), findsOneWidget);
  });
}
