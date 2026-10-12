import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/domain/result_board_tabs.dart';
import 'package:podx/features/home/presentation/attachment_menu.dart';
import 'package:podx/features/home/presentation/result_board_tab_row.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/shared/widgets/header_menu.dart';

/// Navigator UX: compact Result Board tabs, the ONE "+" attachment control
/// and the header Menu / Screen Guide. Universal: rows from several domains
/// (product, service, job, video) go through the same tabs.
void main() {
  const shop = UniversalMatch(id: 'p1', title: 'Phone shop', segment: 'nearby_external', source: 'external',
      destinationUrl: 'https://maps.example/p1', ratingAverage: 4.3, reviewCount: 120);
  const used = UniversalMatch(id: 'u1', title: 'Used fridge', segment: 'used', source: 'local');
  const online = UniversalMatch(id: 'o1', title: 'Online store', source: 'online',
      destinationUrl: 'https://store.example/x', offerPrice: 9999, offerTitle: 'Bank offer');
  const job = UniversalMatch(id: 'j1', title: 'Driver job', segment: 'jobs', source: 'online',
      destinationUrl: 'https://jobs.example/1');
  const plumber = UniversalMatch(id: 'pl', title: 'Plumber', source: 'interest', ratingAverage: 4.8, reviewCount: 9);
  const video = UniversalMatch(id: 'v1', title: 'Review video', source: 'video', destinationUrl: 'https://y/v');
  const unrated = UniversalMatch(id: 'x', title: 'No reviews', source: 'online',
      destinationUrl: 'https://s/x', ratingAverage: 4.9, reviewCount: 0);
  final all = [shop, used, online, job, plumber, video, unrated];

  group('Result Board tabs (views of one deck, never new searches)', () {
    test('every tab maps rows from any category', () {
      List<String> ids(AskodoxBoardTab t) => askodoxBoardTabRows(t, all).map((m) => m.id).toList();
      expect(ids(AskodoxBoardTab.all), ['p1', 'u1', 'o1', 'j1', 'pl', 'v1', 'x']);
      expect(ids(AskodoxBoardTab.local), containsAll(['p1', 'u1', 'pl']));
      expect(ids(AskodoxBoardTab.online), containsAll(['o1', 'j1', 'x']));
      expect(ids(AskodoxBoardTab.videos), ['v1']);
      expect(ids(AskodoxBoardTab.deals), ['o1'], reason: 'only rows with a real offer from their source');
    });

    test('Reviews: only grounded ratings (rating AND review count), best first', () {
      expect(askodoxBoardTabRows(AskodoxBoardTab.reviews, all).map((m) => m.id), ['pl', 'p1']);
      expect(askodoxHasGroundedReviews(unrated), isFalse, reason: 'a rating without reviews is never shown');
    });

    test('counts and honest empty states', () {
      final counts = askodoxBoardTabCounts([job]);
      expect(counts[AskodoxBoardTab.local], 0);
      expect(counts[AskodoxBoardTab.online], 1);
      expect(askodoxBoardTabEmptyText(AskodoxBoardTab.reviews, 'en'), contains('never guessed'));
      expect(askodoxBoardTabEmptyText(AskodoxBoardTab.local, 'te'), isNotEmpty);
    });

    test('a narrowed tab keeps the failure / source notices of the deck', () {
      final results = AskodoxChatResults(matches: all, searched: true, sourceStatus: const {'online': 'quota_exhausted'});
      final narrowed = askodoxResultsForTab(results, AskodoxBoardTab.videos);
      expect(narrowed.matches.map((m) => m.id), ['v1']);
      expect(narrowed.sourceStatus, results.sourceStatus);
      expect(identical(askodoxResultsForTab(results, AskodoxBoardTab.all), results), isTrue);
    });

    testWidgets('ONE row: Result Board | Local | Online | Deals | Reviews | Videos + Expand + Minimize', (tester) async {
      AskodoxBoardTab? picked;
      var minimized = false, expanded = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AskodoxResultBoardTabRow(
            selected: AskodoxBoardTab.all,
            counts: askodoxBoardTabCounts(all),
            lang: 'en',
            onSelect: (t) => picked = t,
            onMinimize: () => minimized = true,
            onExpand: () => expanded = true,
          ),
        ),
      ));
      for (final tab in AskodoxBoardTab.values) {
        expect(find.byKey(ValueKey('askodoxBoardTab-${tab.name}')), findsOneWidget);
      }
      expect(find.text('Result Board'), findsOneWidget);
      // The tabs scroll sideways (a phone shows a few at a time).
      await tester.drag(find.byKey(const Key('askodoxResultBoardTabs')), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Videos 1'));
      await tester.pumpAndSettle();
      expect(picked, AskodoxBoardTab.videos);
      await tester.tap(find.byKey(const Key('askodoxResultBoardMinimize')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxResultBoardMega')));
      await tester.pumpAndSettle();
      expect(minimized, isTrue);
      expect(expanded, isTrue);
    });
  });

  testWidgets('ONE "+" opens Camera / Photos / Videos / Files and hands the choice to the picker', (tester) async {
    final picks = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: AskodoxAttachButton(lang: 'te', onPick: picks.add))),
    ));
    expect(find.byKey(const Key('askodoxAttachButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAttachButton')));
    await tester.pumpAndSettle();
    for (final c in AskodoxAttachButton.choices) {
      expect(find.byKey(ValueKey('askodoxAttachChoice-$c')), findsOneWidget);
    }
    expect(find.text('కెమెరా'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxAttachChoice-video')));
    await tester.pumpAndSettle();
    expect(picks, ['video']);
  });

  testWidgets('header Menu lists existing places only; Screen Guide offers the in-app walkthroughs', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [AskodoxHeaderMenuButton(te: false), AskodoxHeaderGuideButton(te: false)]),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('askodoxHeaderMenu')));
    await tester.pumpAndSettle();
    for (final key in ['business', 'listings', 'enquiries', 'roles']) {
      expect(find.byKey(ValueKey('askodoxMenu-$key')), findsOneWidget);
    }
    for (final key in ['studio_videos', 'studio_creations', 'memory']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('askodoxMenu-$key')), 120,
          scrollable: find.byType(Scrollable).last);
      expect(find.byKey(ValueKey('askodoxMenu-$key')), findsOneWidget);
    }
    expect(find.byType(Drawer), findsNothing, reason: 'the menu is a sheet, never a drawer');
    expect(askodoxHeaderMenuEntries.map((e) => e.route).toSet().length, askodoxHeaderMenuEntries.length,
        reason: 'no duplicate entry points');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxHeaderScreenGuide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxGuideStart-upload_video')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHeaderGuideOtherApps')), findsOneWidget);
  });

  group('Result Board attribute chips (seller-given details, views of the deck)', () {
    const a = UniversalMatch(id: '1', title: 'Shoe A', source: 'local', attributes: {'size': '9', 'colour': 'Black'});
    const b = UniversalMatch(id: '2', title: 'Shoe B', source: 'local', attributes: {'size': '10', 'colour': 'Black'});
    const c = UniversalMatch(id: '3', title: 'Shoe C', source: 'local', attributes: {'size': '9', 'payment': 'Cash, UPI'});
    const web = UniversalMatch(id: 'w', title: 'Online shoe', source: 'online', destinationUrl: 'https://s/x');

    test('chips only from values the rows carry; multi values split; most common first', () {
      final chips = askodoxAttributeChips([a, b, c, web]);
      expect(chips.first.id, 'size=9');
      expect(chips.first.count, 2);
      expect(chips.map((c) => c.id), containsAll(['size=10', 'colour=Black', 'payment=Cash', 'payment=UPI']));
      expect(chips.first.label, 'Size: 9');
      expect(askodoxAttributeChips([web]), isEmpty, reason: 'no seller details -> no chips (nothing invented)');
      expect(askodoxAttributeChips([a, a]), isEmpty, reason: 'a value every row shares filters nothing');
    });

    test('filtering keeps rows carrying EVERY chosen detail and the deck notices', () {
      expect(askodoxFilterByAttributes([a, b, c, web], {'size=9'}).map((m) => m.id), ['1', '3']);
      expect(askodoxFilterByAttributes([a, b, c, web], {'size=9', 'colour=Black'}).map((m) => m.id), ['1']);
      expect(askodoxFilterByAttributes([a, b, c, web], {'payment=UPI'}).map((m) => m.id), ['3']);
      expect(askodoxFilterByAttributes([a, b], const {}).length, 2);
      final results = AskodoxChatResults(matches: [a, b, c], searched: true, sourceStatus: const {'online': 'error'});
      final narrowed = askodoxResultsForAttributes(results, {'size=10'});
      expect(narrowed.matches.single.id, '2');
      expect(narrowed.sourceStatus, results.sourceStatus);
      expect(UniversalMatch.fromJson({'id': 'r', 'title': 'x', 'attributes': {'size': '9', 'note': ''}}).attributes,
          {'size': '9'});
    });
  });
}
