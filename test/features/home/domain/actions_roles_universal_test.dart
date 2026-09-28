import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_action_intent.dart';
import 'package:podx/features/home/domain/need_state.dart';

/// Conversational actions = the same backend action as the buttons, and
/// browsing never turns a Buyer into a Seller -- for ANY category.
void main() {
  group('typed actions execute (no clarification loop)', () {
    const acts = [
      'yes', 'Yes please', 'ok do it', 'go ahead', 'order it', 'Order this', 'place order', 'place the order',
      'send request', 'send the request', 'send it', 'book it', 'book the first one', 'buy it',
      "I'll take the second one", 'choose option 2', 'order number 3', 'request this', 'call him',
      'contact the seller', 'connect me with the provider', 'go with the first one',
      'అవును పంపండి', 'సరే', 'ఇదే కావాలి', 'రెండో ది తీసుకుంటాను', 'हाँ भेजो', 'यही चाहिए', 'ले लूंगा',
    ];
    for (final text in acts) {
      test('"$text" acts', () => expect(askodoxConfirmsAction(text), isTrue));
    }
    const notActs = [
      'no', 'not this one', 'show me cheaper ones', 'is it available?', 'compare them', 'wait',
      'I want a TV', 'వద్దు', 'नहीं', 'another option please',
    ];
    for (final text in notActs) {
      test('"$text" does not act', () => expect(askodoxConfirmsAction(text), isFalse));
    }
  });

  test('"show me" / "search" / "చూపించండి" search now (any category)', () {
    for (final text in ['show me', 'Show me the options', 'search now', 'చూపించండి', 'दिखाओ', 'find it']) {
      expect(askodoxWantsResultsNow(text), isTrue, reason: text);
    }
  });

  group('roles: browsing never switches Buyer -> Seller', () {
    const browsing = [
      'show me TV sellers near me', 'who sells chicken here', 'list of shops selling AC',
      'TV for sale near me', 'I want to see car sellers', 'any seller for a used bike?',
      'I need AC installation', 'find delivery jobs', 'show me job openings',
    ];
    for (final text in browsing) {
      test('"$text"', () {
        final spoken = askodoxDetectRole(text);
        final role = askodoxContextRole(
          spoken: spoken,
          fromIntent: askodoxRoleForIntent(const UniversalDealBrain().capture(text).intent),
        );
        expect(role, isNot(AskodoxUserRole.seller));
        expect(role, isNot(AskodoxUserRole.serviceProvider));
      });
    }

    test('only the user\'s own words make them a seller / provider / job seeker', () {
      expect(askodoxDetectRole('I want to sell my TV')?.role, AskodoxUserRole.seller);
      expect(askodoxDetectRole('I repair ACs')?.role, AskodoxUserRole.serviceProvider);
      expect(askodoxDetectRole('I need a delivery job')?.role, AskodoxUserRole.jobSeeker);
      // A guessed supply intent never switches the role on its own.
      expect(askodoxContextRole(spoken: null, fromIntent: AskodoxUserRole.seller), isNull);
      expect(askodoxRoleForIntent(DealIntent.buy), AskodoxUserRole.buyer);
    });
  });
}
