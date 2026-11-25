import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/answer_card.dart';
import 'package:podx/features/home/presentation/answer_card_view.dart';

/// One-screen answers at 360 x 780 (owner 2026-11-24: every answer fits ONE phone screen, any language).
AskodoxAnswerCard _mudra() => AskodoxAnswerCard.fromJson({
      'kind': 'answer',
      'label': 'ముద్ర loan · షాప్ / business కోసం',
      'headline': '₹20 lakh వరకు loan. హామీ (collateral) అవసరం లేదు.',
      'speak': '₹20 lakh వరకు loan వస్తుంది.',
      'tabs': [
        {
          'id': 'types', 'label': 'రకాలు', 'icon': 'money', 'style': 'cards', 'title': '4 రకాలు',
          'items': [
            {'title': 'శిశు', 'value': '₹50,000', 'sub': 'వరకు', 'body': 'కొత్తగా మొదలుపెట్టే చిన్న షాప్ కి'},
            {'title': 'కిశోర్', 'value': '₹5 lakh', 'sub': '₹50,000 పైన నుంచి', 'body': 'నడుస్తున్న షాప్ పెంచడానికి'},
            {'title': 'తరుణ్', 'value': '₹10 lakh', 'sub': '₹5 lakh పైన నుంచి', 'body': 'పెద్ద business, machines కొనడానికి'},
            {'title': 'తరుణ్ ప్లస్', 'value': '₹20 lakh', 'sub': '₹10 lakh పైన నుంచి', 'body': 'తరుణ్ loan సరిగా తీర్చినవాళ్ళకి'},
          ],
        },
        {
          'id': 'who', 'label': 'ఎవరికి', 'icon': 'who', 'style': 'grid',
          'items': [
            {'title': 'కిరాణా షాప్'}, {'title': 'Tailor'}, {'title': 'Hotel / Tiffin'},
            {'title': 'Auto / Van'}, {'title': 'Beauty parlour'}, {'title': 'Repair షాప్'},
          ],
        },
        {
          'id': 'docs', 'label': 'Papers', 'icon': 'papers', 'style': 'checklist',
          'items': [
            {'title': 'Aadhaar'}, {'title': 'PAN card'}, {'title': 'Bank passbook'},
            {'title': 'Shop proof'}, {'title': 'Photos'}, {'title': 'Quotation'},
          ],
        },
        {
          'id': 'how', 'label': 'ఎలా', 'icon': 'steps', 'style': 'steps',
          'items': [
            {'title': 'Bank కి వెళ్ళండి', 'body': 'మీ account ఉన్న bank లేదా online లో apply చేయొచ్చు'},
            {'title': 'Papers ఇవ్వండి', 'body': 'ఏమి కొంటారో దాని quotation కూడా తీసుకెళ్ళండి'},
            {'title': 'Loan వస్తుంది', 'body': 'Bank check చేసి నేరుగా account లో వేస్తుంది'},
          ],
        },
      ],
      'primary': {'kind': 'ask', 'label': 'నాకు ఏ loan సరిపోతుంది?', 'value': 'నాకు ఏ ముద్ర loan సరిపోతుంది?'},
    })!;

AskodoxAnswerCard _sms() => AskodoxAnswerCard.fromJson({
      'kind': 'check',
      'label': 'SMS check',
      'headline': 'ఈ SMS ఇంకా నమ్మకండి. ముందు ఒక్కసారి check చేయండి.',
      'risk': 'careful',
      'risk_label': 'జాగ్రత్త',
      'seen': {
        'title': 'SMS లో నేను చూసినవి',
        'text': 'Rs 8,551 received for NSE trade bills bit.ly/3xK9 -INNOVATESECURITIES · 6:20 PM',
        'marks': [
          {'text': '8,551', 'kind': 'money'},
          {'text': 'bit.ly/3xK9', 'kind': 'link'},
          {'text': 'INNOVATESECURITIES', 'kind': 'sender'},
        ],
      },
      'donts': [
        {'icon': 'link', 'text': 'Link నొక్కకండి'},
        {'icon': 'otp', 'text': 'OTP చెప్పకండి'},
        {'icon': 'reply', 'text': 'Reply ఇవ్వకండి'},
      ],
      'replies': [
        {'label': 'ఖాతా ఉంది', 'tone': 'ok', 'text': 'అయితే ఇది మామూలు alert అయ్యుండొచ్చు. Broker app లోనే ledger చూడండి.'},
        {
          'label': 'వీళ్ళెవరో తెలియదు', 'tone': 'warn', 'text': 'ఇది scam అయ్యే అవకాశం ఎక్కువ.',
          'actions': [
            {'kind': 'sms', 'label': 'Spam report', 'value': '1909'},
            {'kind': 'block_help', 'label': 'Number block', 'value': ''},
          ],
        },
        {
          'label': 'డబ్బు పోయింది', 'tone': 'danger', 'text': 'వెంటనే – మొదటి గంట చాలా ముఖ్యం',
          'actions': [
            {'kind': 'call', 'label': '1930 call', 'value': '1930'},
            {'kind': 'bank_help', 'label': 'Bank కి call', 'value': ''},
          ],
        },
      ],
      'primary': {'kind': 'open_upi', 'label': 'డబ్బు కట్ అయిందా? Bank చూడండి', 'value': ''},
      'share': true,
    })!;

