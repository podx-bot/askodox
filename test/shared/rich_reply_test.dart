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
}
