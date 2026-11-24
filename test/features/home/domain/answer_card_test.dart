import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/answer_card.dart';
import 'package:podx/features/home/domain/conversation_language.dart';
import 'package:podx/shared/widgets/rich_reply.dart';

void main() {
  test('romanized + script language: the same answers as the backend (shared fixture)', () {
    final data = jsonDecode(File('test/fixtures/romanized_language_cases.json').readAsStringSync()) as Map;
    for (final c in data['cases'] as List) {
      expect(askodoxDetectLanguage(c[0] as String), c[1], reason: c[0] as String);
    }
    // Owner 2026-11-24: Telugu in English letters is Telugu from the first message.
    expect(askodoxNextConversationLanguage(current: 'en', message: 'e sms akadi unchi vachidhi'), 'te');
  });

  test('spoken part, mark removal and streaming never show half the mark', () {
    const reply = 'ఈ SMS ఇంకా నమ్మకండి.\n[[more]]\n## చేయకూడనివి\n- [risk] Link నొక్కకండి';
    expect(askodoxSpokenPart(reply), 'ఈ SMS ఇంకా నమ్మకండి.');
    expect(askodoxWithoutCardMark(reply), isNot(contains('[[more]]')));
    expect(askodoxCardSpokenReply(reply), 'ఈ SMS ఇంకా నమ్మకండి.');
    expect(askodoxCardSpokenReply('plain'), 'plain');
    expect(askodoxStreamingSpokenPart('Answer line.\n[[mo').text, 'Answer line.');
    expect(askodoxStreamingSpokenPart('Answer line.\n[[mo').complete, isFalse);
    expect(askodoxStreamingSpokenPart('Answer.\n[[more]]\n## A').complete, isTrue);
    expect(askodoxPlainReply(reply), isNot(contains('[[more]]')));
  });

  test('card parsing keeps only safe actions and marks that are in the text', () {
    final card = AskodoxAnswerCard.fromJson({
      'kind': 'check',
      'headline': 'Do not trust this SMS yet.',
      'risk': 'careful',
      'seen': {
        'title': 'What I saw',
        'text': 'Rs 8,551 received bit.ly/3x -INNOVATE',
        'marks': [
          {'text': '8,551', 'kind': 'money'},
          {'text': 'not there', 'kind': 'link'},
        ],
      },
      'tabs': [
        {'id': 'a', 'label': 'Types', 'icon': 'money', 'style': 'cards', 'items': [{'title': 'Shishu', 'value': '₹50,000'}]},
      ],
      'replies': [
        {
          'label': 'Money gone',
          'tone': 'danger',
          'text': 'Call now',
          'actions': [
            {'kind': 'call', 'label': '1930', 'value': '1930'},
            {'kind': 'call', 'label': 'bad', 'value': 'abc'},
          ],
        },
        {'label': 'Ask more', 'text': '', 'actions': []},
      ],
      'primary': {'kind': 'open_url', 'label': 'x', 'value': 'http://plain.example'},
      'actions': [{'kind': 'rocket', 'label': 'x'}],
      'share': true,
    })!;
    expect(card.isCheck, isTrue);
    expect(card.seenMarks.map((m) => m.text), ['8,551']);
    expect(card.replies.first.actions.single.value, '1930');
    expect(card.replies.first.answersInCard, isTrue);
    expect(card.replies.last.answersInCard, isFalse);
    expect(card.primary, isNull, reason: 'only https links');
    expect(card.actions, isEmpty);
    expect(AskodoxAnswerCard.fromJson({'tabs': []}), isNull);
  });

  test('marked pieces keep the text in order', () {
    final pieces = askodoxMarkedPieces('Rs 8,551 from X', const [AskodoxCardMark('8,551', 'money'), AskodoxCardMark('X', 'sender')]);
    expect(pieces.map((p) => p.text).join(), 'Rs 8,551 from X');
    expect(pieces.where((p) => p.kind != null).map((p) => p.kind), ['money', 'sender']);
  });

  test('share text never carries the scam link', () {
    final card = AskodoxAnswerCard.fromJson({
      'kind': 'check',
      'headline': 'Scam',
      'seen': {'text': 'Open https://bad.example/x now', 'marks': []},
      'donts': [{'icon': 'link', 'text': 'Do not tap'}],
    })!;
    final text = askodoxCardShareText(card, telugu: false);
    expect(text, isNot(contains('bad.example')));
    expect(text, contains('Do not tap'));
  });

  test('a lone "-" line is never drawn and a tag after a bullet does not split the point', () {
    const reply = 'Watch out\n-\n- [risk] Don\'t tap the link\n-\n- [caution] • Never share OTP';
    final blocks = askodoxParseReply(reply);
    final texts = [
      for (final b in blocks)
        switch (b) {
          AskodoxParagraph(:final text) => text,
          AskodoxListItem(:final text) => text,
          AskodoxHeading(:final text) => text,
          AskodoxTable() => '',
        },
    ];
    expect(texts, ['Watch out', "Don't tap the link", 'Never share OTP']);
  });
}
