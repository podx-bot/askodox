import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/net/net_quality.dart';
import 'package:podx/features/home/domain/offline_questions.dart';
import 'package:podx/features/home/presentation/offline_ask_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Made-up names and amounts only (public repo).
Map<String, Object?> row(String id, int rupees, String at, {String dir = 'in', String party = '', String app = 'PhonePe', bool bank = false}) => {
      'local_id': id,
      'amount_paise': rupees * 100,
      'direction': dir,
      'detected_at': at,
      'source_label': app,
      'party': party,
      if (bank) 'bank_confirmed': true,
    };

void main() {
  final now = DateTime(2026, 11, 23, 16, 0); // a Monday
  String iso(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute).toIso8601String();

  final events = <Map<String, Object?>>[
    row('1', 1200, iso(23, 10, 15), party: 'Lakshmi Kirana', bank: true),
    row('2', 300, iso(23, 11, 0), party: 'Ravi'),
    row('3', 500, iso(23, 12, 30), party: 'Ravi', app: 'Google Pay', bank: true),
    row('4', 448, iso(23, 9, 0), dir: 'out', party: 'Recharge'),
    row('5', 900, iso(22, 18, 0), party: 'Suma', bank: true),
    row('6', 2500, iso(10, 9, 0), party: 'Old Customer', bank: true),
    {...row('7', 99999, iso(23, 13, 0)), 'test': true},
    {...row('8', 8551, iso(23, 13, 5)), 'excluded': true},
  ];

  group('owner 2026-11-23, Lite step 3: what the phone can answer with no net', () {
    test('time + money questions in Telugu, English and Hindi', () {
      expect(askodoxOfflineAsk('ఈరోజు ఎంత వచ్చింది?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false));
      expect(askodoxOfflineAsk('ఈ రోజు ఎంత డబ్బు వచ్చింది'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false));
      expect(askodoxOfflineAsk('నిన్న ఎంత వచ్చింది?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.yesterday, out: false));
      expect(askodoxOfflineAsk('ఈ వారం ఎంత వచ్చింది?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.week, out: false));
      expect(askodoxOfflineAsk('ఈ నెల మొత్తం payments ఎంత'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.month, out: false));
      expect(askodoxOfflineAsk('ఈరోజు ఎంత ఖర్చు అయింది'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: true));
      expect(askodoxOfflineAsk('How much came today?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false));
      expect(askodoxOfflineAsk('how much did I spend yesterday? i paid a lot'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.yesterday, out: true));
      expect(askodoxOfflineAsk('total payments this week'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.week, out: false));
      expect(askodoxOfflineAsk('आज कितना आया?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false));
      expect(askodoxOfflineAsk('कल कितना आया?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.yesterday, out: false));
    });

    test('the last payment and who paid', () {
      expect(askodoxOfflineAsk('ఆఖరి payment'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false, last: true));
      expect(askodoxOfflineAsk('last payment received'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false, last: true));
      expect(askodoxOfflineAsk('ఈరోజు ఎవరు ఎంత కట్టారు?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false, who: true));
      expect(askodoxOfflineAsk('Who paid today?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false, who: true));
      expect(askodoxOfflineAsk('आज किसने कितना दिया?'), const AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: false, who: true));
    });

    test('every ready question is one the phone answers', () {
      for (final lang in ['te', 'hi', 'en']) {
        for (final q in askodoxOfflineReadyQuestions(lang)) {
          expect(askodoxOfflineAsk(q), isNotNull, reason: '$lang: $q');
        }
      }
    });

    test('anything else needs the net: prices, weather, how-to, dues, shopping', () {
      for (final q in [
        'ఈరోజు బంగారం ధర ఎంత?',
        'రేపు వర్షం పడుతుందా?',
        'today gold rate',
        'how to pay by UPI today',
        'బాకీ ఎవరు?',
        'ఒక బిర్యానీ ఆర్డర్ పెట్టాలి',
        'iPhone price in India today',
        'hi',
        'ఈరోజు వార్తలు',
        'payment',
      ]) {
        expect(askodoxOfflineAsk(q), isNull, reason: q);
      }
    });
  });

  group('the answer comes only from the phone\'s own payment rows', () {
    test('today: total, count, the biggest, what the bank has not confirmed, and where the figure is from', () {
      final a = askodoxOfflineAnswer(askodoxOfflineAsk('ఈరోజు ఎంత వచ్చింది?')!, events, now, 'te');
      expect(a, contains('₹2,000'));
      expect(a, contains('3 payments'));
      expect(a, contains('Lakshmi Kirana ₹1,200, 10:15'));
      expect(a, contains('వీటిలో 1 bank SMS ఇంకా నిర్ధారించలేదు'));
      expect(a, contains(askodoxOfflineSourceNote('te')));
      expect(a, isNot(contains('99,999')), reason: 'a test row is not money');
      expect(a, isNot(contains('8,551')), reason: 'a row set aside is not money');
    });

    test('money out, yesterday, week, month', () {
      expect(askodoxOfflineAnswer(askodoxOfflineAsk('ఈరోజు ఎంత ఖర్చు అయింది')!, events, now, 'te'), contains('₹448'));
      expect(askodoxOfflineAnswer(askodoxOfflineAsk('How much came yesterday?')!, events, now, 'en'), contains('₹900 (1 payment)'));
      // Monday: the week has only today in it
      expect(askodoxOfflineAnswer(askodoxOfflineAsk('How much came this week?')!, events, now, 'en'), contains('₹2,000'));
      expect(askodoxOfflineAnswer(askodoxOfflineAsk('ఈ నెల ఎంత వచ్చింది')!, events, now, 'te'), contains('₹5,400'));
    });

    test('who paid: one line per name, biggest first', () {
      final a = askodoxOfflineAnswer(askodoxOfflineAsk('ఈరోజు ఎవరు ఎంత కట్టారు?')!, events, now, 'te');
      expect(a, contains('Lakshmi Kirana ₹1,200, Ravi ₹800'));
      expect(a, contains('మొత్తం ₹2,000'));
    });

    test('the last payment, with the app it came through', () {
      final a = askodoxOfflineAnswer(askodoxOfflineAsk('Last payment')!, events, now, 'en');
      expect(a, contains('₹500 · Ravi · 12:30 · Google Pay'));
      expect(a, isNot(contains('Not confirmed')));
    });

    test('no rows = it says so, never a made-up figure', () {
      final a = askodoxOfflineAnswer(askodoxOfflineAsk('ఈరోజు ఎంత వచ్చింది?')!, const [], now, 'te');
      expect(a, contains('record ఈ phone లో లేదు'));
      expect(a, isNot(contains('₹')));
      expect(askodoxOfflineAnswer(askodoxOfflineAsk('Last payment')!, const [], now, 'en'), contains('no payment record'));
    });

    test('Indian grouping', () {
      expect(askodoxRupeesIn(425000), '₹4,250');
      expect(askodoxRupeesIn(12345678), '₹1,23,456.78');
      expect(askodoxRupeesIn(1234567800), '₹1,23,45,678');
      expect(askodoxRupeesIn(9900), '₹99');
    });
  });

  group('questions that wait for the net', () {
    test('kept once, oldest dropped past the limit, old ones not asked', () {
      var list = <AskodoxHeldQuestion>[];
      list = askodoxHeldAdd(list, 'ఈరోజు బంగారం ధర ఎంత?', 1000);
      list = askodoxHeldAdd(list, ' ఈరోజు బంగారం ధర ఎంత? ', 2000);
      expect(list.length, 1);
      expect(list.single.atMs, 2000);
      for (var i = 0; i < 12; i++) {
        list = askodoxHeldAdd(list, 'question $i', 3000 + i);
      }
      expect(list.length, askodoxHeldMax);
      expect(list.last.text, 'question 11');
      expect(askodoxHeldDecode(askodoxHeldEncode(list)).map((q) => q.text), list.map((q) => q.text));
      expect(askodoxHeldDecode('not json'), isEmpty);
      expect(askodoxHeldFresh(list, 3000 + askodoxHeldKeepMs + 5), hasLength(7));
    });

    test('the store survives a restart and empties as questions are asked', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AskodoxHeldQuestions.instance;
      expect(await store.add('రేపు వర్షం పడుతుందా?', nowMs: 5000), 1);
      expect(await store.add('today gold rate', nowMs: 6000), 2);
      final held = await store.load(nowMs: 7000);
      expect(held.map((q) => q.text), ['రేపు వర్షం పడుతుందా?', 'today gold rate']);
      await store.remove(held.first);
      expect(store.count.value, 1);
      expect(await store.load(nowMs: 6000 + askodoxHeldKeepMs + 1), isEmpty);
      expect(store.count.value, 0);
    });

    test('the kept text says the answer comes by itself', () {
      expect(askodoxOfflineKeptText('te', 1), contains('net రాగానే'));
      expect(askodoxOfflineKeptText('te', 3), contains('3 ప్రశ్నలు'));
      expect(askodoxOfflineKeptText('en', 1), isNot(contains('waiting)')));
    });
  });

  group('the strip above the composer', () {
    setUp(() {
      AskodoxNetQuality.instance.reset();
      AskodoxHeldQuestions.instance.count.value = 0;
    });
    tearDown(() {
      AskodoxNetQuality.instance.reset();
      AskodoxHeldQuestions.instance.count.value = 0;
    });

    Future<List<String>> pump(WidgetTester tester) async {
      final asked = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AskodoxOfflineAskStrip(lang: 'te', onAsk: asked.add))));
      return asked;
    }

    testWidgets('nothing on a working net; ready questions with no net; a tap asks', (tester) async {
      final asked = await pump(tester);
      expect(find.byKey(const Key('askodoxOfflineAskStrip')), findsNothing);
      AskodoxNetQuality.instance.take(null);
      await tester.pump();
      expect(find.byKey(const Key('askodoxOfflineAsk-0')), findsOneWidget);
      expect(find.byKey(const Key('askodoxOfflineHeld')), findsNothing);
      await tester.tap(find.byKey(const Key('askodoxOfflineAsk-0')));
      expect(asked, ['ఈరోజు ఎంత వచ్చింది?']);
    });

    testWidgets('waiting questions are counted; when the net is back the ready questions go', (tester) async {
      await pump(tester);
      AskodoxNetQuality.instance.take(null);
      AskodoxHeldQuestions.instance.count.value = 2;
      await tester.pump();
      expect(find.text('2 ప్రశ్నలు net కోసం ఆగి ఉన్నాయి'), findsOneWidget);
      AskodoxNetQuality.instance.take(900);
      await tester.pump();
      expect(find.byKey(const Key('askodoxOfflineAsk-0')), findsNothing);
      expect(find.byKey(const Key('askodoxOfflineHeld')), findsOneWidget);
      AskodoxHeldQuestions.instance.count.value = 0;
      await tester.pump();
      expect(find.byKey(const Key('askodoxOfflineAskStrip')), findsNothing);
    });
  });
}
