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
}
