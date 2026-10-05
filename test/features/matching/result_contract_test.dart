import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/matching/domain/result_contract.dart';

UniversalMatch _m(String id) => UniversalMatch(id: id, title: id);

Map<String, Object?> _payload({List<Map<String, Object?>>? sections, bool claim = true}) => {
      'result_contract_version': 2,
      'sections': sections ??
          [
            {'kind': 'local', 'item_ids': ['l2', 'l1'], 'count': 2, 'requested': false},
            {'kind': 'online', 'item_ids': ['o1'], 'count': 1, 'requested': true},
            {'kind': 'videos', 'item_ids': [], 'count': 0, 'requested': true, 'empty_reason': 'source unavailable'},
          ],
      'answer': {'may_claim_results': claim, 'checked': ['online'], 'unavailable': ['videos']},
      'conversation_state': {
        'explicit_constraints': {'size': '9', 'budget_max': 2000},
      },
    };

void main() {
  group('canonical result contract', () {
    test('older backends (no contract) are recognised and keep the old order', () {
      expect(ResultContract.fromJson({'matches': []}), isNull);
      expect(ResultContract.fromJson({'result_contract_version': 1, 'sections': []}), isNull);
    });

    test('sections, honest answer and the exact constraints are parsed', () {
      final c = ResultContract.fromJson(_payload())!;
      expect(c.kinds, ['local', 'online', 'videos']);
      expect(c.sections.last.emptyReason, 'source unavailable');
      expect(c.sections.last.requested, isTrue);
      expect(c.mayClaimResults, isTrue);
      expect(c.unavailable, ['videos']);
      expect(c.explicitConstraints['size'], '9');
    });

    test('rows follow the backend order section by section; unlisted rows are kept, never dropped', () {
      final c = ResultContract.fromJson(_payload())!;
      final ordered = c.order([_m('o1'), _m('x9'), _m('l1'), _m('l2')], (m) => m.id);
      expect(ordered.map((m) => m.id), ['l2', 'l1', 'o1', 'x9']);
    });

    test('the same id twice is shown once', () {
      final c = ResultContract.fromJson(_payload())!;
      expect(c.order([_m('l1'), _m('l1'), _m('l2')], (m) => m.id).map((m) => m.id), ['l2', 'l1']);
    });

    test('rendered report: drawn sections, asked-for empty notice, hidden-by-advisor reason', () {
      final c = ResultContract.fromJson(_payload())!;
      final shown = askodoxRenderedSections(c, [_m('l1'), _m('l2'), _m('o1')]);
      expect(shown.rendered, ['local', 'online', 'videos']);
      expect(shown.hidden, isEmpty);
      final held = askodoxRenderedSections(c, const [], heldReason: 'held: advisor');
      expect(held.rendered, isEmpty);
      expect(held.hidden, {'local': 'held: advisor', 'online': 'held: advisor'});
    });
  });

  group('honesty and explicit constraints (APK 1292)', () {
    test('a reply that claims results is detected in en / te / hi', () {
      for (final reply in [
        'Showing running shoes available near you.',
        'Here are the mobile phones available under 15,000.',
        'Finding walking shoes in Size 8 or 9 for you.',
        'Let me check real sellers, shops and online options near you.',
        'విజయవాడలో ఉన్న రన్నింగ్ షూస్ చూపిస్తున్నాను.',
        'मैं आपके लिए जूते दिखा रहा हूं',
      ]) {
        expect(askodoxReplyClaimsResults(reply), isTrue, reason: reply);
      }
      for (final reply in ['What size do you need?', 'What budget do you have in mind?', 'Okay, any size.']) {
        expect(askodoxReplyClaimsResults(reply), isFalse, reason: reply);
      }
    });

    test('a reply restating the size differently is caught; the same size is fine', () {
      expect(askodoxReplyAltersSize('Finding walking shoes in Size 8 or 9', '9'), isTrue);
      expect(askodoxReplyAltersSize('Size 10 shoes', '9'), isTrue);
      expect(askodoxReplyAltersSize('Walking shoes, size 9, under ₹2000', '9'), isFalse);
      expect(askodoxReplyAltersSize('Size 9 it is', 'UK 9'), isFalse);
      expect(askodoxReplyAltersSize('Size 8 or 9', null), isFalse, reason: 'no size given yet');
    });

    test('the size is taken exactly as said', () {
      expect(askodoxExplicitSize('Size 9 ₹2000'), '9');
      expect(askodoxExplicitSize('size 9.5'), '9.5');
      expect(askodoxExplicitSize('size 8 or 9'), '8 or 9');
      expect(askodoxExplicitSize('UK 9 walking shoes'), 'UK 9');
      expect(askodoxExplicitSize('సైజు 9'), '9');
      expect(askodoxExplicitSize('size XL'), 'XL');
      expect(askodoxExplicitSize('walking shoes under 2000'), isNull);
      expect(askodoxExplicitSize('show us 10 options'), isNull);
    });

    test('with no cards the reply is the next question, the honest outcome, or "not searched yet"', () {
      expect(askodoxNoCardsReply(question: 'What budget do you have in mind?', telugu: false),
          'What budget do you have in mind?');
      const empty = AskodoxChatResults(dealId: '47', searched: true, sourceStatus: {'online': 'quota_exhausted'});
      expect(askodoxReplyClaimsResults(askodoxNoCardsReply(results: empty, telugu: false)), isFalse);
      expect(askodoxNoCardsReply(telugu: false), contains("haven't searched"));
      expect(askodoxNoResultsText(empty, telugu: false), contains('could not be reached'),
          reason: 'quota / disabled / unavailable sources are named, not hidden');
      expect(askodoxNoResultsText(empty, telugu: false), allOf(contains('Request saved (in Updates)'), isNot(contains('ID 47'))));
    });

    test('"Any" is a no-preference reply in en / te / hi, other short answers are not', () {
      for (final t in ['Any', 'any size', 'ఏదైనా', 'कोई भी', 'no preference']) {
        expect(UniversalDealController.isNoPreferenceReply(t), isTrue, reason: t);
      }
      for (final t in ['9', 'Size 9', 'Nike', '2000']) {
        expect(UniversalDealController.isNoPreferenceReply(t), isFalse, reason: t);
      }
    });
  });

  test('staff-approved news gets its own News group next to products, never replacing them', () {
    const news = UniversalMatch(id: 'content-7', title: 'Walking shoes buying guide', source: 'content',
        destinationUrl: 'https://news.example/guide');
    const product = UniversalMatch(id: 'web-1', title: 'Walking shoes', source: 'online',
        destinationUrl: 'https://shop.example/w');
    expect(askodoxCompareKindOf(news), AskodoxCompareKind.news);
    expect(askodoxCompareKindOf(product), AskodoxCompareKind.online);
    final groups = askodoxCompareGroups([news, product]).map((g) => g.$1).toList();
    expect(groups, [AskodoxCompareKind.online, AskodoxCompareKind.news]);
    expect(askodoxCompareLabel(AskodoxCompareKind.news, 'te'), 'వార్తలు');
  });
}
