import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/rich_reply.dart';

Future<void> _pump(WidgetTester tester, String text) => tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: AskodoxRichReply(text, style: const TextStyle(fontSize: 14))))));

String _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  testWidgets('plain replies stay ONE plain Text (unchanged look)', (tester) async {
    await _pump(tester, 'Hello! How can I help?');
    expect(find.byKey(const Key('askodoxRichReply')), findsNothing);
    expect(find.text('Hello! How can I help?'), findsOneWidget);
  });

  testWidgets('APK 1312: Telugu bold, bullets and numbers render -- no raw ** markers', (tester) async {
    const reply = '**ఖర్చు అంచనా** (సుమారు):\n'
        '- టైల్స్: **₹6,600–₹16,500**\n'
        '- కూలీ: ₹2,000\n\n'
        '1. కొలతలు తీసుకోండి\n'
        '2. 10% వృథా కలపండి';
    await _pump(tester, reply);
    final shown = _shown(tester);
    expect(shown, isNot(contains('**')));
    expect(shown, contains('ఖర్చు అంచనా'));
    expect(shown, contains('₹6,600–₹16,500'));
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('headings, tables and links (English)', (tester) async {
    const reply = '## Cost breakdown\n'
        '| Item | Estimate |\n|---|---|\n| Paint | ₹8,000 |\n| Labour | ₹12,000 |\n\n'
        'See [the guide](https://example.com/guide).';
    await _pump(tester, reply);
    final shown = _shown(tester);
    expect(shown, contains('Cost breakdown'));
    expect(shown, isNot(contains('##')));
    expect(shown, isNot(contains('|---')));
    expect(find.byType(Table), findsOneWidget);
    expect(shown, contains('the guide'));
    expect(shown, isNot(contains('https://example.com/guide')), reason: 'a link shows its label');
  });

  test('speech gets plain words, never markup', () {
    final plain = askodoxPlainReply('## Plan\n- **Paint**: ₹8,000\n- See [guide](https://x.example)');
    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('##')));
    expect(plain, isNot(contains('https://')));
    expect(plain, contains('Paint'));
    expect(plain, contains('guide'));
  });

  group('meaning colours (severity tags from the assistant, never keyword guesses)', () {
    testWidgets('ok / caution / risk lines are marked; untagged lines stay neutral; tags never shown', (tester) async {
      const reply = 'Here is what to check.\n'
          '- [ok] ISI-marked wiring is safe for home use.\n'
          '- [caution] Check the warranty card before paying.\n'
          '[risk] Do not pay the full amount in advance.\n\n'
          'Anything else?';
      await _pump(tester, reply);
      expect(find.byKey(const ValueKey('askodoxSeverity-ok')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxSeverity-caution')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxSeverity-risk')), findsOneWidget);
      final shown = _shown(tester);
      for (final tag in ['[ok]', '[caution]', '[risk]']) {
        expect(shown, isNot(contains(tag)));
      }
      expect(shown, contains('Do not pay the full amount'));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget, reason: 'meaning is not colour-only');
    });

    testWidgets('no tags -> no colour, even with warning-like words (meaning comes from the assistant)',
        (tester) async {
      await _pump(tester, '- Avoid cheap cables.\n- Danger zones are listed below.');
      for (final s in ['ok', 'caution', 'risk']) {
        expect(find.byKey(ValueKey('askodoxSeverity-$s')), findsNothing);
      }
    });

    testWidgets('Telugu reply: tagged line coloured, taller line height', (tester) async {
      await _pump(tester, '⚠️ ముందుగా పూర్తి డబ్బు చెల్లించకండి.\n\nమిగతావి సాధారణం.');
      expect(find.byKey(const ValueKey('askodoxSeverity-caution')), findsOneWidget);
      final tall = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.textSpan?.toPlainText() ?? t.data ?? '').contains('చెల్లించకండి'))
          .any((t) => (t.textSpan?.style?.height ?? t.style?.height ?? 0) >= 1.5);
      expect(tall, isTrue, reason: 'Telugu gets line height 1.5');
      expect(_shown(tester), isNot(contains('⚠️')));
    });

    test('dark and light palettes both exist for every severity', () {
      for (final s in AskodoxSeverity.values.where((s) => s != AskodoxSeverity.neutral)) {
        final light = askodoxSeverityStyle(s, Brightness.light);
        final dark = askodoxSeverityStyle(s, Brightness.dark);
        expect(light.fg, isNot(dark.fg));
        expect(light.label, isNotEmpty);
      }
    });

    test('speech and copy drop the tags', () {
      final plain = askodoxPlainReply('- [risk] Do not pay in advance.\n[ok] Good choice.\n✅ Done');
      expect(plain, isNot(contains('[risk]')));
      expect(plain, isNot(contains('[ok]')));
      expect(plain, isNot(contains('✅')));
      expect(plain, contains('Do not pay in advance.'));
      expect(plain, contains('Good choice.'));
    });
  });

  test('APK 1318: points glued into one line become separate points (Telugu screenshot)', () {
    const glued = 'సమాచారం ఇదిగోండి:\n'
        '- **కాక్రోచ్ పార్టీ అంటే ఏంటి?**: ఇది ఒక నిరసన కార్యక్రమం. - **ఢిల్లీలో ఏం జరిగింది?**: సమస్యలు. '
        '- **దీని ఉద్దేశం ఏంటి?**: దృష్టికి తీసుకురావడం.';
    final items = askodoxParseReply(glued).whereType<AskodoxListItem>().toList();
    expect(items, hasLength(3));
    expect(items[1].text, startsWith('**ఢిల్లీలో'));
    final numbered = askodoxParseReply('Options: 1. **Local** shop. 2. **Online** store.')
        .whereType<AskodoxListItem>()
        .toList();
    expect(numbered.map((i) => i.number), ['1', '2']);
    expect(askodoxSplitGluedPoints('Price is 10 - 20 rupees'), 'Price is 10 - 20 rupees',
        reason: 'an ordinary dash is not a point');
  });

  testWidgets('points and paragraphs have a clear gap between them', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AskodoxRichReply('Intro line.\n\n- **One**: a\n- **Two**: b', style: TextStyle()))));
    final one = tester.getRect(find.textContaining('One'));
    final two = tester.getRect(find.textContaining('Two'));
    expect(two.top - one.bottom, greaterThanOrEqualTo(10));
  });
}
