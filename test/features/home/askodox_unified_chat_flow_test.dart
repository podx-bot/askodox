import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/config/environment.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/orders/data/order_repository.dart';
import 'package:podx/features/selling/data/seller_listing_repository.dart';
import 'package:podx/services/in_app_assistant_service.dart';
import 'package:podx/services/real_product_match_service.dart';
import 'dart:async';

import 'package:podx/features/home/presentation/video_viewer_screen.dart';
import 'package:podx/services/reply_speech_service.dart';
import 'package:podx/services/support_escalation_service.dart';
import 'package:podx/services/voice_transcription_service.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- fakes --

class _FakeMatchRepository implements UniversalMatchRepository {
  _FakeMatchRepository(this.responses);

  /// Each call to createAndMatch consumes the next entry: a
  /// [UniversalMatchResult] or an [Object] to throw.
  final List<Object> responses;
  final List<UniversalDeal> deals = [];
  final List<(String, String)> accepted = [];

  @override
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal) async {
    deals.add(deal);
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    if (next is UniversalMatchResult) return next;
    throw next;
  }

  @override
  Future<void> acceptMatch({required String dealId, required String matchId}) async {
    accepted.add((dealId, matchId));
  }

  @override
  Future<void> acceptSandboxPartyB({required String dealId, required String matchId}) async {}

  @override
  bool sandboxConversationReady({required String dealId, required String matchId}) => false;

  @override
  bool sandboxContactSharingAllowed({required String dealId, required String matchId}) => false;
}

class _FakeOrderRepository implements OrderRepository {
  final List<String> placed = [];

  @override
  Future<OrderActionResult> placeOrder({
    required String productId,
    double? quantity,
    String? buyerNote,
  }) async {
    placed.add(productId);
    return const OrderActionResult(success: true);
  }

  @override
  Future<List<Order>> myOrders({int limit = 50}) async => const [];

  @override
  Future<List<Order>> incomingOrders({int limit = 50}) async => const [];

  @override
  Future<OrderActionResult> respondToOrder({
    required String orderId,
    required String status,
    String? sellerNote,
  }) async =>
      const OrderActionResult(success: true);
}

class _FakeSellerListingRepository implements SellerListingRepository {
  final List<UniversalDeal> listed = [];

  @override
  Future<SellerListingResult> createListing(UniversalDeal deal) async {
    listed.add(deal);
    return const SellerListingResult(success: true);
  }
}

/// Scripted `/api/in-app/assistant`: `null` means the AI is unavailable
/// (deterministic fallback path); otherwise the JSON decision to return.
class _Assistant {
  _Assistant([this.decide]);
  final Map<String, Object?>? Function(String message)? decide;
  final List<Map<String, dynamic>> requests = [];
  Completer<void>? hold;

