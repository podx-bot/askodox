import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/net/net_quality.dart';

void main() {
  setUp(AskodoxNetQuality.instance.reset);
  tearDown(AskodoxNetQuality.instance.reset);

  test('owner 2026-11-23: slow net or no net turns Lite mode on by itself; two fast readings turn it off', () {
    final net = AskodoxNetQuality.instance;
    expect(net.lite, isFalse);
    net.take(400);
    expect(net.state.value, AskodoxNet.good);
    net.take(3200); // one slow answer
    expect(net.state.value, AskodoxNet.slow);
    net.take(600); // one lucky fast answer on a weak signal is not "good" yet
    expect(net.state.value, AskodoxNet.slow);
    net.take(700);
    expect(net.state.value, AskodoxNet.good);
    net.take(null); // the request failed / timed out
    expect(net.state.value, AskodoxNet.offline);
    net.take(2000); // an answer came: not offline any more, still Lite
    expect(net.state.value, AskodoxNet.slow);
    net.take(900);
    net.take(3000); // slow again: the count of fast readings starts over
    net.take(900);
    expect(net.lite, isTrue);
    net.take(900);
    expect(net.lite, isFalse);
  });

  test('a middling reading changes nothing on a good net', () {
    expect(askodoxNetAfter(AskodoxNet.good, 0, 2000).state, AskodoxNet.good);
    expect(askodoxNetAfter(AskodoxNet.slow, 1, 2000), (state: AskodoxNet.slow, goodRun: 0));
  });

  test('a failing probe counts as offline; nothing is probed before start', () async {
    final net = AskodoxNetQuality.instance;
    await net.check();
    expect(net.state.value, AskodoxNet.good);
    net.start(() async => throw Exception('no route'));
    await Future<void>.delayed(Duration.zero);
    expect(net.state.value, AskodoxNet.offline);
  });

  testWidgets('the banner shows only in Lite mode and says what still works', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AskodoxLiteBanner(te: false))));
    expect(find.byKey(const Key('askodoxLiteBanner-slow')), findsNothing);
    AskodoxNetQuality.instance.take(5000);
    await tester.pump();
    expect(find.byKey(const Key('askodoxLiteBanner-slow')), findsOneWidget);
    expect(find.textContaining('text first'), findsOneWidget);
    AskodoxNetQuality.instance.take(null);
    await tester.pump();
    expect(find.byKey(const Key('askodoxLiteBanner-offline')), findsOneWidget);
    expect(find.textContaining('payment sound'), findsOneWidget);
    AskodoxNetQuality.instance.take(300);
    AskodoxNetQuality.instance.take(300);
    await tester.pump();
    expect(find.byKey(const Key('askodoxLiteBanner-offline')), findsNothing);
    expect(find.byKey(const Key('askodoxLiteBanner-slow')), findsNothing);
  });

  testWidgets('a result photo waits for a tap in Lite mode', (tester) async {
    AskodoxNetQuality.instance.take(5000);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 60,
                height: 60,
                child: AskodoxLiteImage('https://example.com/a.png', fallback: Icon(Icons.storefront, key: Key('fallback')))))));
    expect(find.byType(Image), findsNothing, reason: 'nothing is downloaded until asked');
    expect(find.byKey(const Key('fallback')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxLitePhotoTap')));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });
}
