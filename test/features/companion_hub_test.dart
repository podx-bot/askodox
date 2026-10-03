import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/companion/askodox_companion.dart';
import 'package:podx/features/companion/companion_hub.dart';
import 'package:podx/features/companion/companion_human2d.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AskodoxCompanionPerformance.reset();
  });

  Widget host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  group('companion hub (contextual actions, not permanent)', () {
    testWidgets('shows every action once and reports taps; the scrim closes it', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final chosen = <AskodoxHubAction>[];
      var closed = 0;
      await tester.pumpWidget(host(AskodoxCompanionHub(lang: 'en', onAction: chosen.add, onClose: () => closed++)));
      for (final a in AskodoxHubAction.values) {
        expect(find.byKey(ValueKey('askodoxHubAction-${a.name}')), findsOneWidget);
      }
      expect(find.text('Voice'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('askodoxHubAction-camera')));
      await tester.tap(find.byKey(const ValueKey('askodoxHubAction-files')));
      expect(chosen, [AskodoxHubAction.camera, AskodoxHubAction.files]);
      await tester.tapAt(const Offset(20, 20));
      expect(closed, 1);
    });

    testWidgets('labels follow the app language (Telugu)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(AskodoxCompanionHub(lang: 'te', onAction: (_) {}, onClose: () {})));
      expect(find.text('మాట్లాడండి'), findsOneWidget);
      expect(find.text('ఫైల్స్'), findsOneWidget);
    });
  });

  group('in-app floating companion', () {
    test('drop snaps to the nearest side and the position survives a restart', () async {
      final first = AskodoxInAppFloatController();
      await Future<void>.delayed(Duration.zero);
      first.setEnabled(true);
      first.dropAt(.3, .4);
      expect(first.state.x, 0);
      expect(first.state.y, .4);
      first.dropAt(.7, 2);
      expect(first.state.x, 1);
      expect(first.state.y, 1, reason: 'kept inside the usable area');
      await Future<void>.delayed(Duration.zero);

      final restarted = AskodoxInAppFloatController();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(restarted.state.enabled, isTrue);
      expect(restarted.state.x, 1);
      expect(restarted.state.y, 1);
    });

    testWidgets('hidden unless turned on; tap opens the compact panel with every action', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final chosen = <AskodoxHubAction>[];
      var asked = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskodoxInAppFloatingCompanion(lang: 'en', onAction: chosen.add, onAskAboutThis: () => asked++),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('askodoxFloatingCompanion')), findsNothing, reason: 'opt-in only');

      container.read(askodoxInAppFloatProvider.notifier).setEnabled(true);
      await tester.pump();
      expect(find.byKey(const Key('askodoxFloatingCompanion')), findsOneWidget);

      await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxFloatingPanel')), findsOneWidget);
      expect(find.byKey(const Key('askodoxFloatAskThis')), findsOneWidget);
      for (final a in AskodoxHubAction.values) {
        expect(find.byKey(ValueKey('askodoxFloatAction-${a.name}')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('askodoxFloatAction-photos')));
      await tester.pump();
      expect(chosen, [AskodoxHubAction.photos]);
      expect(find.byKey(const Key('askodoxFloatingPanel')), findsNothing, reason: 'an action closes the panel');

      await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('askodoxFloatAskThis')));
      await tester.pump();
      expect(asked, 1);

      await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('askodoxFloatMinimize')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxFloatingPanel')), findsNothing);
      expect(find.byKey(const Key('askodoxFloatingCompanion')), findsOneWidget, reason: 'minimize keeps the avatar');

      await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('askodoxFloatHide')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxFloatingCompanion')), findsNothing, reason: 'hide turns it off');
    });

    testWidgets('dragging moves it and releasing snaps it to an edge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: AskodoxInAppFloatingCompanion(lang: 'en', onAction: (_) {}))),
      ));
      container.read(askodoxInAppFloatProvider.notifier).setEnabled(true);
      await tester.pump();
      final before = tester.getCenter(find.byKey(const Key('askodoxFloatingCompanion')));
      expect(before.dx, greaterThan(180), reason: 'starts on the right edge');
      await tester.drag(find.byKey(const Key('askodoxFloatingCompanion')), const Offset(-250, -100));
      await tester.pump();
      final state = container.read(askodoxInAppFloatProvider);
      expect(state.x, 0, reason: 'released on the left half -> left edge');
      final after = tester.getCenter(find.byKey(const Key('askodoxFloatingCompanion')));
      expect(after.dx, lessThan(60));
      expect(after.dy, lessThan(before.dy));
    });

    testWidgets('while listening, a tap stops voice instead of opening the panel', (tester) async {
      final chosen = <AskodoxHubAction>[];
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: AskodoxInAppFloatingCompanion(lang: 'en', onAction: chosen.add))),
      ));
      container.read(askodoxInAppFloatProvider.notifier).setEnabled(true);
      container.read(askodoxCompanionLiveProvider.notifier).state =
          const AskodoxCompanionLive(mood: AskodoxCompanionMood.listening, listening: true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pump();
      expect(chosen, [AskodoxHubAction.voice]);
      expect(find.byKey(const Key('askodoxFloatingPanel')), findsNothing);
    });
  });

  group('sponsored / affiliate disclosure', () {
    test('organic rows carry no paid label; sponsored and affiliate rows do', () {
      const organic = UniversalMatch(id: '12', title: 'Local shop');
      const sponsored = UniversalMatch(id: 'sponsored-1', title: 'TV', sponsored: true, sponsoredLabel: 'Promoted');
      const affiliate = UniversalMatch(id: 'p-1', title: 'Store', affiliate: true, segment: 'partner');
      expect(organic.paidPlacementLabel, isNull);
      expect(sponsored.paidPlacementLabel, 'Promoted');
      expect(affiliate.paidPlacementLabel, 'Sponsored');
      expect(askodoxSegmentOf(sponsored), AskodoxResultSegment.sponsored);
      expect(askodoxSegmentOf(organic), isNot(AskodoxResultSegment.sponsored));
    });

    test('the sponsored flag survives History round-trips', () {
      final restored = UniversalMatch.fromJson(
          const UniversalMatch(id: 'sponsored-2', title: 'TV', sponsored: true, sponsoredLabel: 'Sponsored').toJson());
      expect(restored.sponsored, isTrue);
      expect(restored.paidPlacementLabel, 'Sponsored');
      expect(UniversalMatch.fromJson(const UniversalMatch(id: '3', title: 'x').toJson()).sponsored, isFalse);
    });

    test('sponsored gets its own section title, after organic ones', () {
      expect(askodoxSegmentTitle(AskodoxResultSegment.sponsored, telugu: false, hasLocal: true), 'Sponsored');
      expect(askodoxSegmentTitle(AskodoxResultSegment.sponsored, telugu: true, hasLocal: true, lang: 'te'),
          'స్పాన్సర్డ్');
      expect(AskodoxResultSegment.sponsored.index, greaterThan(AskodoxResultSegment.online.index));
      expect(AskodoxResultSegment.sponsored.index, greaterThan(AskodoxResultSegment.partner.index));
    });
  });

  group('one companion identity everywhere', () {
    test('every state resolves to a bundled photo of the same person', () {
      final files = {for (final n in AskodoxHuman2d.bundled) n: File('${AskodoxHuman2d.dir}/$n.jpg')};
      for (final entry in files.entries) {
        expect(entry.value.existsSync(), isTrue, reason: entry.key);
      }
      for (final mood in AskodoxCompanionMood.values) {
        final asset = AskodoxHuman2d.assetFor(mood);
        expect(File(asset).existsSync(), isTrue, reason: '$mood -> $asset');
        expect(asset.startsWith(AskodoxHuman2d.dir), isTrue, reason: 'no other face for $mood');
      }
      // Missing states fall back to the neutral photo (not another face).
      expect(AskodoxHuman2d.assetFor(AskodoxCompanionMood.speaking), '${AskodoxHuman2d.dir}/neutral.jpg');
      expect(AskodoxHuman2d.assetFor(AskodoxCompanionMood.listening), '${AskodoxHuman2d.dir}/listening.jpg');
      expect(AskodoxHuman2d.assetFor(AskodoxCompanionMood.thinking), '${AskodoxHuman2d.dir}/thinking.jpg');
    });

    testWidgets('chat stage, home, nav button and floating companion all render the same human', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(askodoxInAppFloatProvider.notifier).setEnabled(true);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: [
              const Column(children: [
                AskodoxCompanionBar(mood: AskodoxCompanionMood.idle, telugu: false), // chat stage
                AskodoxCompanion(key: Key('home'), size: 170), // Home
                AskodoxCompanion(key: Key('nav'), size: 54), // bottom navigation
              ]),
              Positioned.fill(child: AskodoxInAppFloatingCompanion(lang: 'en', onAction: (_) {})),
            ]),
          ),
        ),
      ));
      await tester.pump();
      final faces = tester.widgetList<AskodoxHuman2d>(find.byType(AskodoxHuman2d)).toList();
      expect(faces, hasLength(4));
      final assets = tester
          .widgetList<Image>(find.descendant(of: find.byType(AskodoxHuman2d), matching: find.byType(Image)))
          .map((i) => (i.image as AssetImage).assetName)
          .toSet();
      expect(assets, {'${AskodoxHuman2d.dir}/neutral.jpg'}, reason: 'one identity, one photo set');
      expect(find.byKey(const ValueKey('askodoxCompanionHuman3d')), findsNothing);
      expect(find.byKey(const ValueKey('askodoxCompanion3d')), findsNothing, reason: 'no robot substitute');
    });
  });

  group('floating companion: keyboard and navigation', () {
    testWidgets('stays above the keyboard and keeps its side after the screen is rebuilt', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(askodoxInAppFloatProvider.notifier)
        ..setEnabled(true)
        ..dropAt(0, 1); // left edge, lowest position
      Widget screen({double keyboard = 0}) => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(size: const Size(360, 780), viewInsets: EdgeInsets.only(bottom: keyboard)),
                child: Scaffold(body: AskodoxInAppFloatingCompanion(lang: 'en', onAction: (_) {})),
              ),
            ),
          );
      await tester.pumpWidget(screen());
      final noKeyboard = tester.getRect(find.byKey(const Key('askodoxFloatingCompanion')));
      await tester.pumpWidget(screen(keyboard: 300));
      final withKeyboard = tester.getRect(find.byKey(const Key('askodoxFloatingCompanion')));
      expect(withKeyboard.bottom, lessThanOrEqualTo(780 - 300), reason: 'never under the keyboard');
      expect(withKeyboard.top, lessThan(noKeyboard.top), reason: 'moves up with the keyboard');
      // Navigating away and back rebuilds the screen: same side, same height.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      final back = tester.getRect(find.byKey(const Key('askodoxFloatingCompanion')));
      expect(back.left, noKeyboard.left);
      expect(back.top, noKeyboard.top);
      expect(back.left, lessThan(40), reason: 'left edge kept');
    });
  });
}
