import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_action_intent.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

const _a = UniversalMatch(id: '41', title: 'Sony 43 inch TV', source: 'local');
const _b = UniversalMatch(id: '42', title: 'LG 43 inch TV', source: 'local');

void main() {
  group('chat confirmation == button action', () {
    test('affirmatives in English/Telugu/Hindi act; questions and negatives never do', () {
      for (final yes in ['yes', 'ok go ahead', 'order it', 'send the request', 'book it', 'confirm',
          'yes, order the second one', 'సరే పంపండి', 'ఆర్డర్ చేయండి', 'हाँ भेजो']) {
        expect(askodoxConfirmsAction(yes), isTrue, reason: yes);
      }
      for (final no in ['no', "don't order it", 'can you confirm the price?', 'show me another option',
          'wait', 'compare them', 'వద్దు', 'नहीं']) {
        expect(askodoxConfirmsAction(no), isFalse, reason: no);
      }
    });

    test('target: ordinal, named title, focused option, else top option', () {
      expect(askodoxPickTarget('order the second one', [_a, _b])?.id, '42');
      expect(askodoxPickTarget('option 1', [_a, _b])?.id, '41');
      expect(askodoxPickTarget('yes the LG one', [_a, _b])?.id, '42');
      expect(askodoxPickTarget('yes', [_a, _b], focused: _b)?.id, '42');
      expect(askodoxPickTarget('yes', [_a, _b])?.id, '41');
      expect(askodoxPickTarget('yes', const []), isNull);
    });
  });

  group('role isolation', () {
    const brain = UniversalDealBrain();
    test('buyer wording never becomes a sell intent', () {
      for (final text in ['show me the best selling 43 inch TV', 'I have a budget of 25000 for a TV',
          'TV for sale near me', 'compare top sellers of fridges']) {
        expect(brain.capture(text).intent, isNot(DealIntent.sell), reason: text);
      }
      expect(brain.capture("I'm selling my car").intent, DealIntent.sell);
      expect(brain.capture('I have a used phone to sell in Guntur').intent, DealIntent.sell);
    });

    test('a guessed supply intent never flips the role; the user\'s own words do', () {
      expect(askodoxContextRole(spoken: null, fromIntent: AskodoxUserRole.seller), isNull);
      expect(askodoxContextRole(spoken: null, fromIntent: AskodoxUserRole.employer), AskodoxUserRole.employer);
      expect(askodoxContextRole(spoken: const AskodoxRoleDetection(AskodoxUserRole.seller), fromIntent: null),
          AskodoxUserRole.seller);
      expect(askodoxContextRole(spoken: const AskodoxRoleDetection(AskodoxUserRole.buyer),
          fromIntent: AskodoxUserRole.seller), AskodoxUserRole.buyer);
    });
  });

  group('job and parcel slots', () {
    const brain = UniversalDealBrain();
    test('a job seeker\'s skill is the subject sent to matching', () {
      final deal = brain.capture('I need a job').copyWith(dynamicFields: {'skill': 'delivery driver'});
      expect(askodoxEffectiveSubject(deal), 'delivery driver');
    });

    test('parcel route is understood in any wording and never becomes the subject', () {
      final d1 = brain.capture('send a document from Benz Circle Vijayawada to Kukatpally Hyderabad tomorrow');
      expect(d1.intent, DealIntent.sendParcel);
      expect(d1.dynamicFields['from'], 'Benz Circle Vijayawada');
      expect(d1.dynamicFields['to'], 'Kukatpally Hyderabad');
      expect(d1.subject, 'document delivery');
      final d2 = brain.capture('pickup at Benz Circle, drop at Governorpet');
      expect([d2.dynamicFields['from'], d2.dynamicFields['to']], ['Benz Circle', 'Governorpet']);
      final d3 = brain.capture('I need to send a parcel');
      expect(d3.intent, DealIntent.sendParcel);
      expect(d3.dynamicFields['from'], isNull, reason: '"I need" is not a pickup');
      final d4 = brain.capture('parcel to Hyderabad');
      expect(d4.dynamicFields['to'], 'Hyderabad');
      expect(d4.subject, isNot(contains('Hyderabad')));
      expect(brain.capture('send biryani parcel from Vijayawada to Guntur').category, 'parcel');
    });

    test('one answer fills pickup AND drop; "current location" uses the known place', () {
      final controller = UniversalDealController();
      controller.start('I need to send a parcel');
      expect(controller.state.deal!.missingForMatch.take(2), ['from', 'to']);
      controller.answer('pickup at Benz Circle, drop at Governorpet');
      expect(controller.state.deal!.missingForMatch, isNot(contains('from')));
      expect(controller.state.deal!.missingForMatch, isNot(contains('to')));
      controller.answer('today 5 pm');
      expect(controller.state.deal!.readyToMatch, isTrue);

      final here = UniversalDealController();
      here.start('I need to send a parcel');
      here.applySelectedLocation(label: 'Benz Circle, Vijayawada', latitude: 16.5, longitude: 80.65, radiusKm: 5);
      here.answer('from my current location');
      expect(here.state.deal!.dynamicFields['from'], 'Benz Circle, Vijayawada');
    });
  });

  test('empty results say what really happened: broadcast count, open request, or sign in', () {
    const sent = AskodoxChatResults(dealId: '77', searched: true, broadcastSent: 3,
        sourceStatus: {'askodox': 'no_results', 'nearby': 'error', 'online': 'not_applicable'});
    final text = askodoxNoResultsText(sent, telugu: false);
    expect(text, contains('ASKODOX sellers'));
    expect(text, contains('nearby businesses could not be reached'));
    expect(text, contains('sent your request to 3 registered'));
    expect(text, isNot(contains('online')), reason: 'not-applicable sources are not claimed as searched');
    const open = AskodoxChatResults(dealId: '78', searched: true);
    expect(askodoxNoResultsText(open, telugu: false), contains('#78 stays open'));
    const guest = AskodoxChatResults(dealId: '', searched: true);
    expect(askodoxNoResultsText(guest, telugu: false), contains('Sign in to save'));
  });
}
