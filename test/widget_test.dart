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
  testWidgets('renders home screen structure', (tester) async {
    await tester.pumpWidget(_screen(const HomeScreen()));
    await tester.pump();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders catalog search structure', (tester) async {
    await tester.pumpWidget(_screen(const SearchScreen()));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });
}
