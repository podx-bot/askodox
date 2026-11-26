import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/ui/ui_switches.dart';
import 'package:podx/features/guide/ask_everywhere.dart';
import 'package:podx/features/guide/guide_sheet.dart';
import 'package:podx/features/guide/guide_switch.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/home/presentation/question_mic.dart';
import 'package:podx/features/steps/presentation/step_kit.dart';
import 'package:podx/shared/widgets/askodox_fill_bar.dart';

final _spoken = <String>[];
final _asked = <String>[];
final _quiet = [
  askodoxGuideSpeakerProvider.overrideWithValue((text, language) async => _spoken.add(text)),
  askodoxGuideAnswererProvider.overrideWithValue((q, screen, steps, guides, locale) async {
    _asked.add('$screen|$q');
    return q.contains('nothing') ? '' : 'Tap Add, type the name and the price.';
  }),
];

void main() {
  setUp(() {
    _spoken.clear();
    _asked.clear();
    askodoxApplyOwnerUi();
  });
  tearDown(() {
    askodoxPageMicsOn = true;
    askodoxGuideSwitchOn = true;
    askodoxAskEverywhereOn = false;
  });

  test('the Ask button shows on every page outside the bottom bar, never on private pages', () {
    expect(askodoxAskShownOn('/pos/:id/items', '/pos/b1/items'), isTrue);
    expect(askodoxAskShownOn('/me/bills', '/me/bills'), isTrue);
    for (final root in askodoxAskShellRoots) {
      expect(askodoxAskShownOn(root, root), isFalse, reason: root);
    }
    expect(askodoxAskShownOn('/onboarding', '/onboarding'), isFalse);
    expect(askodoxAskShownOn('/pos/:id/items', '/pos/b1/items', keyboard: 280), isFalse);
    expect(askodoxAskShownOn('/pos/:id/items', '/pos/b1/items', guiding: true), isFalse);
    askodoxAskEverywhereOn = false;
    expect(askodoxAskShownOn('/pos/:id/items', '/pos/b1/items'), isFalse);
  });

  testWidgets('Ask answers on the same page; the chat opens only by the person\'s own tap', (tester) async {
    final router = GoRouter(initialLocation: '/pos/b1/items', routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/pos/:id/items', builder: (_, __) => const Scaffold(body: Text('ITEMS'))),
    ]);
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: _quiet,
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AskodoxAskLayer(router: router, child: child!),
        );
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAskHere')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAskSheet')), findsOneWidget);
    // The sheet keeps its own mic even though page mics are off.
    expect(find.byKey(const Key('askodoxQuestionMic')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxAskBox')), 'how do I add an item');
    await tester.tap(find.byKey(const Key('askodoxAskSend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAskAnswer')), findsOneWidget);
    expect(find.text('Tap Add, type the name and the price.'), findsOneWidget);
    expect(_spoken, ['Tap Add, type the name and the price.']);
    expect(_asked.single, endsWith('|how do I add an item'));
    expect(find.text('ITEMS'), findsOneWidget); // still on the page
    expect(container.read(askodoxChatRequestProvider), isNull);

    await tester.enterText(find.byKey(const Key('askodoxAskBox')), 'nothing here');
    await tester.tap(find.byKey(const Key('askodoxAskSend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAskNone')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAskToChat')));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.prompt, 'nothing here');
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskHere')), findsNothing); // Home has the bottom bar's Ask
  });

  testWidgets('one switch takes the mics off every page and the guide chip away', (tester) async {
    Widget page() => ProviderScope(
          overrides: _quiet,
          child: MaterialApp(
            home: Scaffold(
              body: Column(children: [
                const AskodoxGuideChip(),
                AskodoxQuestionMic(onText: (_) {}),
                AskodoxFillBar(fields: () => const [], onFilled: () {}),
              ]),
              bottomNavigationBar: AskodoxStepBottom(label: 'Next', onPressed: () {}, onSpoken: (_) {}),
            ),
          ),
        );
    await tester.pumpWidget(page());
    await tester.pump();
    expect(find.byKey(const Key('askodoxGuideSwitch')), findsNothing);
    expect(find.byKey(const Key('askodoxQuestionMic')), findsNothing);
    expect(find.byKey(const Key('askodoxStepMic')), findsNothing);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    expect(find.text('Next'), findsOneWidget);
  });
}
