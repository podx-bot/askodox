// App-level smoke test for the real ASKODOX app (package `podx`, root widget
// `PodxApp`). Keep this file: CI's `flutter create` step writes Flutter's
// counter-app template (package:askodox / MyApp) here whenever it is missing,
// which does not compile against this project.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/app.dart';
import 'package:podx/l10n_generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('UI locale falls back to a supported language', () {
    const supported = AppLocalizations.supportedLocales;
    expect(askodoxUiLocale(const Locale('te', 'IN'), supported).languageCode,
        'te');
    expect(askodoxUiLocale(const Locale('xx'), supported).languageCode, 'en');
    expect(askodoxUiLocale(null, supported), supported.first);
  });

  testWidgets('PodxApp starts without errors', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BuildContext? readyContext;

    await tester.pumpWidget(
      ProviderScope(
        child: PodxApp(onReady: (context) => readyContext = context),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PodxApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(readyContext, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
