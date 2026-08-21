import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podx/app.dart';

void main() {
  testWidgets('renders the ASKODOX AI-first home experience', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AskodoxApp()));
    await tester.pump();

    expect(find.text('ASKODOX AI'), findsOneWidget);
    expect(find.text('Ask anything local. Buy, sell, work, services or rides.'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
  });
}
