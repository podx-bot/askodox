import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/orders/data/order_repository.dart';

UniversalMatch _m(String id, String source, {String? url}) =>
    UniversalMatch(id: id, title: id, source: source, destinationUrl: url);

void main() {
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
    test('buyer to seller switch is announced in English and Telugu', () {
      expect(
        askodoxRoleSwitchNotice(
            previous: DealIntent.buy, current: DealIntent.sell, telugu: false),
        'You are now acting as: Seller for this request',
      );
      expect(
        askodoxRoleSwitchNotice(
            previous: DealIntent.buy, current: DealIntent.sell, telugu: true),
        contains('విక్రేత'),
      );
    });

    test('no notice on first request or when the role is unchanged', () {
      expect(
          askodoxRoleSwitchNotice(
              previous: null, current: DealIntent.buy, telugu: false),
          isNull);
      expect(
          askodoxRoleSwitchNotice(
              previous: DealIntent.buy, current: DealIntent.buy, telugu: false),
          isNull);
    });

    test('service provider and customer are distinct roles', () {
      expect(askodoxRoleForIntent(DealIntent.needService),
          AskodoxChatRole.customer);
      expect(askodoxRoleForIntent(DealIntent.offerService),
          AskodoxChatRole.serviceProvider);
      expect(
        askodoxRoleSwitchNotice(
            previous: DealIntent.needService,
            current: DealIntent.offerService,
            telugu: false),
        contains('Service provider'),
      );
    });
  });

  group('fallback and replies', () {
    test('offline fallback is plain labelled links, never fake sellers', () {
      final rows = askodoxOfflineFallbackResults('mixer grinder');
      expect(rows.map((m) => m.source), ['online', 'video', 'video']);
      expect(rows.every((m) => m.price == null && m.distanceKm == null), isTrue);
      expect(rows.first.destinationUrl,
          'https://www.google.com/search?q=mixer+grinder+price');
      expect(askodoxOfflineFallbackResults('  '), isEmpty);
      expect(askodoxOfflineFallbackResults('ride', includeVideos: false),
          hasLength(1));
    });

    test('videos are offered only where they make sense', () {
      expect(askodoxIntentWantsVideos(DealIntent.buy), isTrue);
      expect(askodoxIntentWantsVideos(DealIntent.needService), isTrue);
      expect(askodoxIntentWantsVideos(DealIntent.needRide), isFalse);
      expect(askodoxIntentWantsVideos(DealIntent.sendParcel), isFalse);
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
