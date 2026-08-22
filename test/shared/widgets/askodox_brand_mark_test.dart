import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/askodox_brand_mark.dart';

void main() {
  testWidgets('ASKODOX brand mark renders mark and optional wordmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AskodoxBrandMark(
              showWordmark: true,
              subtitle: 'Ask Anything. Get It Done.',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('askodoxBrandMark')), findsOneWidget);
    expect(find.byKey(const Key('askodoxWordmark')), findsOneWidget);
    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Ask Anything. Get It Done.'), findsOneWidget);
  });
}