  InAppAssistantService service() => InAppAssistantService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          if (hold != null) await hold!.future;
          final decision = decide?.call(body['message'] as String);
          if (decision == null) {
            return http.Response(jsonEncode({'reply': '', 'source': 'fallback'}), 200);
          }
          return http.Response(jsonEncode(decision), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
}

RealProductMatchService _productSearch(List<Map<String, Object?>> items) =>
    RealProductMatchService(
      client: MockClient((_) async => http.Response(jsonEncode({'items': items}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );

AppConfig _config(BackendProvider provider) => AppConfig.fromEnvironment({
      'APP_ENV': 'development',
      'BACKEND_PROVIDER': provider.name,
      'API_BASE_URL': provider == BackendProvider.mock ? '' : 'https://api.example',
      'STORAGE_URL': '',
      'AUTH_OTP_ENABLED': 'false',
      'MAPS_PROVIDER': 'mock',
      'LOGGING_LEVEL': 'debug',
    });

const _localMatch = UniversalMatch(
  id: 'app-seller-1',
  title: 'Interested match',
  subtitle: 'Ready to connect',
  source: 'interest',
  score: 0.82,
  distanceKm: 1.4,
  ratingAverage: 4.5,
  reviewCount: 2,
);
const _onlineMatch = UniversalMatch(
  id: 'online-0-shop.example',
  title: 'Mixer grinder at Shop',
  subtitle: '₹2,999 with delivery',
  source: 'online',
  destinationUrl: 'https://shop.example/mixer?tag=askodox',
  affiliate: true,
  disclosure: 'Affiliate link',
);
const _videoMatch = UniversalMatch(
  id: 'video-0-youtube.com',
  title: 'Mixer grinder review',
  source: 'video',
  destinationUrl: 'https://www.youtube.com/watch?v=abc',
);

class _FakeVoice extends VoiceTranscriptionService {
  _FakeVoice(this.transcript);
  final String? transcript;
  final List<(String, String)> calls = [];
  Completer<void>? hold;

  @override
  Future<String?> transcribeFile(String path, {required String locale}) async {
    calls.add((path, locale));
    if (hold != null) await hold!.future;
    return transcript;
  }
}

class _FakeReplySpeech extends ReplySpeechService {
  Uint8List? audio;
  final List<(String, String)> calls = [];

  @override
  Future<Uint8List?> sarvamAudio(String text, {required String locale}) async {
    calls.add((text, locale));
    return audio;
  }
}

class _FakeSupport extends SupportEscalationService {
  final List<Map<String, Object?>> escalations = [];

  @override
  Future<AskodoxSupportCase?> escalate({
    required String issue,
    required String category,
    required bool critical,
    required List<Map<String, String>> conversation,
    Map<String, Object?> requirement = const {},
    String? dealId,
    String? counterpart,
    List<String> actionsTried = const [],
    String status = '',
    String activeRole = '',
    String locale = '',
    String? authToken,
  }) async {
    escalations.add({
      'issue': issue,
      'category': category,
      'critical': critical,
      'conversation': conversation,
      'actionsTried': actionsTried,
      'activeRole': activeRole,
    });
    return const AskodoxSupportCase(caseId: '12', whatsappUrl: 'https://wa.me/919000000000');
  }
}

// -------------------------------------------------------------- harness --

class _Harness {
  _Harness({
    required this.matches,
    _Assistant? assistant,
    List<Map<String, Object?>> products = const [],
    this.backend = BackendProvider.rest,
    String? voiceTranscript,
  })  : assistant = assistant ?? _Assistant(),
        productSearch = _productSearch(products),
        voice = _FakeVoice(voiceTranscript);

  final _FakeMatchRepository matches;
  final _Assistant assistant;
  final RealProductMatchService productSearch;
  final BackendProvider backend;
  final _FakeVoice voice;
  final support = _FakeSupport();
  final replySpeech = _FakeReplySpeech();
  final embeddedVideos = <Uri>[];
  final orders = _FakeOrderRepository();
  final listings = _FakeSellerListingRepository();

  Future<void> pump(WidgetTester tester, {String? locale}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (locale != null) 'askodox.locale': locale,
    });
    tester.view.physicalSize = const Size(1440, 5200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(_config(backend)),
        universalMatchRepositoryProvider.overrideWithValue(matches),
        orderRepositoryProvider.overrideWithValue(orders),
        sellerListingRepositoryProvider.overrideWithValue(listings),
        askodoxAssistantServiceProvider.overrideWithValue(assistant.service()),
        askodoxRealProductMatchServiceProvider.overrideWithValue(productSearch),
        askodoxVoiceTranscriptionServiceProvider.overrideWithValue(voice),
        askodoxSupportEscalationServiceProvider.overrideWithValue(support),
        askodoxReplySpeechServiceProvider.overrideWithValue(replySpeech),
        askodoxVideoEmbedBuilderProvider.overrideWithValue((uri) {
          embeddedVideos.add(uri);
          return Text('EMBED $uri');
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: AskodoxPrimaryHomeScreen())),
    ));
    await settle(tester);
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await settle(tester);
  }

  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await _Harness.settle(tester);
}

void main() {
  testWidgets('English buyer product request shows local match inside chat and Connect keeps contact hidden',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '77', matches: [_localMatch, _videoMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(h.matches.deals.single.intent, DealIntent.buy);
    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget,
        reason: 'results render under the assistant reply, in the chat');
    expect(find.text('ASKODOX matches'), findsOneWidget);
    expect(find.text('82% match'), findsOneWidget);
    expect(find.text('★ 4.5 (2)'), findsOneWidget);
    expect(find.text('Videos & reviews'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.textContaining('app-seller-1'), findsNothing);

    // AI-first: the first card offers a conversation, not a request.
    expect(find.text('Connect'), findsNothing);
    await _tapText(tester, 'Ask ASKODOX about this');
    expect(h.matches.deals, hasLength(1), reason: 'discussing an option never re-runs matching');
    expect(h.assistant.requests.last['message'], contains('Option the user is asking about: Interested match'));
    expect(find.textContaining('Here is what I know about this option'), findsOneWidget);
    expect(find.text('Phone/contact stays hidden until they accept.'), findsOneWidget);

    await _tapText(tester, 'Connect');
    expect(h.matches.accepted, [('77', 'app-seller-1')]);
    expect(h.orders.placed, isEmpty, reason: 'deal matches never become product orders');
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('only after they accept'), findsWidgets);
  });

  testWidgets('no local match falls back to online and video results without Send Request',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '78', matches: [_onlineMatch, _videoMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(find.text('No local match yet -- online options'), findsOneWidget);
    expect(find.textContaining('No verified local match yet'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Affiliate link'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Send request'), findsNothing);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('service request routes through AI understanding as a service need',
      (tester) async {
    final h = _Harness(
      assistant: _Assistant((message) => {
            'reply': 'I found AC technicians near you.',
            'domain': 'SERVICE',
            'transactional': true,
            'action': 'need_service',
            'confidence': 0.9,
            'source': 'universal_ai',
            'entities': {'service': 'AC repair', 'location': 'Vijayawada'},
          }),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '90', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'My AC is not cooling, need someone today');

    expect(h.matches.deals.single.intent, DealIntent.needService);
    expect(find.text('I found AC technicians near you.'), findsOneWidget);
    expect(find.text('Ask ASKODOX about this'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('Telugu conversation keeps Telugu replies and result labels', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '91', matches: [_onlineMatch]),
      ]),
    );
    await h.pump(tester, locale: 'te');
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(h.assistant.requests.single['locale'], 'te');
    expect(find.textContaining('ధృవీకరించిన స్థానిక match దొరకలేదు'), findsOneWidget);
    expect(find.text('స్థానిక match లేదు -- ఆన్‌లైన్ ఎంపికలు'), findsOneWidget);
    expect(find.text('తెరవండి'), findsOneWidget);
  });

  testWidgets('follow-up refinement keeps earlier results and sends conversation history',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '1', matches: [_onlineMatch]),
        const UniversalMatchResult(dealId: '2', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    await h.send(tester, 'I want to buy a 750 watt mixer grinder in Vijayawada');

    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxChatResults-3')), findsOneWidget);
    final history = h.assistant.requests.last['history'] as List;
    expect(history, hasLength(2));
    expect((history.first as Map)['text'], contains('mixer grinder'));
    expect(h.matches.deals.last.subject, contains('mixer grinder'));
  });

