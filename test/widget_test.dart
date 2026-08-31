import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/presentation/search_screen.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:podx/generated/l10n/app_localizations.dart';

Widget _screen(Widget child) => ProviderScope(
      child: MaterialApp(
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

    expect(find.text('ASKODOX AI'), findsOneWidget);
    expect(find.text('Hi! I’m ASKODOX AI'), findsOneWidget);
    expect(find.textContaining('Tell me what you need.'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxLanguageButton')), findsOneWidget);
    expect(find.text('Recent history'), findsOneWidget);
  });

  testWidgets('renders conversation-first ASKODOX workspace', (tester) async {
    await tester.pumpWidget(_screen(const SearchScreen()));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.textContaining('Just tell me naturally.'), findsOneWidget);
    expect(find.text('Chicken nearby'), findsOneWidget);
    expect(find.text('I need a job'), findsOneWidget);
    expect(find.text('Ride to Vijayawada'), findsOneWidget);
  });
}
