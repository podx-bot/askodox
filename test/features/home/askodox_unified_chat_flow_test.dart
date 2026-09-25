import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/config/environment.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/orders/data/order_repository.dart';
import 'package:podx/features/selling/data/seller_listing_repository.dart';
import 'package:podx/services/in_app_assistant_service.dart';
import 'package:podx/services/real_product_match_service.dart';
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

  InAppAssistantService service() => InAppAssistantService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
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

// -------------------------------------------------------------- harness --

class _Harness {
  _Harness({
    required this.matches,
    _Assistant? assistant,
    List<Map<String, Object?>> products = const [],
    this.backend = BackendProvider.rest,
  })  : assistant = assistant ?? _Assistant(),
        productSearch = _productSearch(products);

  final _FakeMatchRepository matches;
  final _Assistant assistant;
  final RealProductMatchService productSearch;
  final BackendProvider backend;
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
    expect(find.text('Local matches'), findsOneWidget);
    expect(find.text('82% match'), findsOneWidget);
    expect(find.text('★ 4.5 (2)'), findsOneWidget);
    expect(find.text('Videos & reviews'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Phone/contact stays hidden until they accept.'), findsOneWidget);
    expect(find.textContaining('app-seller-1'), findsNothing);

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
    expect(find.text('Connect'), findsOneWidget);
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
    // Even while matching is down the user is not left empty-handed.
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('askodoxResultsRetry')));
    await tester.tap(find.byKey(const Key('askodoxResultsRetry')));
    await _Harness.settle(tester);

    expect(find.byKey(const Key('askodoxResultsFailed')), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
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

    expect(find.text('You are now acting as: Seller for this request'), findsOneWidget);
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
