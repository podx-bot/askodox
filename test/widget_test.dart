import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/presentation/search_screen.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:podx/generated/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _screen(Widget child, {Locale? locale}) => ProviderScope(
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );

void main() {
  test('returns localized ASKODOX greetings for each daypart', () {
    expect(askodoxGreetingForHour(9, 'en'), 'Good morning 👋');
    expect(askodoxGreetingForHour(13, 'en'), 'Good afternoon 👋');
    expect(askodoxGreetingForHour(18, 'en'), 'Good evening 👋');
    expect(askodoxGreetingForHour(22, 'en'), 'Good night 👋');
    expect(askodoxGreetingForHour(9, 'te'), 'శుభోదయం 👋');
    expect(askodoxGreetingForHour(18, 'hi'), 'शुभ संध्या 👋');
    expect(askodoxGreetingForHour(22, 'or'), 'ଶୁଭ ରାତ୍ରି 👋');
  });

  testWidgets('renders ASKODOX bright AI-first home structure', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen()));
    await tester.pump();

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text(askodoxGreetingForHour(DateTime.now().hour, 'en')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPlusButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxImageButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSendButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxLanguageButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHomeOrb')), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);

    expect(find.text('Buy & Local'), findsNothing);
    expect(find.text('Products nearby'), findsNothing);
    expect(find.text('Jobs'), findsNothing);
    expect(find.text('Rides'), findsNothing);
    expect(find.text('Business'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Continue your conversations'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Continue your conversations'), findsOneWidget);

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);
  });

  testWidgets('opens multimodal actions from ASKODOX plus button', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxPlusButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add to your request'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPlusPhotosAction')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPlusVoiceAction')), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
    expect(find.text('Use voice'), findsOneWidget);
  });

  testWidgets('renders Telugu AI-first home without layout regressions', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen(), locale: const Locale('te')));
    await tester.pump();

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text(askodoxGreetingForHour(DateTime.now().hour, 'te')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPlusButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxImageButton')), findsOneWidget);
    expect(find.text('ప్రస్తుతం జరుగుతున్నవి'), findsOneWidget);
    expect(find.text('యాక్టివిటీ'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('మీ సంభాషణలను కొనసాగించండి'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('మీ సంభాషణలను కొనసాగించండి'), findsOneWidget);
    expect(find.text('చాట్స్'), findsOneWidget);
    expect(find.text('అడగండి'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders conversation-first ASKODOX workspace', (tester) async {
    await tester.pumpWidget(_screen(const SearchScreen()));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Tell me what you need naturally'), findsOneWidget);
    expect(find.textContaining('No forms.'), findsOneWidget);
    expect(find.text('I want chicken nearby'), findsOneWidget);
    expect(find.text('I need a job'), findsOneWidget);
    expect(find.text('I need a ride to Vijayawada'), findsOneWidget);
  });

  testWidgets('restores visible ASKODOX conversation turns after recreation', (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.active_universal_deal.v1': jsonEncode({
        'deal': {
          'rawText': 'I want chicken nearby',
          'intent': 'buy',
          'partyA': {'side': 'demand', 'role': 'buyer', 'action': 'buy'},
          'partyB': {'side': 'supply', 'role': 'seller', 'action': 'sell'},
          'subject': 'chicken',
          'category': 'food',
          'location': {'label': 'Vijayawada', 'radiusKm': 10},
          'dynamicFields': <String, Object?>{},
          'status': 'collecting',
        },
        'quotes': <Object?>[],
      }),
      'askodox.active_conversation_turns.v1': jsonEncode([
        {'text': '5 kg', 'isUser': true},
        {'text': 'Do you want pickup or delivery?', 'isUser': false},
      ]),
    });

    await tester.pumpWidget(_screen(const SearchScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('I want chicken nearby'), findsOneWidget);
    expect(find.text('5 kg'), findsOneWidget);
    expect(find.text('Do you want pickup or delivery?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
