import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/brand_lexicon.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_action_intent.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/domain/need_state.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

/// Real-phone regressions, fixed in the shared (universal) layer.
void main() {
  group('conversational action == the card button', () {
    for (final said in [
      'yes',
      'order it',
      'send it',
      'I want this',
      'i want this one',
      'contact seller',
      'Please contact the seller',
      'call the shop',
      'buy now',
      'సరే పంపండి',
    ]) {
      test('"$said" acts on the selected option', () => expect(askodoxConfirmsAction(said), isTrue));
    }
    for (final said in ['I want a TV', 'show me cheaper ones', 'no, wait', 'is it available?', 'compare them']) {
      test('"$said" is not an action', () => expect(askodoxConfirmsAction(said), isFalse));
    }
  });

  group('browsing never turns a Buyer into a Seller', () {
    test('"TV for sale near me" is a buyer', () {
      expect(askodoxDetectRole('43 inch TV for sale near me')?.role, isNot(AskodoxUserRole.seller));
    });
    test('"my bike for sale" is a seller', () {
      expect(askodoxDetectRole('my bike for sale')?.role, AskodoxUserRole.seller);
    });
    test('soft participation hints are confirmed, never switched silently', () {
      final hint = askodoxDetectRole('check my channel for TV reviews');
      expect(hint?.role, AskodoxUserRole.influencer);
      expect(hint?.ambiguous, isTrue);
      expect(askodoxDetectRole("I'm a farmer")?.ambiguous, isFalse);
    });
  });

  group('brand changes update the active search (any category, NO fixed brand list)', () {
    test('a short refinement reply is the brand -- including brands no list ever had', () {
      expect(askodoxQualifierReply('Tata'), 'Tata');
      expect(askodoxQualifierReply('blue star'), 'Blue Star');
      expect(askodoxQualifierReply('Kalyani'), 'Kalyani', reason: 'any maker, not a curated list');
    });
    test('how people say it names the brand', () {
      expect(askodoxDetectBrand('show only Tata cars'), 'Tata');
      expect(askodoxDetectBrand('Voltas brand AC please'), 'Voltas');
      expect(askodoxDetectBrand('brand: Prestige'), 'Prestige');
      expect(askodoxDetectBrand('Hero instead'), 'Hero');
    });
    test('brands real listings carry are recognised inside a sentence', () {
      expect(askodoxDetectBrand('I want a sony 43 inch TV', known: {'Sony'}), 'Sony');
    });
    test('Maruti 800 -> Tata replaces the previous brand and its model', () {
      expect(askodoxSubjectWithBrand('Maruti 800 car', 'Tata', previous: 'Maruti'), 'Tata car');
      expect(askodoxSubjectWithBrand('Maruti 800 car', 'Tata', known: {'Maruti'}), 'Tata car');
    });
    test('sizes and capacities are kept', () {
      expect(askodoxSubjectWithBrand('Samsung 43 inch TV', 'Sony', previous: 'Samsung'), 'Sony 43 inch TV');
      expect(askodoxSubjectWithBrand('Samsung 43 inch TV', 'Samsung'), 'Samsung 43 inch TV');
      expect(askodoxSubjectWithBrand('250 l fridge', 'LG'), 'LG 250 l fridge');
    });
    test('ordinary words, commands, numbers and sizes are not brands', () {
      for (final said in ['yes', 'cheaper', 'used', '1 kg', 'show me', 'go', 'nearby', 'thanks']) {
        expect(askodoxQualifierReply(said), isNull, reason: said);
      }
      expect(askodoxDetectBrand('shop on MG Road'), isNull);
      expect(askodoxDetectBrand('1 kg apple'), isNull);
      expect(askodoxDetectBrand('1.5 hp motor'), isNull);
    });
  });

  group('grounding: ASKODOX never invents facts about a result', () {
    test('missing facts are stated as not provided', () {
      const match = UniversalMatch(id: '7', title: 'Sri Chicken Centre', source: 'local');
      final context = askodoxOptionContext(match);
      expect(context, contains('rating/reviews: not provided'));
      expect(context, contains('price: not provided'));
      expect(context, contains('stock/availability: not provided'));
      expect(askodoxGroundingRule, contains('never guess'));
    });
    test('a snippet price is marked unverified', () {
      const match = UniversalMatch(id: 'o1', title: 'TV', source: 'online', price: 24990, priceVerified: false);
      expect(askodoxOptionContext(match), contains('(unverified)'));
    });
  });

  group('"show me / search / go" run the search (EN/TE/HI)', () {
    for (final said in ['show me', 'search', 'go', 'go ahead', 'find it', 'చూపించండి', 'ढूंढो']) {
      test('"$said"', () => expect(askodoxWantsResultsNow(said), isTrue));
    }
    test('ordinary words are not commands', () => expect(askodoxWantsResultsNow('good morning'), isFalse));
  });

  group('jobs are job openings, never products', () {
    test('job rows get their own section and keep the stated salary', () {
      final job = UniversalMatch.fromJson({
        'id': 'job-0', 'title': 'Computer operator', 'source': 'online', 'segment': 'jobs',
        'page_type': 'job_listing', 'salary_text': '₹20,000 - ₹30,000 per month',
        'destination_url': 'https://www.naukri.com/x',
      });
      expect(job.isJob, isTrue);
      expect(askodoxSegmentOf(job), AskodoxResultSegment.jobs);
      expect(askodoxSegmentTitle(AskodoxResultSegment.jobs, telugu: false, hasLocal: false), 'Job openings');
      expect(UniversalMatch.fromJson(job.toJson()).salaryText, '₹20,000 - ₹30,000 per month');
    });
  });
}
