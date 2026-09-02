import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/presentation/search_screen.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:podx/generated/l10n/app_localizations.dart';

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
  testWidgets('renders ASKODOX bright AI-first home structure', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen()));
    await tester.pump();

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Good evening 👋'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSendButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxLanguageButton')), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);

    // Home stays AI-first: capability/category tiles must not compete with the
    // natural-language entry point.
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

  testWidgets('renders Telugu AI-first home without layout regressions', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen(), locale: const Locale('te')));
    await tester.pump();

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('శుభ సాయంత్రం 👋'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
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
}
