import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openLanguagePicker(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('askodoxLanguageButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> revealLanguage(WidgetTester tester, String language) async {
    final finder = find.text(language);
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  Future<void> revealBottomNavigation(WidgetTester tester) async {
    final navigation = find.byType(NavigationBar);
    for (var i = 0; i < 12 && navigation.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(navigation, findsOneWidget);
  }

  List<String> navigationLabels(WidgetTester tester) => tester
      .widgetList<NavigationDestination>(find.byType(NavigationDestination))
      .map((destination) => destination.label)
      .toList(growable: false);

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
    await revealBottomNavigation(tester);
    expect(navigationLabels(tester), ['Chats', 'Ask', 'Activity']);
  });

  testWidgets('Telugu Home remains readable and keeps the same AI-first hierarchy',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.locale': 'te',
    });

    await pumpHome(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.text('ప్రస్తుతం జరుగుతున్నవి'), findsOneWidget);
    expect(find.text('మీ సంభాషణలను కొనసాగించండి'), findsOneWidget);
    await revealBottomNavigation(tester);
    expect(navigationLabels(tester), ['చాట్స్', 'అడగండి', 'యాక్టివిటీ']);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Home language picker exposes catalog languages beyond legacy four',
      (tester) async {
    await pumpHome(tester);
    await openLanguagePicker(tester);

    expect(find.text('ASKODOX Language'), findsOneWidget);
    await revealLanguage(tester, 'Bengali');
    await revealLanguage(tester, 'Kannada');
    await revealLanguage(tester, 'Tamil');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil Home selection persists while untranslated Home copy falls back safely',
      (tester) async {
    await pumpHome(tester);
    await openLanguagePicker(tester);
    await revealLanguage(tester, 'Tamil');
    await tester.tap(find.text('Tamil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