  testWidgets('matching failure shows honest retry state, then recovers', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        StateError('Unable to load matches.'),
        const UniversalMatchResult(dealId: '55', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(find.byKey(const Key('askodoxResultsFailed')), findsOneWidget);
    expect(find.textContaining('tap Retry below'), findsOneWidget);
    // No placeholder links while matching is down -- just an honest retry.
    expect(find.text('Open'), findsNothing);
    expect(find.textContaining('Search online'), findsNothing);
    expect(find.text('Connect'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('askodoxResultsRetry')));
    await tester.tap(find.byKey(const Key('askodoxResultsRetry')));
    await _Harness.settle(tester);

    expect(find.byKey(const Key('askodoxResultsFailed')), findsNothing);
    expect(find.text('Ask ASKODOX about this'), findsOneWidget);
  });

  testWidgets('signed-out buyer gets real listings with Send Request as an order request',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([StateError('Sign in required -- no session token was sent')]),
      products: [
        {'id': '42', 'title': 'Mixer grinder — 750W', 'subtitle': '₹3,200 • Vijayawada', 'price': 3200, 'provider_id': ''},
      ],
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(find.text('₹3200'), findsOneWidget);
    expect(find.text('Send request'), findsNothing);
    // Asking for the seller exposes the request without a new search.
    await h.send(tester, 'Please contact the seller');
    expect(find.textContaining('Tap Send request on the option you want'), findsOneWidget);
    await _tapText(tester, 'Send request');
    expect(h.orders.placed, ['42']);
    expect(h.matches.accepted, isEmpty);
    expect(find.text('Request sent'), findsOneWidget);
  });

  testWidgets('role follows activity: buyer then seller is announced and seller never runs a buyer search',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '5', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    expect(find.byKey(const Key('askodoxRoleNotice')), findsNothing);

    await h.send(tester, 'I want to sell my 2 bicycles in Vijayawada for 3000');

    expect(find.text('Active role changed: Buyer → Seller'), findsOneWidget);
    expect(h.listings.listed.single.intent, DealIntent.sell);
    expect(h.matches.deals, hasLength(1), reason: 'the sell turn must not run a buyer match');
  });

  testWidgets('live REST home never shows fake demo Nearby profiles', (tester) async {
    final live = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
    await live.pump(tester);
    expect(find.text('Demo local profiles'), findsNothing);
    expect(find.text('Sri Mobiles'), findsNothing);
  });

  testWidgets('mock sandbox home still shows labelled demo profiles', (tester) async {
    final sandbox = _Harness(
      matches: _FakeMatchRepository([StateError('unused')]),
      backend: BackendProvider.mock,
    );
    await sandbox.pump(tester);
    expect(find.text('Demo local profiles'), findsOneWidget);
  });

  // ------------------------------------------------ PR #88 acceptance --

  testWidgets('Chicken end-to-end: curry cut → 1 kg → skinless → fresh → delivery stays in the buying flow and matches once',
      (tester) async {
    final h = _Harness(
      assistant: _Assistant((message) {
        if (message.contains('chicken')) return null; // AI unavailable for the opener
        return {
          'reply': 'Noted.',
          'domain': 'PRODUCT',
          'transactional': false,
          'action': 'general_chat',
          'confidence': 0.4,
          'source': 'universal_ai',
          'entities': {'subject': message},
        };
      }),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '301', matches: [_localMatch, _onlineMatch, _videoMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy chicken in Vijayawada');
    expect(find.text('How much chicken do you need?'), findsOneWidget);

    for (final answer in ['curry cut', '1 kg', 'skinless', 'fresh']) {
      await h.send(tester, answer);
      expect(h.matches.deals, isEmpty, reason: 'no matching before details are complete ($answer)');
    }
    await h.send(tester, 'delivery');

    expect(h.matches.deals, hasLength(1));
    final deal = h.matches.deals.single;
    expect(deal.intent, DealIntent.buy);
    expect(deal.subject, 'chicken');
    expect(deal.quantity, 1);
    expect(deal.unit, 'kg');
    expect(deal.dynamicFields['cut'], 'curry cut');
    expect(deal.dynamicFields['chickenPreference'], 'skinless');
    expect(deal.fulfilment, 'delivery');
    expect(find.text('ASKODOX matches'), findsOneWidget);
    expect(find.text('Online options'), findsOneWidget);
    expect(find.text('Videos & reviews'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxChatResults-11')), findsOneWidget,
        reason: 'results sit under the last assistant reply in the same chat');
  });

  testWidgets('Chicken short answers survive an AI rewrite that looks like a new retail request',
      (tester) async {
    final h = _Harness(
      assistant: _Assistant((message) => message.contains('chicken')
          ? null
          : {
              'reply': 'Got it.',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'buy',
              'confidence': 0.8,
              'source': 'universal_ai',
              'entities': {'subject': message},
            }),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '302', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy chicken in Vijayawada');
    for (final answer in ['1 kg', 'curry cut', 'skinless', 'fresh', 'delivery']) {
      await h.send(tester, answer);
    }

    expect(h.matches.deals, hasLength(1));
    expect(h.matches.deals.single.subject, 'chicken');
    expect(h.matches.deals.single.dynamicFields['cut'], 'curry cut');
  });

  testWidgets('43-inch TV: no repeated size question, local + online + video results, refinement keeps context',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '401', matches: [_localMatch, _onlineMatch, _videoMatch]),
        const UniversalMatchResult(dealId: '402', matches: [_onlineMatch]),
      ]),
      assistant: _Assistant((message) => message.startsWith('Samsung')
          ? {
              'reply': 'Here are Samsung 43 inch TVs under ₹30,000.',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'buy',
              'confidence': 0.9,
              'source': 'universal_ai',
              'entities': {'subject': 'Samsung 43 inch TV', 'location': 'Vijayawada', 'price': 30000},
            }
          : null),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a 43 inch TV in Vijayawada');

    expect(find.text('What TV screen size do you prefer?'), findsNothing);
    expect(h.matches.deals.single.size, '43 inch');
    expect(find.text('ASKODOX matches'), findsOneWidget);
    expect(find.text('Affiliate link'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);

    await h.send(tester, 'Samsung under 30000');

    expect(h.matches.deals, hasLength(2));
    expect(h.matches.deals.last.subject, contains('43 inch'));
    expect((h.assistant.requests.last['history'] as List).first['text'],
        contains('43 inch TV'));
    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget,
        reason: 'first results stay in the conversation');
    expect(find.byKey(const ValueKey('askodoxChatResults-3')), findsOneWidget);
  });

  testWidgets('unfinished buyer deal: a sell request still switches role; an aside keeps the deal to resume',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '501', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy chicken in Vijayawada');
    await h.send(tester, 'what is the weather today?');
    expect(find.byKey(const Key('askodoxRoleNotice')), findsNothing);
    await h.send(tester, 'curry cut');
    expect(find.text('How much chicken do you need?'), findsNWidgets(2),
        reason: 'the aside did not drop the chicken deal; the next question is still pending');

    await h.send(tester, 'I want to sell my 2 bicycles in Vijayawada for 3000');
    expect(find.text('Active role changed: Buyer → Seller'), findsOneWidget);
    expect(h.listings.listed.single.intent, DealIntent.sell);
    expect(h.matches.deals, isEmpty);
  });

  testWidgets('Build 1236: completed chicken deal never ends without result cards',
      (tester) async {
    Future<void> runChicken(_Harness h) async {
      await h.pump(tester);
      await h.send(tester, 'I want to buy chicken in Vijayawada');
      for (final answer in ['curry cut', '1 kg', 'skinless', 'fresh', 'delivery']) {
        await h.send(tester, answer);
      }
    }

    // Backend 422 with nothing missing (request could not be published):
    // honest failure + retry, never placeholder cards.
    final rejected = _Harness(matches: _FakeMatchRepository([
      const DealNeedsDetailsException(domain: 'commerce', action: 'buy', missingFields: []),
    ]));
    await runChicken(rejected);
    expect(rejected.matches.deals, hasLength(1));
    expect(find.byKey(const Key('askodoxResultsFailed')), findsOneWidget);
    expect(find.textContaining('Search online'), findsNothing);

    // Backend 200 but zero rows from every source: said plainly.
    final empty = _Harness(matches: _FakeMatchRepository([
      const UniversalMatchResult(dealId: '777', matches: [], sourceStatus: {
        'askodox': 'no_results', 'nearby': 'no_results', 'online': 'unavailable', 'videos': 'unavailable',
      }),
    ]));
    await runChicken(empty);
    expect(find.byKey(const Key('askodoxResultsNone')), findsOneWidget);
    expect(find.textContaining('Not available right now: online stores, videos'), findsOneWidget);
    expect(find.textContaining('reviews on YouTube'), findsNothing);
  });

  testWidgets('43-inch TV: registered, used, deals, nearby shops, online and videos all appear in one chat',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '600', matches: [
          UniversalMatch(id: '12', title: 'Sony 43 inch TV', source: 'local', segment: 'registered', price: 28000),
          UniversalMatch(id: '13', title: '43 inch TV, 2 years used', source: 'local', segment: 'used', price: 14000),
          UniversalMatch(id: '14', title: '43 inch TV open box', source: 'local', segment: 'surplus', price: 22000),
          UniversalMatch(id: '15', title: 'LG 43 inch TV (one-time seller)', source: 'local', segment: 'individual', price: 26500),
          UniversalMatch(id: 'external-p1', title: 'Sri Electronics', source: 'external', segment: 'nearby_external',
              distanceKm: 1.2, destinationUrl: 'https://maps.google.com/?cid=1'),
          UniversalMatch(id: 'deals-0-shop', title: '43 inch TV festival offers', source: 'online', segment: 'deals',
              destinationUrl: 'https://shop.example/tv'),
          UniversalMatch(id: 'online-0-partner', title: 'TV at Partner', source: 'online', affiliate: true,
              disclosure: 'Affiliate link', destinationUrl: 'https://partner.example/tv'),
          UniversalMatch(id: 'video-0-youtube.com', title: '43 inch TV comparison', source: 'video',
              destinationUrl: 'https://youtube.com/watch?v=x'),
        ]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a 43 inch TV in Vijayawada');

    for (final heading in [
      'ASKODOX sellers', 'Individual sellers', 'Used / second-hand',
      'Surplus / clearance / open-box', 'Deals & offers', 'Nearby shops',
      'Online options', 'Videos & reviews',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    // Nearby shop not on ASKODOX: open its real map page / ask ASKODOX,
    // never a request to a seller who is not on ASKODOX.
    expect(find.byKey(const ValueKey('askodoxOpen-external-p1')), findsOneWidget);
    expect(find.text('Affiliate link'), findsOneWidget);
    // AI-first: no request buttons on first results.
    expect(find.text('Send request'), findsNothing);
    expect(find.text('Ask ASKODOX about this'), findsNWidgets(8));

    // A comparison question stays in the conversation (no new search) ...
    await h.send(tester, 'Which one is better, new or used?');
    expect(h.matches.deals, hasLength(1));
    expect(h.assistant.requests.last['message'], contains('Options already shown to the user'));
    expect(h.assistant.requests.last['message'], contains('43 inch TV, 2 years used'));
  });

  testWidgets('support is not pushed in normal chat; offered after the AI tried, and at once for payment problems',
      (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
    await h.pump(tester);
    await h.send(tester, 'hello there');
    await h.send(tester, 'The app is not working when I upload a photo');
    expect(find.text('Need more help? Contact ASKODOX Support'), findsNothing,
        reason: 'ASKODOX AI answers first');

    await h.send(tester, 'Still not working');
    expect(find.text('Need more help? Contact ASKODOX Support'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('askodoxSupportChat')));
    await tester.tap(find.byKey(const Key('askodoxSupportChat')));
    await _Harness.settle(tester);

    final escalation = h.support.escalations.single;
    expect(escalation['issue'], 'Still not working');
    expect(escalation['critical'], isFalse);
    final conversation = escalation['conversation']! as List;
    expect(conversation.first, {'role': 'user', 'text': 'hello there'});
    expect(conversation.length, 6, reason: 'the whole conversation travels with the case');
    expect((escalation['actionsTried']! as List), isNotEmpty);
    expect(escalation['activeRole'], 'Buyer');
    expect(find.byKey(const Key('askodoxSupportCaseCreated')), findsOneWidget);
    expect(find.text('WhatsApp Support'), findsOneWidget);
    expect(find.text('Call Support'), findsNothing, reason: 'not configured');
  });

  testWidgets('critical payment issue gets support immediately', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
    await h.pump(tester);
    await h.send(tester, 'Money deducted but order not confirmed');
    expect(find.text('Need more help? Contact ASKODOX Support'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('askodoxSupportChat')));
    await tester.tap(find.byKey(const Key('askodoxSupportChat')));
    await _Harness.settle(tester);
    expect(h.support.escalations.single['category'], 'PAYMENT');
    expect(h.support.escalations.single['critical'], isTrue);
  });

  testWidgets('ambiguous high-impact role switch asks first; stored roles stay', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
    await h.pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
    await h.send(tester, 'Can I sell things on ASKODOX?');

    expect(find.text('Switch to Seller mode?'), findsOneWidget);
    expect(container.read(askodoxRoleProvider).active, AskodoxUserRole.buyer);
    await _tapText(tester, 'Switch');
    expect(container.read(askodoxRoleProvider).active, AskodoxUserRole.seller);
    expect(container.read(askodoxRoleProvider).owned, {AskodoxUserRole.buyer});
    expect(find.text('Active role changed: Buyer → Seller'), findsOneWidget);

    await h.send(tester, 'I repair ACs in Vijayawada');
    expect(container.read(askodoxRoleProvider).active, AskodoxUserRole.serviceProvider);
    expect(find.text('Active role changed: Seller → Service Provider'), findsOneWidget);
  });

  testWidgets('History: New ask starts clean and reopening restores the exact conversation',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '901', matches: [_localMatch, _videoMatch]),
      ]),
    );
    await h.pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    await _tapText(tester, 'Ask ASKODOX about this');
    await _tapText(tester, 'Connect');
    expect(find.text('Request sent'), findsOneWidget);

    final saved = container.read(askodoxConversationArchiveProvider);
    expect(saved, hasLength(1));
    expect(saved.single.status, AskodoxConversationStatus.completed);
    expect(saved.single.title, 'I want to buy a mixer grinder in Vijayawada');

    container.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.newConversation();
    await _Harness.settle(tester);
    expect(find.text('I want to buy a mixer grinder in Vijayawada'), findsNothing);
    expect(container.read(universalDealControllerProvider).deal, isNull);

    container.read(askodoxChatRequestProvider.notifier).state =
        AskodoxChatRequest.restore(saved.single.id);
    await _Harness.settle(tester);

    expect(find.text('I want to buy a mixer grinder in Vijayawada'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
    expect(find.text('Request sent'), findsOneWidget, reason: 'deal state restored');
    expect(find.text('Videos & reviews'), findsOneWidget);
    expect(container.read(universalDealControllerProvider).deal?.subject, contains('mixer grinder'));
    expect(h.matches.deals, hasLength(1), reason: 'restoring never re-runs matching');
  });

  testWidgets('ambiguous "battery TV" asks ONE clarification before any search, then searches the chosen product',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '700', matches: [_onlineMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a 14 inch battery TV in Vijayawada');

    expect(find.textContaining('Do you mean a portable TV that runs on a battery'), findsOneWidget);
    expect(find.byKey(const Key('askodoxClarificationOptions')), findsOneWidget);
    expect(h.matches.deals, isEmpty, reason: 'no guessed search before the need is clear');

    await _tapText(tester, 'Portable battery TV');

    expect(h.matches.deals.single.subject, 'portable rechargeable battery TV');
    expect(find.byKey(const Key('askodoxClarificationOptions')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxChatResults-3')), findsOneWidget);
  });

  testWidgets('Telugu "నాకు battery TV కావాలి" is clarified first, then the usual questions continue',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '701', matches: [_onlineMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'నాకు battery TV కావాలి');
    expect(find.textContaining('Do you mean a portable TV'), findsOneWidget);
    expect(h.matches.deals, isEmpty);

    await h.send(tester, 'inverter backup');
    expect(h.matches.deals, isEmpty, reason: 'size still needed for a TV');
    await h.send(tester, '32 inch');
    await h.send(tester, 'Vijayawada');

    expect(h.matches.deals, hasLength(1));
    expect(h.matches.deals.single.subject, 'low power TV for inverter battery backup');
  });

  testWidgets('real multi-source results coexist; actual video opens inside ASKODOX and back keeps the chat',
      (tester) async {
    const video = UniversalMatch(
      id: 'video-0-youtube.com',
      title: 'Samsung 43 inch Crystal 4K TV review',
      source: 'video',
      imageUrl: 'https://i.ytimg.com/vi/AbCdEf12345/hqdefault.jpg',
      sourceName: 'Tech Telugu',
      duration: '08:12',
      destinationUrl: 'https://www.youtube.com/watch?v=AbCdEf12345',
    );
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '800', matches: [
          UniversalMatch(id: '21', title: 'Sony 43 inch TV', source: 'local', segment: 'registered', price: 28000),
          UniversalMatch(id: '22', title: '43 inch TV used 1 year', source: 'local', segment: 'used', price: 15000),
          UniversalMatch(id: 'online-0-shop.example', title: 'Samsung 43 inch Crystal 4K', source: 'online',
              price: 27990, sourceName: 'shop.example', imageUrl: 'https://imgs.example/tv.jpg',
              destinationUrl: 'https://shop.example/tv'),
          video,
        ], sourceStatus: {'askodox': 'ok', 'nearby': 'no_results', 'online': 'ok', 'videos': 'ok'}),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a 43 inch TV in Vijayawada');

    for (final heading in ['ASKODOX sellers', 'Used / second-hand', 'Online options', 'Videos & reviews']) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.textContaining('No results from: nearby shops'), findsOneWidget);
    expect(find.text('shop.example'), findsOneWidget, reason: 'real source name');
    expect(find.text('₹27990'), findsOneWidget, reason: 'real returned price');
    expect(find.text('Tech Telugu'), findsOneWidget, reason: 'real creator');
    expect(find.text('08:12'), findsOneWidget);
    expect(find.textContaining('reviews on YouTube'), findsNothing);
    expect(find.textContaining('Search online for'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('askodoxVideoThumb-video-0-youtube.com')));
    await tester.tap(find.byKey(const ValueKey('askodoxVideoThumb-video-0-youtube.com')));
    await tester.pumpAndSettle();
    expect(find.byType(AskodoxVideoViewerScreen), findsOneWidget);
    expect(h.embeddedVideos.single.toString(),
        'https://www.youtube-nocookie.com/embed/AbCdEf12345?autoplay=1&playsinline=1&rel=0');
    expect(find.byKey(const Key('askodoxVideoOpenOriginal')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AskodoxVideoViewerScreen), findsNothing);
    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget, reason: 'same chat after back');

    // Ask about the video from the viewer: stays in the AI conversation.
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxVideoThumb-video-0-youtube.com')));
    await tester.tap(find.byKey(const ValueKey('askodoxVideoThumb-video-0-youtube.com')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxVideoAsk')));
    await _Harness.settle(tester);
    await tester.pumpAndSettle();
    expect(h.assistant.requests.last['message'], contains('Samsung 43 inch Crystal 4K TV review'));
    expect(h.matches.deals, hasLength(1), reason: 'asking about a video never re-runs matching');
  });

  group('Main Chat voice uses the ASKODOX/Sarvam pipeline', () {
    const channel = MethodChannel('com.askodox.app/device');
    final calls = <MethodCall>[];

    /// Simulated native recorder: `levels` are the amplitudes returned by
    /// successive voiceRecordingLevel polls (one per 200 ms sample).
    void mockRecorder({
      List<int> levels = const [],
      Object? startResult = true,
      PlatformException? startError,
      String? path = '/cache/askodox_voice_1.m4a',
      Future<Object?> Function(MethodCall call)? extra,
    }) {
      calls.clear();
      var sample = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'startVoiceRecording':
            if (startError != null) throw startError;
            return startResult;
          case 'voiceRecordingLevel':
            if (sample >= levels.length) return levels.isEmpty ? 0 : levels.last;
            return levels[sample++];
          case 'stopVoiceRecording':
            return path;
          default:
            return extra == null ? null : await extra(call);
        }
      });
    }

    List<String> methods() => [for (final c in calls) c.method];
    int levelPolls() => methods().where((m) => m == 'voiceRecordingLevel').length;

    List<int> speech(Duration d, {int level = 5000}) =>
        List.filled(d.inMilliseconds ~/ 200, level);
    List<int> quiet(Duration d, {int level = 150}) =>
        List.filled(d.inMilliseconds ~/ 200, level);

    Future<void> runFor(WidgetTester tester, Duration d) async {
      for (var i = 0; i < d.inMilliseconds ~/ 200; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await _Harness.settle(tester);
    }

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    testWidgets('long Telugu speech with natural pauses keeps recording, stops on genuine silence and replies in Telugu voice',
        (tester) async {
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        // ~25 s of speech with 2-second thinking pauses: the old native loop
        // stopped at ~10 s; this must keep recording.
        for (var i = 0; i < 5; i++) ...[
          ...speech(const Duration(seconds: 3), level: 1200), // soft voice
          ...quiet(const Duration(seconds: 2), level: 400),
        ],
        ...quiet(const Duration(seconds: 4)),
      ]);
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: 'నాకు విజయవాడలో చికెన్ కావాలి',
        assistant: _Assistant((_) => {
              'reply': 'సరే, ఎంత చికెన్ కావాలి?',
              'domain': 'FOOD',
              'transactional': false,
              'confidence': 0.9,
              'source': 'universal_ai',
            }),
      );
      await h.pump(tester, locale: 'te');
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 20));
      expect(methods(), isNot(contains('stopVoiceRecording')),
          reason: 'still speaking at 20 s: no premature stop');

      await runFor(tester, const Duration(seconds: 12));

      expect(methods(), isNot(contains('startVoiceSearch')), reason: 'never the system recognizer');
      expect(methods().where((m) => m == 'stopVoiceRecording'), hasLength(1));
      expect(levelPolls(), greaterThan(125), reason: 'recorded for well over 25 seconds');
      expect(h.voice.calls.single, ('/cache/askodox_voice_1.m4a', 'te'));
      expect(find.text('నాకు విజయవాడలో చికెన్ కావాలి'), findsOneWidget);
      final speak = calls.lastWhere((c) => c.method == 'speakReply');
      expect((speak.arguments as Map)['text'], 'సరే, ఎంత చికెన్ కావాలి?');
      expect((speak.arguments as Map)['languageCode'], 'te');
    });

    testWidgets('English question gets an English voice reply even in the Telugu UI',
        (tester) async {
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        ...speech(const Duration(seconds: 12)),
        ...quiet(const Duration(seconds: 4)),
      ]);
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: 'I want to know the best time to visit Araku valley',
        assistant: _Assistant((_) => {
              'reply': 'October to March is the best time to visit Araku.',
              'domain': 'GENERAL',
              'transactional': false,
              'confidence': 0.9,
              'source': 'universal_ai',
            }),
      );
      await h.pump(tester, locale: 'te');
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 18));

      final speak = calls.lastWhere((c) => c.method == 'speakReply');
      expect((speak.arguments as Map)['languageCode'], 'en');
      expect((speak.arguments as Map)['text'], 'October to March is the best time to visit Araku.');
    });

    testWidgets('pressing Stop ends the recording immediately and sends it', (tester) async {
      mockRecorder(levels: speech(const Duration(seconds: 60)));
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: 'I need AC repair',
      );
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 3));
      expect(find.byTooltip('Stop and send'), findsOneWidget);

      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await _Harness.settle(tester);

      expect(methods(), contains('stopVoiceRecording'));
      expect(h.voice.calls, hasLength(1));
      expect(find.text('I need AC repair'), findsOneWidget);
    });

    testWidgets('no speech at all is reported after the long timeout, chat untouched', (tester) async {
      mockRecorder(levels: quiet(const Duration(seconds: 30)));
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 10));
      expect(methods(), isNot(contains('cancelVoiceRecording')), reason: 'not at 10 s');
      await runFor(tester, const Duration(seconds: 6));

      expect(methods(), contains('cancelVoiceRecording'));
      expect(find.text('I did not hear anything. Please try again.'), findsOneWidget);
      expect(h.voice.calls, isEmpty);
      expect(h.assistant.requests, isEmpty);
    });

    testWidgets('cancel discards the recording without sending anything', (tester) async {
      mockRecorder(levels: speech(const Duration(seconds: 60)));
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('askodoxVoiceCancel')));
      await _Harness.settle(tester);

      expect(methods(), contains('cancelVoiceRecording'));
      expect(methods(), isNot(contains('stopVoiceRecording')));
      expect(h.voice.calls, isEmpty);
      expect(find.byIcon(Icons.mic_rounded), findsWidgets);
    });

    testWidgets('microphone permission denied shows a clear error and no fallback recognizer',
        (tester) async {
      mockRecorder(startError: PlatformException(code: 'mic_denied'));
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await _Harness.settle(tester);

      expect(find.textContaining('Microphone permission is off'), findsOneWidget);
      expect(methods(), ['startVoiceRecording']);
      expect(h.voice.calls, isEmpty);
    });

    testWidgets('transcription failure is reported and nothing is sent', (tester) async {
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        ...speech(const Duration(seconds: 2)),
        ...quiet(const Duration(seconds: 4)),
      ]);
      final failing = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await failing.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 8));
      expect(find.textContaining('could not understand'), findsOneWidget);
      expect(failing.assistant.requests, isEmpty);
    });

    testWidgets('typing a new message interrupts a spoken reply', (tester) async {
      mockRecorder();
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await h.send(tester, 'hello');
      expect(methods(), contains('stopSpeaking'));
      expect(methods(), isNot(contains('speakReply')), reason: 'typed turns are not spoken');
    });

    testWidgets('Listening panel shows live level bars driven by real amplitude, elapsed time and a separate Stop',
        (tester) async {
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        ...speech(const Duration(seconds: 2), level: 200),
        ...speech(const Duration(seconds: 3), level: 9000),
        ...speech(const Duration(seconds: 30), level: 9000),
      ]);
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxVoicePanel')), findsOneWidget);

      double lastBar() => tester.getSize(find.byKey(const ValueKey('askodoxLevelBar-23'))).height;
      Future<void> samples(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pump(const Duration(milliseconds: 200)); // bar animation
      }

      await samples(11); // 3 calibration + 8 soft (200) samples
      expect(find.text('Listening…'), findsOneWidget);
      final quietHeight = lastBar();
      await samples(4); // now loud (9000) speech
      final loudHeight = lastBar();
      expect(loudHeight, greaterThan(quietHeight + 10), reason: 'bars react to the speaker');
      expect(find.text('00:03'), findsOneWidget);
      expect(find.byKey(const Key('askodoxVoiceStop')), findsOneWidget);

      await tester.tap(find.byKey(const Key('askodoxVoiceStop')));
      await _Harness.settle(tester);
      expect(methods(), contains('stopVoiceRecording'));
    });

    testWidgets('Listening → Understanding → Thinking → Speaking → idle, with Sarvam Bulbul reply audio',
        (tester) async {
      final playing = Completer<Object?>();
      mockRecorder(
        levels: [
          ...quiet(const Duration(milliseconds: 600)),
          ...speech(const Duration(seconds: 2)),
          ...quiet(const Duration(seconds: 4)),
        ],
        extra: (call) async => call.method == 'playReplyAudio' ? playing.future : null,
      );
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: 'hello ASKODOX',
        assistant: _Assistant((_) => {
              'reply': 'Hello! How can I help?',
              'domain': 'GENERAL',
              'transactional': false,
              'confidence': 0.9,
              'source': 'universal_ai',
            }),
      );
      h.voice.hold = Completer<void>();
      h.assistant.hold = Completer<void>();
      h.replySpeech.audio = Uint8List.fromList([79, 103, 103, 83]);
      await h.pump(tester);
      final state = tester.state(find.byType(AskodoxPrimaryHomeScreen)) as dynamic;

      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 1));
      expect(find.text('Listening…'), findsOneWidget);

      await runFor(tester, const Duration(seconds: 5));
      expect(find.text('Understanding…'), findsOneWidget);

      h.voice.hold!.complete();
      await _Harness.settle(tester);
      expect(find.text('Thinking…'), findsOneWidget);

      h.assistant.hold!.complete();
      await _Harness.settle(tester);
      expect(find.text('Speaking…'), findsOneWidget);
      final play = calls.lastWhere((c) => c.method == 'playReplyAudio');
      expect((play.arguments as Map)['bytes'], [79, 103, 103, 83]);
      expect(methods(), isNot(contains('speakReply')), reason: 'Sarvam audio, not device TTS');
      expect(h.replySpeech.calls.single, ('Hello! How can I help?', 'en'));

      playing.complete(true);
      await _Harness.settle(tester);
      expect(find.byKey(const Key('askodoxVoicePanel')), findsNothing);
      expect(state.lastReplyVoiceEngine, 'sarvam_bulbul_v3');
    });

    testWidgets('without Sarvam audio the reply falls back to device TTS and says so', (tester) async {
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        ...speech(const Duration(seconds: 2)),
        ...quiet(const Duration(seconds: 4)),
      ]);
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: 'నమస్తే',
        assistant: _Assistant((_) => {
              'reply': 'నమస్తే! మీకు ఏమి కావాలి?',
              'domain': 'GENERAL',
              'transactional': false,
              'confidence': 0.9,
              'source': 'universal_ai',
            }),
      );
      await h.pump(tester, locale: 'te');
      final state = tester.state(find.byType(AskodoxPrimaryHomeScreen)) as dynamic;
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 8));

      expect(h.replySpeech.calls.single.$2, 'te');
      final speak = calls.lastWhere((c) => c.method == 'speakReply');
      expect((speak.arguments as Map)['languageCode'], 'te');
      expect(state.lastReplyVoiceEngine, 'device');
    });

    testWidgets('starting the mic while ASKODOX is speaking interrupts the reply', (tester) async {
      final playing = Completer<Object?>();
      mockRecorder(
        levels: [
          ...quiet(const Duration(milliseconds: 600)),
          ...speech(const Duration(seconds: 2)),
          ...quiet(const Duration(seconds: 4)),
          ...speech(const Duration(seconds: 60)),
        ],
        extra: (call) async {
          if (call.method == 'playReplyAudio') return playing.future;
          if (call.method == 'stopSpeaking' && !playing.isCompleted) playing.complete(false);
          return null;
        },
      );
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]), voiceTranscript: 'hi');
      h.replySpeech.audio = Uint8List.fromList([1, 2, 3]);
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 8));
      expect(find.text('Speaking…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('askodoxVoiceButton')));
      await runFor(tester, const Duration(seconds: 1));
      expect(methods(), contains('stopSpeaking'));
      expect(find.text('Listening…'), findsOneWidget);
    });
  });

  test('live repository never substitutes demo matches and parses rich result fields', () async {
    final empty = ApiUniversalMatchRepository(_ScriptedClient({'/deals': <String, Object?>{}}),
        appUserId: 'app-1', authToken: 't');
    final deal = UniversalDeal(
      rawText: 'buy mixer',
      intent: DealIntent.buy,
      partyA: const DealPartyRequirement(side: DealSide.demand, role: 'buyer', action: 'buy'),
      partyB: const DealPartyRequirement(side: DealSide.supply, role: 'seller', action: 'sell'),
      subject: 'mixer',
    );
    await expectLater(empty.createAndMatch(deal), throwsStateError);

    final live = ApiUniversalMatchRepository(
      _ScriptedClient({
        '/deals': {'id': 9},
        '/deals/9/matches': {
          'matches': [
            {'id': 'app-s', 'match_source': 'interest', 'rating_average': 4.0, 'review_count': 3},
            {'id': 'online-0', 'source': 'online', 'destination_url': 'https://a.b', 'affiliate': true},
          ],
        },
      }),
      appUserId: 'app-1',
      authToken: 't',
    );
    final result = await live.createAndMatch(deal);
    expect(result.dealId, '9');
    final interest = result.matches.firstWhere((m) => m.id == 'app-s');
    expect(interest.source, 'interest');
    expect(interest.ratingAverage, 4.0);
    expect(interest.reviewCount, 3);
    expect(result.matches.firstWhere((m) => m.id == 'online-0').affiliate, isTrue);
  });
}

class _ScriptedClient implements ApiClient {
  _ScriptedClient(this.routes);
  final Map<String, Map<String, Object?>> routes;

  Future<ApiResult<T>> _reply<T>(String path) async =>
      ApiSuccess<T>((routes[path] ?? <String, Object?>{}) as T);

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path);

  @override
  Future<ApiResult<T>> post<T>(String path,
          {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path);

  @override
  Future<ApiResult<T>> put<T>(String path,
          {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path);

  @override
  Future<ApiResult<T>> patch<T>(String path,
          {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path);

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path);

  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes,
          required String fileName,
          ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess<Uri>(Uri.parse('https://files.example/$fileName'));
}
