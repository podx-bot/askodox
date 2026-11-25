import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide/guide_switch.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('owner 2026-11-23: each auto walkthrough exists, is hidden from the list and its tour stops move on with Next', () {
    expect(askodoxAutoGuideRoutes['/onboarding'], 'signin');
    expect(askodoxAutoGuideRoutes['/'], 'home_tour');
    // Owner 2026-11-25: tours of Live Work, Money, the 3-step bill and the baaki page (route patterns with an id).
    expect(askodoxAutoGuideIdFor('/work'), 'live_work_tour');
    expect(askodoxAutoGuideIdFor('/money-home'), 'money_tour');
    expect(askodoxAutoGuideIdFor('/me/business/b1/bill'), 'bill_tour');
    expect(askodoxAutoGuideIdFor('/biz/b1/money/dues'), 'dues_tour');
    expect(askodoxAutoGuideIdFor('/biz/b1/money'), isNull);
    expect(askodoxAutoGuideIdFor('/me/business//bill'), isNull);
    for (final id in askodoxAutoGuideRoutes.values) {
      final flow = askodoxGuideById(id);
      expect(flow, isNotNull, reason: id);
      expect(flow!.listed, isFalse);
      expect(flow.steps, isNotEmpty);
    }
    final tour = askodoxGuideById('home_tour')!;
    expect(tour.steps.every((s) => s.info), isTrue);
    expect(tour.steps.map((s) => s.target), containsAll(['askodoxComposerField', 'askodoxNavLiveWork', 'askodoxGuideSwitch']));
    final signin = askodoxGuideById('signin')!;
    expect(signin.steps.first.target, 'askodoxLanguageContinue');
    expect(signin.steps.map((s) => s.target), containsAll(['mobile-input', 'askodoxSendOtp', 'otp-input', 'askodoxFinishSignUp']));
    expect(askodoxGuideIdle, const Duration(seconds: 5));
  });

  test('banner words say on / off in Telugu and English', () {
    expect(askodoxGuideBannerText(true, true), contains('గైడ్ ఆన్'));
    expect(askodoxGuideBannerText(false, true), contains('గైడ్ ఆఫ్'));
    expect(askodoxGuideBannerText(true, false), startsWith('Guide on'));
  });

  testWidgets('the switch is OFF by default, one tap turns it ON (saved) and shows the short banner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: AskodoxGuideChip()))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxGuideSwitchOff')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxGuideSwitch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('askodoxGuideSwitchOn')), findsOneWidget);
    expect(find.byKey(const Key('askodoxGuideBannerOn')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(askodoxGuideOnPrefsKey), isTrue);
    await tester.tap(find.byKey(const Key('askodoxGuideSwitch')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxGuideSwitchOff')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the intro card never shows in tests (only the real app turns it on)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Consumer(builder: (context, ref, _) {
        captured = ref;
        return const Scaffold(body: SizedBox());
      })),
    ));
    final ctx = tester.element(find.byType(Scaffold));
    expect(await askodoxGuideIntroOnce(ctx, captured), isFalse);
    expect(find.byKey(const Key('askodoxGuideIntro')), findsNothing);
  });
}