Future<void> _pump(WidgetTester tester, AskodoxAnswerCard card,
    {List<AskodoxCardAction>? ran, List<String>? asked, String language = 'te'}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(padding: const EdgeInsets.all(8), children: [
        AskodoxAnswerCardView(
          card: card,
          language: language,
          maxHeight: 780 - 160,
          onAsk: (say) => asked?.add(say),
          runAction: (a) async => ran?.add(a),
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('a reply that says the same as the big button is not drawn twice', () {
    // Owner phone 2026-11-25: "Is it right for me?" was a reply button AND the big bottom button.
    const card = AskodoxAnswerCard(
      headline: 'Sector funds investing in roads, power, ports and railways.',
      replies: [AskodoxCardReply(label: 'Compare with index fund'), AskodoxCardReply(label: 'Is it right for me?')],
      primary: AskodoxCardAction(kind: 'ask', label: 'Is it right for me ?'),
    );
    expect(card.shownReplyIndexes, [0]);
    const noMain = AskodoxAnswerCard(headline: 'x', replies: [AskodoxCardReply(label: 'A'), AskodoxCardReply(label: 'B')]);
    expect(noMain.shownReplyIndexes, [0, 1]);
  });


  testWidgets('Mudra answer: one screen, 4 tabs change the content inside the same card', (tester) async {
    final asked = <String>[];
    await _pump(tester, _mudra(), asked: asked);
    expect(tester.takeException(), isNull);
    final cardBox = tester.getRect(find.byKey(const Key('askodoxAnswerCard')));
    expect(cardBox.height, lessThanOrEqualTo(620.0), reason: 'never taller than the chat area');
    expect(find.byKey(const Key('askodoxAnswerCardHeadline')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAnswerCardVoice')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAnswerCardMic')), findsOneWidget);
    expect(find.text('₹50,000'), findsOneWidget);

    // Swipe sideways to the next card.
    await tester.drag(find.byKey(const ValueKey('askodoxAnswerCardPages-types')), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('₹5 lakh'), findsWidgets);

    for (final (i, expected) in [(1, 'Tailor'), (2, 'Aadhaar'), (3, 'Bank కి వెళ్ళండి')].indexed) {
      await tester.tap(find.byKey(ValueKey('askodoxAnswerCardTab-${expected.$1}')));
      await tester.pumpAndSettle();
      expect(find.text(expected.$2), findsOneWidget, reason: 'tab $i');
      expect(tester.takeException(), isNull);
    }

    // Papers: tick what you have.
    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardTab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardCheck-0')));
    await tester.pumpAndSettle();
    expect(find.text('5 ఇంకా కావాలి'), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxAnswerCardPrimary')));
    expect(asked, ['నాకు ఏ ముద్ర loan సరిపోతుంది?']);
  });

  testWidgets('SMS check: risk meter, coloured SMS, donts, reply follow-ups inside the card', (tester) async {
    final ran = <AskodoxCardAction>[];
    await _pump(tester, _sms(), ran: ran);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('askodoxAnswerCardRisk-careful')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAnswerCardSeen')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAnswerCardDont-2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAnswerCardShare')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('askodoxAnswerCard'))).height, lessThanOrEqualTo(620.0));

    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardReply-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAnswerCardFollowUp')), findsOneWidget);
    expect(find.text('1930 call'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardFollowAction-0')));
    expect(ran.single.kind, 'call');
    expect(ran.single.value, '1930');

    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardReply-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('మామూలు alert'), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxAnswerCardPrimary')));
    expect(ran.last.kind, 'open_upi');
    await tester.tap(find.byKey(const Key('askodoxAnswerCardShare')));
    expect(ran.last.kind, 'share');
    expect(tester.takeException(), isNull);
  });

  testWidgets('English and a card with no tabs still fit; a reply without follow-up is asked', (tester) async {
    final asked = <String>[];
    final card = AskodoxAnswerCard.fromJson({
      'headline': 'Yes, you can apply online in 10 minutes.',
      'replies': [
        {'label': 'Show me how', 'tone': 'neutral', 'text': ''},
      ],
    })!;
    await _pump(tester, card, asked: asked, language: 'en');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('askodoxAnswerCardReply-0')));
    expect(asked, ['Show me how']);
  });

  testWidgets('a small phone height keeps the card inside the screen (no overflow)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          AskodoxAnswerCardView(card: _sms(), language: 'te', maxHeight: 640 - 120),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
