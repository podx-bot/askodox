import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podx/app.dart';

Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders the localized ASKODOX home experience', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await _pumpReady(tester);

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Discover near you'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('opens catalog search from bottom navigation', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await _pumpReady(tester);

    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Find your product'), findsOneWidget);
    expect(find.text('Browse categories'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
  });
}
