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

  testWidgets('Home opens on locked ASKODOX home, not a second chat page', (tester) async {
    await pumpHome(tester);

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxLanguageButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHomeOrb')), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Telugu Home keeps locked home hierarchy', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'askodox.locale': 'te'});
    await pumpHome(tester);
    await tester.pump();

    expect(find.text('ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxLanguageButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHomeOrb')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home language picker exposes catalog languages beyond legacy four', (tester) async {
    await pumpHome(tester);
    await openLanguagePicker(tester);

    expect(find.text('ASKODOX Language'), findsOneWidget);
    await revealLanguage(tester, 'Bengali');
    await revealLanguage(tester, 'Kannada');
    await revealLanguage(tester, 'Tamil');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil Home selection persists with safe fallback', (tester) async {
    await pumpHome(tester);
    await openLanguagePicker(tester);
    await revealLanguage(tester, 'Tamil');
    await tester.tap(find.text('Tamil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('askodox.locale'), 'ta');
    expect(find.text('Tamil'), findsOneWidget);
    expect(find.text('ASKODOX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('localized greeting helper returns Telugu greeting without fallback', () {
    expect(askodoxGreetingForHour(9, 'te'), 'శుభోదయం 👋');
    expect(askodoxGreetingForHour(18, 'te'), 'శుభ సాయంత్రం 👋');
  });
}
