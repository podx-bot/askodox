import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/guide/in_app_guide.dart';

GoRouter _router() => GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
                body: Column(children: [
                  TextButton(key: const Key('askodoxLocationChip'), onPressed: () {}, child: const Text('Uyyuru')),
                  const Spacer(),
                  TextButton(
                      key: const Key('askodoxNavProfile'), onPressed: () => context.go('/profile'), child: const Text('Profile')),
                ]),
              )),
      GoRoute(
          path: '/profile',
          builder: (context, _) => Scaffold(
                body: ListView(children: [
                  ListTile(
                      key: const ValueKey('profile-feedback'),
                      title: const Text('Report a problem'),
                      onTap: () => context.push('/beta-feedback')),
                ]),
              )),
      GoRoute(
          path: '/beta-feedback',
          builder: (context, _) => Scaffold(
                body: Column(children: [
                  const TextField(key: Key('askodoxFeedbackDescription')),
                  FilledButton(key: const Key('askodoxFeedbackSubmit'), onPressed: () {}, child: const Text('Submit')),
                ]),
              )),
      GoRoute(path: '/onboarding', builder: (context, _) => const Scaffold(body: Text('OTP'))),
    ]);

Future<(GoRouter, ProviderContainer, List<String>)> _pump(WidgetTester tester) async {
  final router = _router();
  final spoken = <String>[];
  final container = ProviderContainer(overrides: [
    askodoxGuideSpeakerProvider.overrideWithValue((text, language) async => spoken.add(text)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
          routerConfig: router, builder: (context, child) => AskodoxGuideOverlay(router: router, child: child!))));
  await tester.pumpAndSettle();
  return (router, container, spoken);
}

Future<void> _tick(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _text(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('askodoxGuideText'))).data!;

void main() {
  test('how-to questions find a guide; plain requests do not', () {
    expect(askodoxGuideFor('How do I upload a video?')?.id, 'upload_video');
    expect(askodoxGuideFor('వీడియో అప్‌లోడ్ ఎలా చేయాలి')?.id, 'upload_video');
    expect(askodoxGuideFor('show me how to send a parcel')?.id, 'send_parcel');
    expect(askodoxGuideFor('send a parcel from Benz Circle to Gannavaram'), isNull);
    expect(askodoxGuideFor('how can I become a delivery partner')?.id, 'become_partner');
    expect(askodoxGuideFlows.map((f) => f.id), containsAll(['upload_video', 'add_listing', 'change_location',
        'accept_order', 'send_parcel', 'become_partner', 'report_problem']));
    expect(askodoxGuideIsPrivate('/onboarding?signin=1'), isTrue);
    expect(askodoxGuideIsPrivate('/profile'), isFalse);
  });

  testWidgets('points at the real button, waits for the user tap, speaks, finishes', (tester) async {
    final (_, container, spoken) = await _pump(tester);
    container.read(askodoxGuideProvider.notifier).start(askodoxGuideById('report_problem')!);
    await _tick(tester);
    expect(_text(tester), 'Tap Profile at the bottom.');
    expect(find.byKey(const Key('askodoxGuideSpotlight')), findsOneWidget);
    expect(find.byKey(const Key('askodoxGuideArrow')), findsOneWidget);
    expect(spoken.last, 'Tap Profile at the bottom.');
    await tester.tap(find.byKey(const Key('askodoxNavProfile')));
    await _tick(tester);
    await _tick(tester);
    expect(_text(tester), 'Tap "Report a problem / Send feedback".');
    await tester.tap(find.byKey(const ValueKey('profile-feedback')));
    await _tick(tester);
    await _tick(tester);
    expect(_text(tester), startsWith('Describe what happened'));
    await tester.tap(find.byKey(const Key('askodoxFeedbackDescription')));
    await _tick(tester);
    expect(_text(tester), 'Tap "Submit feedback".');
    await tester.tap(find.byKey(const Key('askodoxFeedbackSubmit')));
    await _tick(tester);
    expect(_text(tester), startsWith('Done'));
    await tester.pump(const Duration(seconds: 4));
    expect(container.read(askodoxGuideProvider), isNull);
  });

  testWidgets('skips steps already done; recovers from a wrong screen; stop', (tester) async {
    final (router, container, _) = await _pump(tester);
    router.go('/profile');
    await _tick(tester);
    container.read(askodoxGuideProvider.notifier).start(askodoxGuideById('report_problem')!);
    await _tick(tester);
    expect(_text(tester), 'Tap "Report a problem / Send feedback".', reason: 'already on Profile: step 1 skipped');
    container.read(askodoxGuideProvider.notifier).start(askodoxGuideById('change_location')!);
    await _tick(tester, 10);
    expect(_text(tester), 'That button is not on this screen.');
    await tester.tap(find.byKey(const Key('askodoxGuideTakeMe')));
    await _tick(tester);
    await _tick(tester);
    expect(_text(tester), 'Tap your place at the top.');
    await tester.tap(find.byKey(const Key('askodoxGuideStop')));
    await tester.pump();
    expect(container.read(askodoxGuideProvider), isNull);
    expect(find.byKey(const Key('askodoxGuideText')), findsNothing);
  });

  testWidgets('pauses on private screens (OTP) and reads nothing there', (tester) async {
    final (router, container, spoken) = await _pump(tester);
    container.read(askodoxGuideProvider.notifier).start(askodoxGuideById('upload_video')!);
    await _tick(tester);
    final before = spoken.length;
    router.push('/onboarding?signin=1');
    await _tick(tester);
    await _tick(tester);
    expect(find.byKey(const Key('askodoxGuidePaused')), findsOneWidget);
    expect(find.byKey(const Key('askodoxGuideText')), findsNothing);
    expect(spoken.length, before);
    router.pop();
    await _tick(tester);
    await _tick(tester);
    expect(find.byKey(const Key('askodoxGuidePaused')), findsNothing);
  });
}
