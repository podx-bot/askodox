import 'package:podx/config/localization/askodox_language_catalog.dart';
import 'package:podx/core/providers/app_settings_provider.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          supportedLocales: AskodoxLanguageCatalog.all
              .map((language) => language.locale)
              .toList(growable: false),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Home keeps one AI-first ask entry point and minimal navigation',
      (tester) async {
    await pumpHome(tester);

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxImageButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPlusButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSendButton')), findsOneWidget);

    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Continue your conversations'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);
  });

  testWidgets('Telugu Home remains readable and keeps the same AI-first hierarchy',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHome(tester, locale: const Locale('te'));

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.text('ప్రస్తుతం జరుగుతున్నవి'), findsOneWidget);
    expect(find.text('మీ సంభాషణలను కొనసాగించండి'), findsOneWidget);
    expect(find.text('చాట్స్'), findsOneWidget);
    expect(find.text('అడగండి'), findsOneWidget);
    expect(find.text('యాక్టివిటీ'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Home language picker exposes catalog languages beyond legacy four',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('askodoxLanguageButton')));
    await tester.pumpAndSettle();

    expect(find.text('ASKODOX Language'), findsOneWidget);
    expect(find.text('Tamil'), findsOneWidget);
    expect(find.text('Bengali'), findsOneWidget);
    expect(find.text('Kannada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil Home selection persists while untranslated Home copy falls back safely',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('askodoxLanguageButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamil'));
    await tester.pumpAndSettle();
    await tester.pump();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('askodox.locale'), 'ta');
    expect(find.text('Tamil'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Continue your conversations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('localized greeting helper returns Telugu greeting without fallback', () {
    expect(askodoxGreetingForHour(9, 'te'), 'శుభోదయం 👋');
    expect(askodoxGreetingForHour(18, 'te'), 'శుభ సాయంత్రం 👋');
  });
}
