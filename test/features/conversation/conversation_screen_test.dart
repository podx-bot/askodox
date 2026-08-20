import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/conversation/data/universal_conversation_client.dart';
import 'package:podx/features/conversation/presentation/conversation_screen.dart';
import 'package:podx/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('home ask opens the ASKODOX conversation surface', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('askodoxAskField')),
      'నాకు దగ్గరలో చికెన్ కావాలి',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('askodoxConversationList')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('askodoxUserMessage')),
        matching: find.text('నాకు దగ్గరలో చికెన్ కావాలి'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('askodoxConversationField')), findsOneWidget);
  });

  testWidgets('unconfigured conversation build fails safely in-app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          initialQuery: 'Find work',
          client: UniversalConversationClient(baseUrl: ''),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Find work'), findsOneWidget);
    expect(
      find.textContaining('conversation server is not configured'),
      findsOneWidget,
    );
  });
}
