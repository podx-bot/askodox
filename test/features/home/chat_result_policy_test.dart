import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/orders/data/order_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

UniversalMatch _m(String id, String source, {String? url}) =>
    UniversalMatch(id: id, title: id, source: source, destinationUrl: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('card actions follow the result source', () {
    test('deal Party B matches connect through the consent flow', () {
      expect(chatResultActionFor(_m('app-seller-1', 'interest')),
          ChatResultAction.connect);
      expect(chatResultActionFor(_m('app-demo-1', 'demo_discovery')),
          ChatResultAction.connect);
      expect(chatResultActionFor(_m('demo-chicken-1', 'local')),
          ChatResultAction.connect);
    });

    test('real seller listings send an order request', () {
      expect(chatResultActionFor(_m('42', 'local')),
          ChatResultAction.sendRequest);
    });

    test('online and video results only open links, never send requests', () {
      expect(chatResultActionFor(_m('online-x', 'online', url: 'https://a.b')),
          ChatResultAction.openLink);
      expect(chatResultActionFor(_m('video-x', 'video', url: 'https://youtu.be/x')),
          ChatResultAction.watchVideo);
    });

    test('results group into local, online and video sections', () {
      final results = AskodoxChatResults(dealId: '7', matches: [
        _m('online-1', 'online', url: 'https://a.b'),
        _m('app-seller-1', 'interest'),
        _m('video-1', 'video', url: 'https://youtu.be/x'),
        _m('12', 'local'),
      ]);
      expect(results.local.map((m) => m.id), ['app-seller-1', '12']);
      expect(results.online.map((m) => m.id), ['online-1']);
      expect(results.videos.map((m) => m.id), ['video-1']);
      expect(results.hasLocal, isTrue);
    });
  });

  group('contact consent', () {
    Order order(String status) => Order.fromJson({
          'id': 1,
          'buyer_user_id': 'app-phone-919000000001',
          'seller_user_id': 'app-phone-919000000002',
          'product_id': 3,
          'product_title': 'Mixer',
          'status': status,
        });

    test('contact is hidden before acceptance even if an id leaks', () {
      for (final status in ['PLACED', 'REJECTED', 'CANCELLED', '', 'weird']) {
        expect(order(status).sellerContact, isNull, reason: status);
        expect(order(status).buyerContact, isNull, reason: status);
      }
    });

    test('contact is available only after an allowed status', () {
      expect(order('ACCEPTED').sellerContact, '919000000002');
      expect(order('FULFILLED').buyerContact, '919000000001');
      expect(orderContactVisible('accepted'), isTrue);
      expect(orderContactVisible('PLACED'), isFalse);
    });
  });

  group('roles follow user activity', () {
    test('clear self-descriptions pick the active role', () {
      expect(askodoxDetectRole('I want chicken')!.role, AskodoxUserRole.buyer);
      expect(askodoxDetectRole('I want to sell my TV')!.role, AskodoxUserRole.seller);
      expect(askodoxDetectRole('I repair ACs')!.role, AskodoxUserRole.serviceProvider);
      expect(askodoxDetectRole('I need a computer operator job')!.role, AskodoxUserRole.jobSeeker);
      expect(askodoxDetectRole('I can deliver parcels')!.role, AskodoxUserRole.deliveryPartner);
      expect(askodoxDetectRole('నాకు ఉద్యోగం కావాలి')!.role, AskodoxUserRole.jobSeeker);
      expect(askodoxDetectRole('I want to sell my TV')!.ambiguous, isFalse);
      expect(askodoxDetectRole('hello there'), isNull);
    });

    test('questions about a role are ambiguous and high-impact switches ask first', () {
      final detection = askodoxDetectRole('Can I sell things on ASKODOX?')!;
      expect(detection.role, AskodoxUserRole.seller);
      expect(detection.ambiguous, isTrue);
      expect(askodoxRoleSwitchIsHighImpact(AskodoxUserRole.seller), isTrue);
      expect(askodoxRoleSwitchIsHighImpact(AskodoxUserRole.buyer), isFalse);
      expect(askodoxRoleSwitchQuestion(AskodoxUserRole.seller, telugu: false),
          'Switch to Seller mode?');
    });

    test('role change message in English and Telugu', () {
      expect(
        askodoxRoleChangedMessage(AskodoxUserRole.buyer, AskodoxUserRole.seller, telugu: false),
        'Active role changed: Buyer → Seller',
      );
      expect(
        askodoxRoleChangedMessage(AskodoxUserRole.buyer, AskodoxUserRole.seller, telugu: true),
        contains('విక్రేత'),
      );
    });

    test('deal intents map to user roles', () {
      expect(askodoxRoleForIntent(DealIntent.needService), AskodoxUserRole.buyer);
      expect(askodoxRoleForIntent(DealIntent.offerService), AskodoxUserRole.serviceProvider);
      expect(askodoxRoleForIntent(DealIntent.deliverParcel), AskodoxUserRole.deliveryPartner);
      expect(askodoxRoleForIntent(DealIntent.seekWork), AskodoxUserRole.jobSeeker);
    });

    test('active role persists without touching stored roles', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final roles = AskodoxRoleController();
      await Future<void>.delayed(Duration.zero);
      roles.toggleOwned(AskodoxUserRole.serviceProvider, true);
      roles.setActive(AskodoxUserRole.seller);
      expect(roles.state.active, AskodoxUserRole.seller);
      expect(roles.state.owned, {AskodoxUserRole.buyer, AskodoxUserRole.serviceProvider});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final reloaded = AskodoxRoleController();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reloaded.state.active, AskodoxUserRole.seller);
      expect(reloaded.state.owned, {AskodoxUserRole.buyer, AskodoxUserRole.serviceProvider});
    });
  });

  group('multi-source results and AI-first flow', () {
    test('rows group into ordered, non-empty sections', () {
      final groups = askodoxGroupResults([
        const UniversalMatch(id: 'video-0', title: 'v', source: 'video', destinationUrl: 'https://y'),
        const UniversalMatch(id: '7', title: 'used tv', source: 'local', segment: 'used'),
        const UniversalMatch(id: 'external-1', title: 'shop', source: 'external', segment: 'nearby_external', destinationUrl: 'https://maps'),
        const UniversalMatch(id: '8', title: 'tv', source: 'local', segment: 'registered'),
      ]);
      expect(groups.map((g) => g.$1), [
        AskodoxResultSegment.registered,
        AskodoxResultSegment.used,
        AskodoxResultSegment.nearbyExternal,
        AskodoxResultSegment.video,
      ]);
    });

    test('nearby external shops are links, never requests', () {
      expect(
        chatResultActionFor(const UniversalMatch(id: 'external-1', title: 's', source: 'external')),
        ChatResultAction.openLink,
      );
    });

    test('human action and result questions are recognised', () {
      expect(askodoxWantsHumanAction('Please contact the seller'), isTrue);
      expect(askodoxWantsHumanAction("I'll take it"), isTrue);
      expect(askodoxWantsHumanAction('What is the price?'), isFalse);
      expect(askodoxIsResultsQuestion('Which one is better?'), isTrue);
      expect(askodoxIsResultsQuestion('Compare the first two'), isTrue);
      expect(askodoxIsResultsQuestion('Samsung under 30000'), isFalse);
      expect(askodoxIsResultsQuestion('I want the best mixer grinder'), isFalse);
      expect(askodoxIsResultsQuestion('Which is cheapest?'), isTrue);
      expect(askodoxIsResultsQuestion('Any reviews?'), isTrue);
    });
  });

  group('first-line support escalation', () {
    test('normal conversations never push support', () {
      expect(askodoxAssessSupport('I want chicken', previousIssueTurns: 0).need,
          AskodoxSupportNeed.none);
      expect(askodoxAssessSupport('What payment options do you accept?', previousIssueTurns: 0).need,
          AskodoxSupportNeed.none);
    });

    test('a problem is escalated only after ASKODOX AI tried', () {
      expect(askodoxAssessSupport('The app is not working', previousIssueTurns: 0).need,
          AskodoxSupportNeed.none);
      expect(askodoxAssessSupport('Still not working', previousIssueTurns: 1).need,
          AskodoxSupportNeed.afterAiAttempt);
      expect(askodoxAssessSupport('I want to talk to customer care', previousIssueTurns: 0).need,
          AskodoxSupportNeed.afterAiAttempt);
    });

    test('critical issues escalate immediately', () {
      final payment = askodoxAssessSupport('Money deducted but order not confirmed', previousIssueTurns: 0);
      expect(payment.need, AskodoxSupportNeed.immediate);
      expect(payment.category, 'PAYMENT');
      expect(askodoxAssessSupport('The seller is a scam', previousIssueTurns: 0).category, 'DISPUTE');
      expect(askodoxAssessSupport('I feel unsafe with this driver', previousIssueTurns: 0).category, 'SAFETY');
    });
  });

  group('fallback and replies', () {
    test('source status is reported honestly, never faked', () {
      const results = AskodoxChatResults(
        searched: true,
        sourceStatus: {'askodox': 'no_results', 'online': 'unavailable', 'videos': 'ok'},
      );
      expect(results.isEmpty, isFalse, reason: 'an empty real search is still shown, honestly');
      expect(results.sourcesWith('no_results'), ['askodox']);
      expect(results.sourcesWith('unavailable'), ['online']);
      expect(const AskodoxChatResults().isEmpty, isTrue);
    });

    test('image and file facts feed the same request pipeline', () {
      expect(askodoxAttachmentRequest('Find this', 'A steel pressure cooker'),
          'Find this\nAttachment facts: A steel pressure cooker');
      expect(askodoxAttachmentRequest('Find this', null), 'Find this');
      expect(askodoxAttachmentRequest('Find this', 'null'), 'Find this');
    });

    test('replies are honest about local, online, failure and missing details', () {
      final local = AskodoxChatResults(matches: [_m('app-s', 'interest')]);
      final online = AskodoxChatResults(
          matches: [_m('online-1', 'online', url: 'https://a.b')]);
      const failed = AskodoxChatResults(failed: true);
      const missing = AskodoxChatResults(missingFields: ['delivery_address']);
      final signIn = AskodoxChatResults(
          signInRequired: true,
          matches: [_m('online-1', 'online', url: 'https://a.b')]);

      expect(askodoxResultsReply(local, telugu: false), contains('local options'));
      expect(askodoxResultsReply(online, telugu: false),
          contains('No verified local match yet'));
      expect(askodoxResultsReply(failed, telugu: false), contains('Retry'));
      expect(askodoxResultsReply(missing, telugu: false),
          contains('delivery address'));
      expect(askodoxResultsReply(signIn, telugu: false), contains('Sign in'));
      expect(askodoxResultsReply(online, telugu: true), contains('ఆన్‌లైన్'));
      expect(askodoxDetailQuestionReply('How much do you need?', telugu: true),
          contains('How much do you need?'));
    });
  });
}
