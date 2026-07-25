import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podx/app.dart';

void main() {
  testWidgets('renders the localized PODX home experience', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await tester.pumpAndSettle();

    expect(find.text('PODX'), findsOneWidget);
    expect(find.text('Discover near you'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('opens catalog search from bottom navigation', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PodxApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Find your product'), findsOneWidget);
    expect(find.text('Browse categories'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
  });
}
