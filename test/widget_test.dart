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
  testWidgets('renders ASKODOX AI-first home structure', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen()));
    await tester.pump();

    expect(find.text('ASKODOX AI', findRichText: true), findsOneWidget);
    expect(find.text('Ask anything. Get matched, compared, done.'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Explore more on ASKODOX'), findsOneWidget);
  });

  testWidgets('renders universal ASKODOX deal workspace', (tester) async {
    await tester.pumpWidget(_screen(const SearchScreen()));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.text('Explore ASKODOX'), findsOneWidget);
    expect(find.textContaining('same AI Deal Brain'), findsOneWidget);
    expect(find.text('Buy & Sell'), findsOneWidget);

    final askNaturally = find.text('Ask ASKODOX naturally');
    await tester.scrollUntilVisible(
      askNaturally,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(askNaturally, findsOneWidget);
  });
}
