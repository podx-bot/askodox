import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/conversation/data/universal_conversation_client.dart';
import 'package:podx/features/conversation/presentation/conversation_screen.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home send opens the ASKODOX conversation surface',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('askodoxAskField')),
      'నాకు దగ్గరలో చికెన్ కావాలి',
    );
    await tester.tap(find.byKey(const Key('askodoxHomeSendButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

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

  testWidgets('conversation server settings button opens editable dialog',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          client: UniversalConversationClient(baseUrl: ''),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxServerSettings')));
    await tester.pumpAndSettle();

    expect(find.text('ASKODOX server'), findsOneWidget);
    expect(find.byKey(const Key('askodoxServerUrlField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxServerSave')), findsOneWidget);
  });

  testWidgets('conversation send button adds user message even offline',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          client: UniversalConversationClient(baseUrl: ''),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('askodoxConversationField')),
      'Find work nearby',
    );
    await tester.tap(find.byKey(const Key('askodoxConversationSend')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.descendant(
        of: find.byKey(const Key('askodoxUserMessage')),
        matching: find.text('Find work nearby'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('conversation server is not configured'),
      findsOneWidget,
    );
  });

  testWidgets('unconfigured conversation build fails safely in-app',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          initialQuery: 'Find work',
          client: UniversalConversationClient(baseUrl: ''),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Find work'), findsOneWidget);
    expect(
      find.textContaining('conversation server is not configured'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('askodoxServerSettings')), findsOneWidget);
  });
}
