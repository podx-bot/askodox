import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/companion/companion_voice.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/config/environment.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/growth/data/partner_tracking.dart';
import 'package:podx/features/growth/data/benefits.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/orders/data/order_repository.dart';
import 'package:podx/features/selling/data/seller_listing_repository.dart';
import 'package:podx/services/in_app_assistant_service.dart';
import 'package:podx/services/real_product_match_service.dart';
import 'package:podx/features/home/data/greeting_repository.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';
import 'dart:async';

import 'package:podx/features/home/presentation/video_viewer_screen.dart';
import 'package:podx/services/reply_speech_service.dart';
import 'package:podx/services/support_escalation_service.dart';
import 'package:podx/services/voice_transcription_service.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/application/saved_options.dart';
import 'package:podx/features/profile/data/user_profile_repository.dart';
import 'package:podx/features/selling/data/catalogue_repository.dart';
import 'package:podx/shared/widgets/app_shell.dart';
import 'package:podx/features/companion/companion_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- fakes --

class _FakeMatchRepository implements UniversalMatchRepository {
  _FakeMatchRepository(this.responses);

  /// Each call to createAndMatch consumes the next entry: a
  /// [UniversalMatchResult] or an [Object] to throw.
  final List<Object> responses;
  final List<UniversalDeal> deals = [];
  final List<(String, String)> accepted = [];

  final List<Map<String, Object?>?> traces = [];

  @override
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal, {Map<String, Object?>? trace}) async {
    traces.add(trace);
    deals.add(deal);
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    if (next is UniversalMatchResult) return next;
    throw next;
  }

  /// Every link the customer opened (destination URLs, in order).
  final List<String> clicks = [];

  @override
  Future<void> recordExternalClick({required UniversalMatch match, required String destinationUrl}) async {
    clicks.add(destinationUrl);
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
  final List<Map<String, Object?>?> contexts = [];
  final List<String?> questions = [];
  /// When set, placing returns a real order id so the chat tracks the deal.
  String? orderId;

  @override
  Future<OrderActionResult> placeOrder({
    required String productId,
    double? quantity,
    String? buyerNote,
    Map<String, Object?>? requestContext,
    String? question,
  }) async {
    placed.add(productId);
    contexts.add(requestContext);
    questions.add(question);
    final id = orderId;
    return OrderActionResult(
      success: true,
      order: id == null
          ? null
          : Order(id: id, buyerUserId: '', sellerUserId: '', productId: productId, productTitle: 'x', status: 'PLACED'),
    );
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

/// Scripted universal deal lifecycle (test fixture, not production data).
class _FakeLifecycle extends OrderLifecycleRepository {
  _FakeLifecycle() : super(MockApiClient());

  String status = 'PLACED';
  String kind = 'product';
  String paymentStatus = 'NOT_STARTED';
  double? price = 24999;
  final messages = <OrderMessage>[];
  final calls = <String>[];

  List<String> get _actions {
    final last = messages.isEmpty ? null : messages.last;
    return [
      if (status == 'PLACED') ...['ask_seller', 'offer_price', 'cancel'],
      if (last?.kind == 'COUNTER_OFFER') ...['accept_offer', 'decline_offer'],
      if (const {'DELIVERED', 'SERVICE_COMPLETED', 'RESOLVED'}.contains(status)) ...['confirm_completion', 'report_problem'],
      if (status == 'REJECTED') 'see_alternatives',
      if (status == 'CLOSED') 'review',
    ];
  }

  OrderDetail _detail() => OrderDetail(
        order: Order(id: '501', buyerUserId: '', sellerUserId: '', productId: '42', productTitle: 'TV',
            status: status, kind: kind, paymentState: paymentStatus, price: price),
        messages: List.of(messages),
        actions: _actions,
        awaiting: status == 'PLACED' ? 'seller' : 'buyer',
      );

  @override
  Future<OrderDetail> detail(String orderId) async => _detail();

  @override
  Future<OrderDetail> message(String orderId, String kind, {String? text, double? amount}) async {
    calls.add('$kind:${amount?.toStringAsFixed(0) ?? text}');
    if (kind == 'ACCEPT_OFFER') price = messages.lastWhere((m) => m.kind == 'COUNTER_OFFER').amount;
    messages.add(OrderMessage(fromRole: 'buyer', kind: kind, text: text, amount: amount));
    return _detail();
  }

  @override
  Future<OrderDetail> confirm(String orderId) async {
    calls.add('confirm');
    status = 'CLOSED';
    return _detail();
  }

  @override
  Future<OrderDetail> problem(String orderId,
      {required String issue, String category = 'DELIVERY', List<String> aiAttempts = const []}) async {
    calls.add('problem:$issue');
    status = 'DISPUTED';
    return _detail();
  }

  @override
  Future<List<Map<String, Object?>>> alternatives(String orderId) async => [
        {'id': '77', 'title': 'Other 43 inch TV', 'source': 'local', 'match_source': 'registered', 'price': 25500},
      ];
}

class _FakeSellerListingRepository implements SellerListingRepository {
  final List<UniversalDeal> listed = [];
  SellerListingResult? next;

  @override
  Future<SellerListingResult> createListing(UniversalDeal deal) async {
    listed.add(deal);
    return next ?? const SellerListingResult(success: true);
  }
}

class _FakeGrowth implements GrowthRepository {
  final List<({String category, String area, String? dealId})> referrals = [];
  bool signedIn = true;

  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async => const [];

  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async =>
      const AskodoxRouteQuote(distanceKm: 12.5, durationMinutes: 34);

  @override
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId}) async {
    if (!signedIn) return null;
    referrals.add((category: category, area: area, dealId: dealId));
    return const AskodoxReferral(code: 'ASK1A2B3C', shareText: 'Join ASKODOX -- use code ASK1A2B3C');
  }

  @override
  Future<AskodoxCatalogDraft?> draftListing({String text = '', Map<String, Object?>? imageAnalysis,
          Map<String, Object?>? videoAnalysis}) async =>
      null;

  @override
  Future<int?> publishDraft(int draftId, Map<String, Object?> reviewed) async => null;

  List<AskodoxLead> leadList = const [];
  final List<String> interests = [];

  @override
  Future<List<AskodoxLead>> leads() async => leadList;

  @override
  Future<bool> expressInterest(String requestId) async {
    interests.add(requestId);
    return true;
  }
}

/// Scripted `/api/in-app/assistant`: `null` means the AI is unavailable
/// (deterministic fallback path); otherwise the JSON decision to return.
class _Assistant {
  _Assistant([this.decide]);
  final Map<String, Object?>? Function(String message)? decide;
  final List<Map<String, dynamic>> requests = [];
  Completer<void>? hold;

  /// English deal question -> localized text the fake /localize returns.
  final Map<String, String> localized = {};

  InAppAssistantService service() => InAppAssistantService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/localize')) {
            final text = localized[body['text']];
            return text == null
                ? http.Response('', 503)
                : http.Response(jsonEncode({'text': text, 'localized': true}), 200,
                    headers: {'content-type': 'application/json; charset=utf-8'});
          }
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
const _registeredTv = UniversalMatch(
  id: '42',
  title: '43 inch portable battery TV',
  subtitle: 'Sony, rechargeable',
  source: 'local',
  segment: 'registered',
  price: 24999,
  locationLabel: 'Vijayawada',
);
const _registeredTv2 = UniversalMatch(
  id: '43',
  title: '43 inch battery backup TV',
  source: 'local',
  segment: 'registered',
  price: 27999,
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
  Future<Uint8List?> sarvamAudio(String text, {required String locale, String voice = 'automatic'}) async {
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

  Map<String, Object?>? caseReply = {'status': 'RESOLVED', 'resolution_note': 'Engineer reset your account'};

  @override
  Future<Map<String, Object?>?> caseStatus(String caseId, {String? authToken}) async => caseReply;
}

class _FakeCatalogue implements AskodoxCatalogueRepository {
  final published = <(String, List<AskodoxCatalogueEntry>, String?, String?)>[];
  final requested = <String>[];

  static final grocery = AskodoxCatalogueTemplate.fromJson({
    'key': 'grocery',
    'name': {'en': 'Grocery (kirana)', 'te': 'కిరాణా', 'hi': 'किराना'},
    'categories': [
      {
        'key': 'dals',
        'name': {'en': 'Dals & pulses', 'te': 'పప్పులు', 'hi': 'दालें'},
        'items': [
          {'key': 'dals.toor', 'name': {'en': 'Toor dal', 'te': 'కంది పప్పు', 'hi': 'तूर दाल'}, 'unit': 'kg', 'sizes': ['500 g', '1 kg']},
        ],
      },
      {
        'key': 'oils_ghee',
        'name': {'en': 'Oils & ghee', 'te': 'నూనెలు & నెయ్యి', 'hi': 'तेल और घी'},
        'items': [
          {'key': 'oils_ghee.ghee', 'name': {'en': 'Ghee', 'te': 'నెయ్యి', 'hi': 'घी'}, 'unit': 'L', 'sizes': ['500 ml']},
        ],
      },
    ],
  });

  @override
  String? get authToken => 'token';

  @override
  Future<AskodoxCatalogueTemplate?> template(String key) async {
    requested.add(key);
    return key == 'grocery' ? grocery : null;
  }

  @override
  Future<List<({String key, Map<String, String> names, int items})>> templates() async => [
        (key: 'grocery', names: const {'en': 'Grocery (kirana)'}, items: 2),
      ];

  @override
  Future<AskodoxCataloguePublishResult> publish(String key, List<AskodoxCatalogueEntry> entries,
      {String? businessName, String? businessAddress, String language = 'en'}) async {
    published.add((key, entries, businessName, businessAddress));
    final priced = entries.where((e) => e.price != null).length;
    return AskodoxCataloguePublishResult(published: priced, drafts: entries.length - priced);
  }
}

class _FakeProfile implements AskodoxUserProfileRepository {
  AskodoxUserProfile? stored = const AskodoxUserProfile(
      userId: 'app-phone-919999999999', name: 'Lakshmi', address: 'Vuyyuru', businessName: 'Sri Lakshmi Kirana');

  @override
  String? get authToken => 'token';

  @override
  Future<AskodoxUserProfile?> load() async => stored;

  @override
  Future<AskodoxUserProfile?> save(Map<String, Object?> fields) async => stored;

  @override
  Future<AskodoxUserProfile?> setPhoto(Uint8List? jpeg) async => stored;
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
  final lifecycle = _FakeLifecycle();
  final listings = _FakeSellerListingRepository();
  final growth = _FakeGrowth();
  final partnerTracker = _FakePartnerTracker();
  final picker = _FakePicker();
  final benefits = _FakeBenefits();
  final attachments = _FakeAttachments();
  final catalogue = _FakeCatalogue();
  final profile = _FakeProfile();

  /// Optional API client (video explain / tracking) -- the real-content
  /// proof render replays the branch backend's real answers through it.
  ApiClient? api;

  /// Optional theme (the proof render adds a Telugu fallback font).
  ThemeData? theme;

  Future<void> pump(WidgetTester tester, {String? locale}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (locale != null) 'askodox.locale': locale,
    });
    tester.view.physicalSize = const Size(1440, 5200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await settle(tester);
  }

  /// A new app process: a brand-new ProviderScope over the same persisted
  /// storage (SharedPreferences survives, in-memory state does not).
  Future<void> relaunch(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    _scopeKey = UniqueKey();
    await tester.pumpWidget(_app());
    await settle(tester);
  }

  /// Same session: Main Chat is unmounted (another screen) and mounted again
  /// inside the SAME ProviderScope.
  Future<void> navigateAway(WidgetTester tester) async {
    await tester.pumpWidget(_app(home: const Text('Explore screen')));
    await settle(tester);
  }

  Future<void> navigateBack(WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await settle(tester);
  }

  Key _scopeKey = UniqueKey();

  /// Sending a request / contacting a seller needs identity (the backend
  /// rejects guests with 401); browsing never does.
  bool signedIn = true;

  /// When true the app runs under a GoRouter with a stand-in sign-in screen
  /// at /onboarding (the real one is phone OTP), so "sign in, then resume
  /// the exact action" is exercised end to end.
  bool withRouter = false;

  /// When true Main Chat runs inside the real app shell (header + bottom
  /// navigation) -- used by the Home render.
  bool withShell = false;

  /// Sign-off texts the fake /api/greeting returns per language.
  final Map<String, String> signoffs = {};

  Widget _app({Widget home = const Scaffold(body: AskodoxPrimaryHomeScreen())}) {
    return ProviderScope(
      key: _scopeKey,
      overrides: [
        appConfigProvider.overrideWithValue(_config(backend)),
        authSessionProvider.overrideWith((ref) => _TestAuth(ref.watch(sessionManagerProvider), signedIn: signedIn)),
        universalMatchRepositoryProvider.overrideWithValue(matches),
        orderRepositoryProvider.overrideWithValue(orders),
        orderLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        sellerListingRepositoryProvider.overrideWithValue(listings),
        growthRepositoryProvider.overrideWithValue(growth),
        askodoxPartnerTrackerProvider.overrideWithValue(partnerTracker),
        askodoxMediaPickerProvider.overrideWithValue(picker),
        askodoxBenefitsRepositoryProvider.overrideWithValue(benefits),
        chatAttachmentServiceProvider.overrideWithValue(attachments),
        askodoxCatalogueRepositoryProvider.overrideWithValue(catalogue),
        askodoxUserProfileRepositoryProvider.overrideWithValue(profile),
        askodoxAssistantServiceProvider.overrideWithValue(assistant.service()),
        askodoxRealProductMatchServiceProvider.overrideWithValue(productSearch),
        askodoxVoiceTranscriptionServiceProvider.overrideWithValue(voice),
        askodoxSupportEscalationServiceProvider.overrideWithValue(support),
        askodoxReplySpeechServiceProvider.overrideWithValue(replySpeech),
        if (api != null) apiClientProvider.overrideWithValue(api!),
        greetingRepositoryProvider.overrideWithValue(GreetingRepository(_GreetingApi(signoffs))),
        askodoxVideoEmbedBuilderProvider.overrideWithValue((uri) {
          embeddedVideos.add(uri);
          return Text('EMBED $uri');
        }),
      ],
      child: withShell
          ? MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: theme,
              routerConfig: GoRouter(routes: [
                StatefulShellRoute.indexedStack(
                  builder: (context, state, shell) => AppShell(shell: shell),
                  branches: [
                    StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => home)]),
                    for (final path in ['/search', '/watchlist', '/updates', '/profile'])
                      StatefulShellBranch(
                          routes: [GoRoute(path: path, builder: (_, __) => Center(child: Text(path)))]),
                  ],
                ),
              ]),
            )
          : withRouter
          ? MaterialApp.router(
              routerConfig: GoRouter(routes: [
                GoRoute(path: '/', builder: (_, __) => home),
                GoRoute(path: '/onboarding', builder: (_, __) => _FakeSignInScreen(onSignIn: () => growth.signedIn = true)),
              ]),
            )
          : MaterialApp(home: home, theme: theme, debugShowCheckedModeBanner: theme == null),
    );
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

class _TestAuth extends AuthController {
  _TestAuth(super.manager, {required bool signedIn}) {
    if (signedIn) signInForTest();
  }

  void signInForTest() {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919876500000', role: UserRole.buyer, displayName: 'Test buyer'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 'test-session-token',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _FakeBenefits extends AskodoxBenefitsRepository {
  _FakeBenefits() : super(MockApiClient(), authToken: 'test-session-token');
  AskodoxClaimResult? scratchReward;
  AskodoxClaimResult claimResult = const AskodoxClaimResult(code: 'SAVE500A', value: 500, kind: 'coupon');
  final scratched = <String>[];
  final claimed = <int>[];
  final opened = <int>[];

  @override
  Future<Map<String, Object?>?> open(int campaignId) async {
    opened.add(campaignId);
    return const {};
  }

  @override
  Future<AskodoxClaimResult> claim(int campaignId, {double? orderValue}) async {
    claimed.add(campaignId);
    return claimResult;
  }

  @override
  Future<AskodoxClaimResult?> scratch(String orderId) async {
    scratched.add(orderId);
    return scratchReward;
  }
}

class _GreetingApi extends MockApiClient {
  _GreetingApi(this.signoffs);
  final Map<String, String> signoffs;
  final paths = <String>[];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    paths.add(path);
    final q = Uri.parse(path).queryParameters;
    final text = q['kind'] == 'signoff' ? signoffs[q['language']] : null;
    return ApiSuccess(<String, Object?>{
      'greeting': text == null ? null : {'text': text, 'language_matched': true},
    } as T);
  }
}

class _FakePicker implements AskodoxMediaPicker {
  final sources = <String>[];
  List<ChatAttachment> next = const [];

  @override
  Future<List<ChatAttachment>> pick(String source) async {
    sources.add(source);
    return next;
  }
}

/// Stands in for POST /api/attachments/analyze: records the ACTUAL bytes it
/// was given and answers with facts like the backend does.
class _FakeAttachments implements ChatAttachmentService {
  final calls = <({ChatAttachment attachment, String userText, String language})>[];
  final failures = <ChatAttachmentException>[];
  Completer<void>? hold;

  @override
  Future<ChatAttachmentResult> analyze(ChatAttachment attachment,
      {required String userText, required String language, String conversationId = ''}) async {
    calls.add((attachment: attachment, userText: userText, language: language));
    if (hold != null) await hold!.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return ChatAttachmentResult(
      id: 'att_${calls.length}',
      kind: attachment.kind,
      facts: attachment.isVideo
          ? 'Video shows: a scooter with a flat tyre'
          : 'Shows: pressure cooker\nBrand: Prestige\nVisible text: Prestige 5L',
      analysis: const {'subject': 'pressure cooker', 'brand': 'Prestige'},
    );
  }
}

final _photoBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

class _FakePartnerTracker extends AskodoxPartnerTracker {
  _FakePartnerTracker() : super(MockApiClient(), Uri.parse('https://api.askodox.test'));
  final events = <(String, String)>[];

  @override
  void track(UniversalMatch match, String event) => events.add((match.clickId ?? '', event));
}

/// Stand-in for the phone-OTP screen: "Verify" signs the test user in and
/// returns to the chat, exactly like a successful OTP.
class _FakeSignInScreen extends ConsumerWidget {
  const _FakeSignInScreen({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('fakeOtpVerify'),
            onPressed: () {
              onSignIn();
              (ref.read(authSessionProvider.notifier) as _TestAuth).signInForTest();
              context.pop(true);
            },
            child: const Text('Verify OTP'),
          ),
        ),
      );
}

/// "Ask ASKODOX about this" (full card) / "Chat" (comparison card): the
/// same action, found by its key.
/// A result kind is shown as its comparison tab (LOCAL / ONLINE / ...), or
/// -- when it is the only kind -- as the label on its cards.
void _expectKind(String kind) => expect(
    find.byWidgetPredicate((w) =>
        w.key == ValueKey('askodoxCompareTab-$kind') ||
        (w is Text && w.data == kind.toUpperCase())),
    findsWidgets,
    reason: kind);

Finder _askButtons() => find.byWidgetPredicate(
    (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxAsk-'));

Future<void> _tapAsk(WidgetTester tester) async {
  await tester.ensureVisible(_askButtons().first);
  await tester.tap(_askButtons().first);
  await _Harness.settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await _Harness.settle(tester);
}

void main() {
  _compactRenders();
  group('rich result cards in the conversation', () {
    testWidgets('nearby vs online line, Directions to real coordinates, Save and Share', (tester) async {
      const shop = UniversalMatch(
        id: 'external-p1', title: 'Sri Rama Kirana', subtitle: 'Main Road, Vuyyuru', source: 'external',
        distanceKm: 0.8, ratingAverage: 4.4, reviewCount: 31, latitude: 16.365, longitude: 80.845,
        locationLabel: 'Main Road, Vuyyuru', availability: 'Open now');
      const registered = UniversalMatch(
        id: '77', title: 'Toor dal 1 kg', source: 'local', price: 160, distanceKm: 1.2, locationLabel: 'Vuyyuru',
        imageUrl: '/api/catalog/photos/77');
      const online = UniversalMatch(
        id: 'online-1', title: 'Toor Dal 1kg', source: 'online', price: 175, priceVerified: false,
        sourceName: 'jiomart.com', destinationUrl: 'https://www.jiomart.com/p/toor-dal');
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '901', matches: [registered, shop, online]),
      ]));
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add('${(call.arguments as Map)['text']}');
        return null;
      });
      await h.pump(tester);
      await h.send(tester, 'I want to buy toor dal 1 kg in Vuyyuru');
      if (find.byKey(const Key('askodoxLocalOnlineCompare')).evaluate().isEmpty) await h.send(tester, 'show me');

      expect(find.byKey(const Key('askodoxLocalOnlineCompare')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('askodoxCompareLocal'))).data, contains('₹160'));
      expect(tester.widget<Text>(find.byKey(const Key('askodoxCompareOnline'))).data,
          allOf(contains('₹175'), contains('page price'), contains('jiomart.com')));
      expect(find.byKey(const ValueKey('askodoxDirections-external-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxDirections-online-1')), findsNothing, reason: 'no directions to a website');
      expect(askodoxDirectionsUri(shop).toString(), contains('destination=16.365,80.845'));

      await tester.ensureVisible(find.byKey(const ValueKey('askodoxSave-77')));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const ValueKey('askodoxSave-77')));
      await _Harness.settle(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
      expect(container.read(askodoxSavedOptionsProvider).map((m) => m.id), ['77']);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxShare-online-1')));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const ValueKey('askodoxShare-online-1')));
      await _Harness.settle(tester);
      expect(clipboard.single, allOf(contains('Toor Dal 1kg'), contains('https://www.jiomart.com/p/toor-dal')));
    });
  });

  group('seller role + ready-made catalogue (real-phone 1265 bug)', () {
    ProviderContainer scope(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));

    testWidgets('a Seller asking for a grocery catalogue stays Seller, gets the catalogue, "all" selects all',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([]));
      await h.pump(tester);
      scope(tester).read(askodoxRoleProvider.notifier).setActive(AskodoxUserRole.seller);
      await _Harness.settle(tester);

      await h.send(tester, 'Do you have ready-made grocery catalogue?');
      expect(scope(tester).read(askodoxRoleProvider).active, AskodoxUserRole.seller, reason: 'never Seller -> Buyer');
      expect(find.textContaining('→ Buyer'), findsNothing);
      expect(h.matches.deals, isEmpty, reason: 'no buyer search, no online shopping cards');
      expect(h.assistant.requests, isEmpty, reason: 'handled as the seller task, not a new AI search');
      expect(h.catalogue.requested, ['grocery']);
      expect(find.byKey(const ValueKey('askodoxCatalogueCard-grocery')), findsOneWidget);
      expect(find.textContaining('ready-made Grocery (kirana) catalogue'), findsOneWidget);

      await h.send(tester, 'all');
      expect(h.matches.deals, isEmpty, reason: '"all" resolves inside the catalogue, not a web search');
      expect(find.textContaining('2 categories selected (2 items)'), findsOneWidget);
      expect(find.byKey(const Key('askodoxCatalogueReviewButton')), findsOneWidget, reason: 'editor opened');

      await tester.enterText(find.byKey(const ValueKey('askodoxCataloguePrice-dals.toor')), '160');
      await tester.tap(find.byKey(const Key('askodoxCatalogueReviewButton')));
      await _Harness.settle(tester);
      expect(find.byKey(const Key('askodoxCatalogueReview')), findsOneWidget);
      expect(find.text('1 will be published'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxCataloguePublish')));
      await _Harness.settle(tester);

      final (key, entries, shop, address) = h.catalogue.published.single;
      expect(key, 'grocery');
      expect(entries.map((e) => e.item.key), ['dals.toor', 'oils_ghee.ghee']);
      expect(entries.first.price, 160);
      expect(entries.last.price, isNull, reason: 'no price is never invented');
      expect(shop, 'Sri Lakshmi Kirana', reason: 'prefilled from the stored profile');
      expect(address, 'Vuyyuru');
      expect(find.textContaining('Published 1 item(s)'), findsOneWidget);
      expect(scope(tester).read(askodoxRoleProvider).active, AskodoxUserRole.seller);
    });

    testWidgets('Telugu seller: "కిరాణా కేటలాగ్ ఉందా?" then "అన్నీ" -- Telugu replies, no search', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([]));
      await h.pump(tester, locale: 'te');
      scope(tester).read(askodoxRoleProvider.notifier).setActive(AskodoxUserRole.seller);
      await h.send(tester, 'కిరాణా కేటలాగ్ ఉందా?');
      expect(find.textContaining('రెడీమేడ్ కిరాణా కేటలాగ్'), findsOneWidget);
      await h.send(tester, 'అన్నీ');
      expect(find.textContaining('2 విభాగాలు ఎంచుకున్నారు'), findsOneWidget);
      expect(h.matches.deals, isEmpty);
      expect(scope(tester).read(askodoxRoleProvider).active, AskodoxUserRole.seller);
    });

    testWidgets('a Buyer asking for a catalogue for their own shop becomes Seller (announced)', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([]));
      await h.pump(tester);
      await h.send(tester, 'I need a ready-made catalogue for my shop, grocery');
      expect(scope(tester).read(askodoxRoleProvider).active, AskodoxUserRole.seller);
      expect(find.textContaining('Buyer → Seller'), findsOneWidget);
      expect(h.matches.deals, isEmpty);
    });

    testWidgets('an unsupported catalogue is said honestly with a real next step', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([]));
      await h.pump(tester);
      scope(tester).read(askodoxRoleProvider.notifier).setActive(AskodoxUserRole.seller);
      await h.send(tester, 'do you have a mobile accessories catalogue?');
      expect(find.textContaining('Which catalogue do you need?'), findsOneWidget);
      expect(find.textContaining('price list'), findsOneWidget);
      expect(find.byType(Card).evaluate().where((e) => e.widget.key.toString().contains('askodoxCatalogueCard')), isEmpty);
      expect(h.matches.deals, isEmpty);
    });
  });

  testWidgets('APK 1275: the deal question is asked in the conversation language; no restating bubble',
      (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([
      const UniversalMatchResult(dealId: '995', matches: [_localMatch]),
    ]));
    h.assistant.localized['How much chicken do you need?'] = 'మీకు ఎంత చికెన్ కావాలి?';
    await h.pump(tester);
    await h.send(tester, 'నాకు దగ్గరలో చికెన్ షాపులు కావాలి');
    expect(find.textContaining('మీకు ఎంత చికెన్ కావాలి?'), findsOneWidget);
    expect(find.textContaining('How much chicken'), findsNothing, reason: 'no English question in a Telugu chat');
    expect(find.byKey(const Key('askodoxCompanionLine')), findsNothing,
        reason: 'the reply is on screen; no second bubble restating it');
  });

  testWidgets('APK 1276: every companion button does its job (camera, photos, video, files, type)', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository(const []));
    await h.pump(tester);
    for (final action in ['camera', 'photos', 'video', 'files']) {
      h.picker.next = const [];
      await _openCompanionHub(tester);
      await tester.tap(find.byKey(ValueKey('askodoxHubAction-$action')));
      await _Harness.settle(tester);
      expect(h.picker.sources.last, action, reason: '$action opens its own picker');
    }
    await _openCompanionHub(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxHubAction-chat')));
    await _Harness.settle(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue, reason: 'Type puts the cursor in the message box');
  });

  testWidgets('APK 1276: a listing rejected for sign-in says so plainly and offers Sign in', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository(const []));
    h.listings.next = const SellerListingResult(
        success: false, message: 'Sign in required -- no session token was sent');
    await h.pump(tester);
    await h.send(tester, 'I want to sell my 2 bicycles in Vijayawada for 3000');
    expect(find.textContaining('no session token'), findsNothing, reason: 'never the server wording');
    expect(find.textContaining('Sign in to publish your listing'), findsOneWidget);
    expect(find.byKey(const Key('askodoxListingSignIn')), findsOneWidget);
  });

  group('APK 1274: sign-off', () {
    testWidgets('"good night" gets the localized sign-off -- no search, no AI follow-up question', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '990', matches: [_localMatch]),
      ]));
      h.signoffs['te'] = 'శుభరాత్రి! మళ్లీ కలుద్దాం.';
      await h.pump(tester);
      await h.send(tester, 'నాకు ఒక మిక్సర్ గ్రైండర్ కావాలి');
      final before = h.assistant.requests.length;
      final searches = h.matches.deals.length;
      await h.send(tester, 'శుభరాత్రి');
      expect(find.text('శుభరాత్రి! మళ్లీ కలుద్దాం.'), findsOneWidget);
      expect(h.assistant.requests.length, before, reason: 'template answered; no AI turn');
      expect(h.matches.deals.length, searches, reason: 'a goodbye never searches');
    });

    testWidgets('no template in that language: the AI writes the sign-off (any language), still no search',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '991', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'thanks, bye');
      expect(h.assistant.requests.last['message'] as String, contains('ending the conversation'));
      expect(h.matches.deals, isEmpty);
    });
  });

  group('APK 1273 phone findings: attachment intent, multi-photo, no unsolicited prompts', () {
    Future<void> attach(WidgetTester tester, _Harness h, String action, List<ChatAttachment> files) async {
      h.picker.next = files;
      await _openCompanionHub(tester);
      await tester.tap(find.byKey(ValueKey('askodoxHubAction-$action')));
      await _Harness.settle(tester);
    }

    testWidgets('a photo sent alone is explained, never turned into a seller/product search', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '980', matches: [_localMatch], nextActions: ['refer_provider']),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'camera', [ChatAttachment(name: 'camera.jpg', bytes: _photoBytes, mimeType: 'image/jpeg')]);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _Harness.settle(tester);
      expect(h.attachments.calls, hasLength(1), reason: 'the photo was analysed');
      final message = h.assistant.requests.single['message'] as String;
      expect(message, contains('pressure cooker'), reason: 'vision facts reach the reasoning turn');
      expect(message, contains('Do not list sellers'), reason: 'attachment intent guard');
      expect(h.matches.deals, isEmpty, reason: 'no generic commerce search for a photo sent to be understood');
      expect(find.byKey(const Key('askodoxReferProvider')), findsNothing);
      expect(find.byKey(const Key('askodoxJoinAsProvider')), findsNothing);
    });

    testWidgets('a photo WITH "where can I buy this nearby" still searches', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '981', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'camera', [ChatAttachment(name: 'camera.jpg', bytes: _photoBytes, mimeType: 'image/jpeg')]);
      await h.send(tester, 'where can I buy this nearby? show me');
      expect(h.matches.deals, hasLength(1), reason: 'the user asked to act');
      expect(h.assistant.requests.first['message'] as String, isNot(contains('Do not list sellers')));
    });

    testWidgets('multi-photo: one failure keeps that photo, the others are analysed and sent', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '982', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'photos', [
        ChatAttachment(name: 'one.jpg', bytes: _photoBytes, mimeType: 'image/jpeg'),
        ChatAttachment(name: 'two.jpg', bytes: _photoBytes, mimeType: 'image/jpeg'),
        ChatAttachment(name: 'three.jpg', bytes: _photoBytes, mimeType: 'image/jpeg'),
      ]);
      expect(h.picker.sources.last, 'photos');
      expect(find.text('one.jpg'), findsOneWidget);
      expect(find.text('three.jpg'), findsOneWidget, reason: 'every selected photo has a preview');
      h.attachments.failures.add(const ChatAttachmentException('failed', 'bad gateway', statusCode: 502));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _Harness.settle(tester);
      expect(h.attachments.calls, hasLength(3), reason: 'each photo analysed; one failure does not stop the rest');
      final message = h.assistant.requests.single['message'] as String;
      expect(message, contains('two.jpg: Shows: pressure cooker'));
      expect(message, contains('three.jpg: Shows: pressure cooker'));
      expect(message, contains('could not be analysed: one.jpg'), reason: 'the failed one is reported honestly');
      expect(find.byKey(const ValueKey('askodoxAttachmentNotice-attach_partial')), findsOneWidget);
      expect(find.byKey(const Key('askodoxAttachmentPreview')), findsOneWidget,
          reason: 'the failed photo stays in the composer for a retry');
    });
  });

  group('attachments reach real multimodal processing (Section 14)', () {
    Future<void> attach(WidgetTester tester, _Harness h, String menuLabel, List<ChatAttachment> files) async {
      h.picker.next = files;
      // Attachments come from the companion's actions (no separate +).
      await _openCompanionHub(tester);
      const telugu = {'కెమెరా': 'camera', 'ఫోటోలు': 'photos', 'వీడియో': 'video', 'ఫైల్స్': 'files'};
      await tester.tap(find.byKey(ValueKey('askodoxHubAction-${telugu[menuLabel] ?? menuLabel.toLowerCase()}')));
      await _Harness.settle(tester);
    }

    testWidgets('photo + Telugu question: the actual bytes are analyzed and the facts drive a Telugu reply',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '970', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'Photos', [ChatAttachment(name: 'IMG_2031.jpg', bytes: _photoBytes, mimeType: 'image/jpeg')]);
      expect(find.byKey(const Key('askodoxAttachmentPreview')), findsOneWidget);
      expect(find.text('IMG_2031.jpg'), findsOneWidget);
      await h.send(tester, 'ఇది ఏమిటి? దగ్గరలో ఎక్కడ దొరుకుతుంది?');

      final call = h.attachments.calls.single;
      expect(call.attachment.bytes, _photoBytes, reason: 'the real image bytes, not a file name');
      expect(call.attachment.mimeType, 'image/jpeg');
      expect(call.userText, 'ఇది ఏమిటి? దగ్గరలో ఎక్కడ దొరుకుతుంది?', reason: 'caption + attachment together');
      expect(call.language, 'te');
      final message = h.assistant.requests.first['message'] as String;
      expect(message, contains('pressure cooker'));
      expect(message, contains('ఇది ఏమిటి?'));
      expect(message, isNot(contains('[Attachment')));
      expect(message, isNot(contains('Please inspect this attachment')));
      expect(h.assistant.requests.first['locale'], 'te', reason: 'the reply follows the conversation language');
      expect(find.textContaining('[Attachment'), findsNothing, reason: 'no placeholder shown as the request');
      expect(find.textContaining('Attachment facts'), findsNothing, reason: 'facts are context, not the user text');
      expect(find.text('IMG_2031.jpg'), findsOneWidget, reason: 'the chat bubble shows the attachment');
      expect(find.byKey(const Key('askodoxAttachmentPreview')), findsNothing);
    });

    testWidgets('an attachment with no words inherits the conversation language and still gets analyzed',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '971', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'నమస్తే, నాకు సహాయం కావాలి');
      await attach(tester, h, 'ఫైల్స్', [ChatAttachment(name: 'cooker.png', bytes: _photoBytes)]);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _Harness.settle(tester);
      expect(h.attachments.calls.single.attachment.mimeType, 'image/png', reason: 'MIME from the extension');
      expect(h.attachments.calls.single.language, 'te');
      final message = h.assistant.requests.last['message'] as String;
      expect(message, contains('pressure cooker'));
      expect(h.assistant.requests.last['locale'], 'te');
      expect(find.textContaining('without a question'), findsNothing, reason: 'the hidden ask is never shown');
    });

    testWidgets('Section 15: after Telugu, "yes" / "ok" / "?" keep Telugu (no "telugu lo" needed)', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '975', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'నాకు ఒక మంచి మిక్సర్ గ్రైండర్ కావాలి');
      for (final short in ['yes', 'ok', '?']) {
        await h.send(tester, short);
      }
      final locales = [for (final r in h.assistant.requests) r['locale']];
      expect(locales, everyElement('te'));
      expect(locales.length, greaterThanOrEqualTo(3));
    });

    testWidgets('upload failure keeps the attachment and Retry sends it; nothing is sent meanwhile',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '972', matches: [_localMatch]),
      ]));
      h.attachments.failures
          .add(const ChatAttachmentException('failed', 'bad gateway', statusCode: 502, endpoint: 'unified'));
      await h.pump(tester);
      await attach(tester, h, 'Camera', [ChatAttachment(name: 'camera.jpg', bytes: _photoBytes, mimeType: 'image/jpeg')]);
      await h.send(tester, 'what is this');
      expect(h.assistant.requests, isEmpty, reason: 'no placeholder request after a failed upload');
      expect(find.byKey(const Key('askodoxAttachmentPreview')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxAttachmentNotice-attach_failed')), findsOneWidget);
      expect(find.textContaining('(failed · HTTP 502 · unified)'), findsOneWidget,
          reason: 'the real status is shown, not only the generic sentence');
      expect(find.textContaining('bad gateway'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'help$')), findsWidgets,
          reason: 'the companion shows recovery for the real failure');
      await tester.tap(find.text('Retry'));
      await _Harness.settle(tester);
      expect(h.attachments.calls, hasLength(2));
      expect(h.assistant.requests.single['message'] as String, contains('pressure cooker'));
    });

    testWidgets('unsupported files are refused clearly; unavailable video is never pretended', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '973', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'Files', [ChatAttachment(name: 'backup.zip', bytes: _photoBytes)]);
      expect(find.byKey(const ValueKey('askodoxAttachmentNotice-attach_unsupported')), findsOneWidget);
      expect(find.byKey(const Key('askodoxAttachmentPreview')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await _Harness.settle(tester);

      h.attachments.failures.add(const ChatAttachmentException('unavailable', 'video analysis is not available'));
      await attach(tester, h, 'Video', [ChatAttachment(name: 'clip.mp4', bytes: _photoBytes, mimeType: 'video/mp4')]);
      await h.send(tester, 'what happened here');
      expect(find.byKey(const ValueKey('askodoxAttachmentNotice-attach_unavailable')), findsOneWidget);
      expect(h.assistant.requests, isEmpty);
    });

    testWidgets('several attachments are all analyzed and their facts combined; cancel keeps them',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '974', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await attach(tester, h, 'Photos', [
        ChatAttachment(name: 'front.jpg', bytes: _photoBytes, mimeType: 'image/jpeg'),
      ]);
      await attach(tester, h, 'Video', [ChatAttachment(name: 'clip.mp4', bytes: _photoBytes, mimeType: 'video/mp4')]);
      h.attachments.hold = Completer<void>();
      await tester.enterText(find.byType(TextField), 'fix this');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(find.byKey(const Key('askodoxAttachmentAnalyzing')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'understanding$')), findsOneWidget,
          reason: 'the companion reads the attachment while it is analyzed');
      await tester.tap(find.byKey(const Key('askodoxCancelAttachment')));
      h.attachments.hold!.complete();
      h.attachments.hold = null;
      await _Harness.settle(tester);
      expect(h.assistant.requests, isEmpty, reason: 'cancelled: nothing sent');
      expect(find.text('front.jpg'), findsOneWidget, reason: 'attachments stay after cancel');

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _Harness.settle(tester);
      final message = h.assistant.requests.single['message'] as String;
      expect(message, contains('front.jpg: Shows: pressure cooker'));
      expect(message, contains('clip.mp4: Video shows: a scooter with a flat tyre'));
    });
  });

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
    _expectKind('local');
    // Comparison cards keep the real facts (rating, distance, price); the
    // internal match score stays out of the compact card.
    expect(find.text('82% match'), findsNothing);
    expect(find.text('★ 4.5 (2)'), findsOneWidget);
    _expectKind('videos');
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('app-seller-1'), findsNothing);

    // AI-first: the first card offers a conversation, not a request.
    expect(find.text('Connect'), findsNothing);
    await _tapAsk(tester);
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
    expect(find.text('Play'), findsOneWidget);
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
    expect(_askButtons(), findsOneWidget);
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

  group('conversation language (Section 2)', () {
    testWidgets('Automatic: asked in Telugu -> Telugu replies, headings and actions through results and short follow-ups',
        (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '91', matches: [_onlineMatch]),
          const UniversalMatchResult(dealId: '92', matches: [_onlineMatch]),
        ]),
      );
      await h.pump(tester); // no Preferred Language chosen = Automatic
      await h.send(tester, 'నాకు Vijayawada లో mixer grinder కావాలి, చూపించండి');
      expect(h.assistant.requests.last['locale'], 'te');
      expect(find.text('స్థానిక match లేదు -- ఆన్‌లైన్ ఎంపికలు'), findsWidgets);
      expect(find.text('తెరవండి'), findsWidgets);
      expect(find.text('Open'), findsNothing);

      // Short Latin follow-ups (brand/size/"show me") never flip to English.
      await h.send(tester, '750 watt show me');
      expect(h.assistant.requests.last['locale'], 'te');
      expect(find.text('Online options'), findsNothing);
      expect(find.text('No local match yet -- online options'), findsNothing);
    });

    testWidgets('a real English sentence (or "reply in English") switches; Preferred Language always wins',
        (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '1', matches: [_onlineMatch]),
          const UniversalMatchResult(dealId: '2', matches: [_onlineMatch]),
        ]),
      );
      await h.pump(tester);
      await h.send(tester, 'నాకు mixer grinder కావాలి చూపించండి');
      expect(h.assistant.requests.last['locale'], 'te');
      await h.send(tester, 'please show me the cheapest mixer grinder options now');
      expect(h.assistant.requests.last['locale'], 'en');
    });

    testWidgets('explicit Preferred Language stays even when the customer types another script', (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '1', matches: [_onlineMatch]),
        ]),
      );
      await h.pump(tester, locale: 'en');
      await h.send(tester, 'నాకు mixer grinder కావాలి చూపించండి');
      expect(h.assistant.requests.last['locale'], 'en');
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('Hindi conversation: Hindi locale for the AI + Hindi result labels (not Telugu-only logic)',
        (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '1', matches: [_onlineMatch]),
        ]),
      );
      await h.pump(tester);
      await h.send(tester, 'मुझे विजयवाड़ा में मिक्सर ग्राइंडर चाहिए, दिखाओ');
      expect(h.assistant.requests.last['locale'], 'hi');
      expect(find.text('खोलें'), findsWidgets);
      expect(find.textContaining('ऑनलाइन विकल्प'), findsWidgets);
    });
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
    expect(_askButtons(), findsOneWidget);
  });

  testWidgets('guest browses real listings; "contact the seller" asks for sign-in instead of a raw error',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([StateError('Sign in required -- no session token was sent')]),
      products: [
        {'id': '42', 'title': 'Mixer grinder — 750W', 'subtitle': '₹3,200 • Vijayawada', 'price': 3200, 'provider_id': ''},
      ],
    )..signedIn = false;
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(find.text('₹3200'), findsOneWidget, reason: 'browsing never needs sign-in');
    await h.send(tester, 'Please contact the seller');
    expect(h.orders.placed, isEmpty);
    expect(find.textContaining('Sign in with your phone number to send this request'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxSignInToAct')), findsOneWidget);
    expect(find.textContaining('no session token'), findsNothing, reason: 'raw server errors are never shown');
  });

  testWidgets('signed-in "contact the seller" / "I want this" runs the same Send request action',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([StateError('Sign in required -- no session token was sent')]),
      products: [
        {'id': '42', 'title': 'Mixer grinder — 750W', 'subtitle': '₹3,200 • Vijayawada', 'price': 3200, 'provider_id': ''},
      ],
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    await h.send(tester, 'Please contact the seller');

    expect(h.orders.placed, ['42']);
    expect(h.matches.accepted, isEmpty);
    expect(find.textContaining('Request sent to "Mixer grinder — 750W"'), findsOneWidget);
  });

  testWidgets('AI clarifies ANY ambiguous category once, then searches the chosen thing with its category',
      (tester) async {
    final h = _Harness(
      assistant: _Assistant((message) => message.contains('amplifier')
          ? {
              'reply': 'Do you mean a guitar amplifier or a car audio amplifier?',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'clarify_need',
              'confidence': 0.8,
              'source': 'universal_ai',
              'entities': {
                'subject': 'amplifier',
                'category': 'audio equipment',
                'clarify_options': ['guitar amplifier', 'car audio amplifier'],
              },
            }
          : null),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '71', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I need an amplifier, show me');
    expect(h.matches.deals, isEmpty, reason: 'no guessed search before the one question');
    expect(find.textContaining('guitar amplifier or a car audio amplifier'), findsWidgets);

    await h.send(tester, '2');
    expect(h.matches.deals, hasLength(1));
    expect(h.matches.deals.single.subject!.toLowerCase(), contains('car audio amplifier'));
    expect(h.matches.deals.single.dynamicFields['aiCategory'], 'audio equipment',
        reason: 'the AI category travels with the requirement (and into the Admin trace slots)');
  });

  testWidgets('native speech word events reach the friend (lip-sync hook)', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
    await h.pump(tester);
    final element = tester.element(find.byType(AskodoxPrimaryHomeScreen));
    final voice = ProviderScope.containerOf(element).read(askodoxCompanionVoiceProvider)..speechBegin('hello world');
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'com.askodox.app/device',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('speechRange', {'start': 6, 'end': 11})),
      (_) {},
    );
    expect(voice.currentCharIndex(), 6);
    voice.speechEnd();
  });

  testWidgets('car: a short brand reply replaces the old brand in the searched subject (no fixed brand list)',
      (tester) async {
    final h = _Harness(
      // The AI names the first brand (it knows every maker); the later
      // "Tata" reply works even with the AI unavailable.
      assistant: _Assistant((message) => message.contains('Maruti')
          ? {
              'reply': 'Looking for Maruti cars under 10 lakh.',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'buy_product',
              'confidence': 0.9,
              'source': 'universal_ai',
              'entities': {'subject': 'Maruti car', 'brand': 'Maruti', 'budget': 1000000, 'location': 'Vijayawada'},
            }
          : null),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '1', matches: [_localMatch]),
        const UniversalMatchResult(dealId: '2', matches: [_localMatch]),
        const UniversalMatchResult(dealId: '3', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a Maruti car under 10 lakh in Vijayawada, show me');
    await h.send(tester, 'Tata');
    await h.send(tester, 'show me');

    final searched = h.matches.deals.last.subject ?? '';
    expect(searched.toLowerCase(), contains('tata'));
    expect(searched.toLowerCase(), isNot(contains('maruti')), reason: 'the old brand never drifts back');
    expect(h.matches.deals.last.dynamicFields['brand'], 'Tata');
  });

  Future<_Harness> advisorHarness(WidgetTester tester) async {
    const shoe = UniversalMatch(id: 'online-0-shoe', title: 'Cushioned running shoes at Store A', source: 'online',
        destinationUrl: 'https://a.example/shoes');
    final h = _Harness(
      assistant: _Assistant((message) => message.toLowerCase().contains('shoes')
          ? {
              'reply': 'Sure. Any brand you prefer?',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'buy_product',
              'confidence': 0.9,
              'source': 'universal_ai',
              'entities': {'subject': 'running shoes', 'location': 'Vijayawada'},
            }
          : null),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '1', matches: [shoe], advisor: AskodoxAdvisorView(
            ready: false, field: 'budget', required: true, question: 'What budget do you have in mind?',
            guidance: ['For running, a light shoe with good cushioning and a snug fit matters most.'])),
        const UniversalMatchResult(dealId: '2', matches: [shoe], advisor: AskodoxAdvisorView(ready: true)),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I need running shoes in Vijayawada');
    // The AI asked about the brand; "any" settles the BRAND only and the
    // still-missing size is asked next (never filled with "any").
    await h.send(tester, 'any');
    expect(h.matches.deals, isEmpty, reason: '"any" brand never jumps straight to results');
    expect(find.text('What size do you need?'), findsOneWidget);
    await h.send(tester, '9');
    expect(h.matches.deals.last.dynamicFields['no_preference'], ['brand']);
    expect(h.matches.deals.last.size, '9');
    // The advisor held the first results: guidance + the budget question,
    // no cards yet.
    expect(find.textContaining('What budget do you have in mind?'), findsWidgets);
    expect(find.textContaining('light shoe with good cushioning'), findsWidgets);
    expect(find.textContaining('Cushioned running shoes at Store A'), findsNothing,
        reason: 'no final recommendations before the decision-changing budget');
    return h;
  }

  testWidgets('Universal Advisor: budget is asked BEFORE final results, then the answer brings them', (tester) async {
    final h = await advisorHarness(tester);
    await h.send(tester, '2000');
    expect(find.textContaining('Cushioned running shoes at Store A'), findsWidgets);
    final searched = h.matches.deals.last;
    expect(h.matches.deals, hasLength(2));
    expect(searched.dynamicFields['no_preference'], ['brand'], reason: 'brand stays "any"; budget now known');
    expect(searched.dynamicFields['advisor_asked'], contains('budget'));
    expect(searched.dynamicFields['budget_max'] ?? searched.price, isNotNull, reason: 'the budget answer is applied');
    expect('${searched.size}', isNot('2000'), reason: 'the amount is never written into another slot');
  });

  testWidgets('Universal Advisor: "any" to the budget question settles the budget only, then results show',
      (tester) async {
    final h = await advisorHarness(tester);
    await h.send(tester, 'any');
    expect(find.textContaining('Cushioned running shoes at Store A'), findsWidgets);
    final searched = h.matches.deals.last;
    expect(searched.dynamicFields['no_preference'], containsAll(['brand', 'budget']));
    expect(searched.dynamicFields['usage'], isNull, reason: 'other fields keep their own state');
    expect(searched.size, isNot('any'));
  });

  testWidgets('several options = ONE compact horizontal rail; referral is a small chip; the friend says what it found',
      (tester) async {
    const a = UniversalMatch(id: 'online-0-a', title: 'Mixer grinder 750W at Store A', source: 'online',
        subtitle: '369 latest offers on mixer grinders in Vijayawada 2026 with free delivery and a very long snippet',
        destinationUrl: 'https://a.example/mixer', price: 3200, priceVerified: false);
    const b = UniversalMatch(id: 'online-1-b', title: 'Mixer grinder at Store B', source: 'online',
        destinationUrl: 'https://b.example/mixer');
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '', matches: [a, b], nextActions: ['refer_provider', 'find_more']),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');

    expect(find.byKey(const Key('askodoxComparisonRail')), findsOneWidget);
    final card = tester.getSize(find.byKey(const ValueKey('askodoxResultCard-online-online-0-a')));
    expect(card.width, lessThanOrEqualTo(282), reason: 'compact fixed-width card (272 + gap)');
    expect(find.text('Page mentions ₹3200'), findsOneWidget, reason: 'unverified price is labelled');
    // APK 1273: no unsolicited referral/join prompt on a plain buy request
    // (referral lives in Profile -> Refer & Earn).
    expect(find.text('Know someone? Refer'), findsNothing);
    expect(find.byKey(const Key('askodoxJoinAsProvider')), findsNothing);
    expect(find.text('Found 2 options — pick one to continue'), findsOneWidget);
  });

  testWidgets('results stay ABOVE; the conversation about them continues BELOW; input stays at the bottom',
      (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '5', matches: [_localMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    await _tapAsk(tester);
    await h.send(tester, 'is it available today?');

    final results = find.byWidgetPredicate(
        (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxChatResults-'));
    expect(results, findsOneWidget, reason: 'the selected result is not re-pinned elsewhere');
    final resultsTop = tester.getTopLeft(results).dy;
    final laterQuestion = tester.getTopLeft(find.text('is it available today?')).dy;
    final composer = tester.getTopLeft(find.byType(TextField)).dy;
    expect(laterQuestion, greaterThan(resultsTop), reason: 'conversation continues below the results');
    expect(composer, greaterThan(laterQuestion), reason: 'the input stays at the bottom');
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
    _expectKind('local');
    _expectKind('online');
    _expectKind('videos');
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
    _expectKind('local');
    expect(find.text('Affiliate link'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

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
      'local', 'used', 'surplus', 'deals', 'online', 'videos',
    ]) {
      _expectKind(heading);
    }
    expect(find.text('Affiliate link'), findsOneWidget);
    // AI-first: no request buttons on first results.
    expect(find.text('Send request'), findsNothing);
    // "All" previews at most 2 per group (3 local -> 2 + View all).
    expect(_askButtons(), findsNWidgets(7));
    expect(find.byKey(const ValueKey('askodoxViewAll-local')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxViewAll-local')));
    await tester.tap(find.byKey(const ValueKey('askodoxViewAll-local')));
    await tester.pumpAndSettle();
    // Nearby shop not on ASKODOX: open its real map page / ask ASKODOX,
    // never a request to a seller who is not on ASKODOX.
    expect(find.byKey(const ValueKey('askodoxOpen-external-p1')), findsOneWidget);
    expect(_askButtons(), findsNWidgets(3), reason: 'Local tab: only local rows');
    await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-all')));
    await tester.pumpAndSettle();

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

    // Customer Care's reply comes back into the same conversation.
    await tester.tap(find.byKey(const Key('askodoxSupportCheckReply')));
    await _Harness.settle(tester);
    expect(find.text('Support resolved it: Engineer reset your account'), findsOneWidget);
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
    await _tapAsk(tester);
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
    _expectKind('videos');
    expect(container.read(universalDealControllerProvider).deal?.subject, contains('mixer grinder'));
    expect(h.matches.deals, hasLength(1), reason: 'restoring never re-runs matching');
  });

  group('fresh Main Chat on every app launch (History keeps everything)', () {
    const ask = 'I want to buy a mixer grinder in Vijayawada';

    Future<(_Harness, ProviderContainer)> converse(WidgetTester tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '901', matches: [_localMatch, _videoMatch]),
        ]),
      );
      await h.pump(tester);
      await h.send(tester, ask);
      await _tapAsk(tester);
      await _tapText(tester, 'Connect');
      expect(find.text('Request sent'), findsOneWidget);
      return (h, ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen))));
    }

    ProviderContainer scope(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));

    testWidgets('reopening the app shows a new ask; the old chat stays in History and restores exactly',
        (tester) async {
      final (h, _) = await converse(tester);
      await h.relaunch(tester);
      final c = scope(tester);

      expect(find.text(ask), findsNothing, reason: 'Main Chat starts as a new, clean ask');
      expect(find.text('Request sent'), findsNothing);
      expect(c.read(universalDealControllerProvider).deal, isNull, reason: 'temporary deal context reset');
      final saved = c.read(askodoxConversationArchiveProvider);
      expect(saved, hasLength(1), reason: 'the previous conversation is kept, not deleted');
      expect(saved.single.title, ask);

      c.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.restore(saved.single.id);
      await _Harness.settle(tester);
      expect(find.text(ask), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget, reason: 'selected option + request state restored');
      _expectKind('videos');
      expect(c.read(universalDealControllerProvider).deal?.subject, contains('mixer grinder'));
      expect(h.matches.deals, hasLength(1), reason: 'History restore never re-runs matching');
    });

    testWidgets('same-session navigation keeps the active chat', (tester) async {
      final (h, _) = await converse(tester);
      await h.navigateAway(tester);
      expect(find.text('Explore screen'), findsOneWidget);
      await h.navigateBack(tester);
      expect(find.text(ask), findsOneWidget, reason: 'not a new launch: chat preserved');
      expect(find.text('Request sent'), findsOneWidget);
      expect(scope(tester).read(askodoxConversationArchiveProvider), hasLength(1));
    });

    testWidgets('New ask after a relaunch starts clean and both conversations coexist', (tester) async {
      final (h, _) = await converse(tester);
      await h.relaunch(tester);
      await h.send(tester, 'I need a plumber in Guntur');
      final c = scope(tester);
      expect(find.text('I need a plumber in Guntur'), findsOneWidget);
      c.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.newConversation();
      await _Harness.settle(tester);
      expect(find.text('I need a plumber in Guntur'), findsNothing);
      expect(c.read(askodoxConversationArchiveProvider).map((x) => x.title),
          containsAll([ask, 'I need a plumber in Guntur']));
    });

    testWidgets('repeated launches never duplicate History and owned roles survive', (tester) async {
      final (h, c) = await converse(tester);
      c.read(askodoxRoleProvider.notifier).toggleOwned(AskodoxUserRole.seller, true);
      c.read(askodoxRoleProvider.notifier).toggleOwned(AskodoxUserRole.serviceProvider, true);
      await _Harness.settle(tester);
      for (var i = 0; i < 3; i++) {
        await h.relaunch(tester);
      }
      final after = scope(tester);
      after.read(askodoxRoleProvider); // created lazily; let it load from storage
      await _Harness.settle(tester);
      expect(after.read(askodoxConversationArchiveProvider), hasLength(1), reason: 'no duplicate per launch');
      expect(after.read(askodoxRoleProvider).owned,
          containsAll([AskodoxUserRole.buyer, AskodoxUserRole.seller, AskodoxUserRole.serviceProvider]),
          reason: 'profile/owned roles are account state, not chat state');
      expect(find.text(ask), findsNothing);
    });

    testWidgets('after a crash, turns only in the per-turn store are recovered into History', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      // Simulate a process killed after the per-turn store was written but
      // before the History snapshot was.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('askodox.active_conversation_turns.v1', jsonEncode([
        {'text': 'నాకు 1 కిలో చికెన్ కావాలి', 'isUser': true},
        {'text': 'ఏ కట్ కావాలి?', 'isUser': false},
      ]));
      await prefs.setString('askodox.conversation_current.v1', 'lost-conversation');
      await h.relaunch(tester);
      final c = scope(tester);
      expect(find.text('నాకు 1 కిలో చికెన్ కావాలి'), findsNothing, reason: 'fresh ask on the new launch');
      final saved = c.read(askodoxConversationArchiveProvider);
      expect(saved.single.id, 'lost-conversation');
      expect(saved.single.title, 'నాకు 1 కిలో చికెన్ కావాలి');
      c.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.restore('lost-conversation');
      await _Harness.settle(tester);
      expect(find.text('ఏ కట్ కావాలి?'), findsOneWidget);
    });
  });

  group('universal engine: results, AI-first routing and the deal lifecycle in chat', () {
    const tvAsk = 'I want a 43 inch portable battery TV in Vijayawada, budget 20000 to 30000';
    Map<String, Object?> advisory(String reply, {bool transactional = false, Map<String, Object?>? entities}) => {
          'reply': reply,
          'domain': 'PRODUCT',
          'transactional': transactional,
          'action': 'buying_advice',
          'confidence': 0.9,
          'source': 'universal_ai',
          'entities': entities ?? {'subject': '43 inch portable battery TV', 'location': 'Vijayawada', 'price': 30000},
        };

    Future<_Harness> withTvResults(WidgetTester tester, {Map<String, Object?>? Function(String)? later}) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '910', matches: [_registeredTv, _registeredTv2, _onlineMatch]),
        ]),
        assistant: _Assistant((message) => message.startsWith('I want a 43')
            ? advisory('Portable 43 inch battery TVs are rare; check battery backup hours and weight.')
            : later?.call(message)),
      );
      h.orders.orderId = '501';
      await h.pump(tester);
      await h.send(tester, tvAsk);
      return h;
    }

    testWidgets('an advisory AI reply for a concrete need still shows real result cards, not text only',
        (tester) async {
      final h = await withTvResults(tester);
      expect(h.matches.deals, hasLength(1), reason: 'the need was searched');
      expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
      expect(find.text('43 inch portable battery TV'), findsOneWidget);
      expect(find.textContaining('rare'), findsOneWidget, reason: 'AI guidance is kept next to the cards');
    });

    testWidgets('a missing detail is asked as the next question instead of a silent explanation',
        (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('must not search yet')]),
        assistant: _Assistant((_) => advisory('Portable battery TVs are handy for outages.',
            entities: {'subject': '43 inch portable battery TV'})),
      );
      await h.pump(tester);
      await h.send(tester, 'I want a 43 inch portable battery TV');
      expect(h.matches.deals, isEmpty);
      final reply = tester.widgetList<Text>(find.textContaining('handy for outages')).single.data!;
      expect(reply.trim().endsWith('?'), isTrue, reason: 'the requirement asks its next question');
    });

    testWidgets('a seller-only question before any request rides along with Send request, with the requirement',
        (tester) async {
      final h = await withTvResults(tester, later: (_) => advisory('It is listed from Vijayawada.',
          entities: const {}));
      await h.send(tester, 'Is it in stock and is delivery free?');
      expect(find.textContaining('only be confirmed by the seller'), findsOneWidget);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);

      expect(h.orders.questions.single, 'Is it in stock and is delivery free?');
      expect(h.orders.contexts.single!['subject'], contains('battery TV'));
      expect(h.orders.contexts.single!['deal_id'], '910');
      expect(find.byKey(const Key('askodoxDealPanel')), findsOneWidget);
      expect(find.text('Request sent — waiting for the seller/provider'), findsOneWidget);
    });

    testWidgets('with a request open, stock and price questions go to the seller through ASKODOX, not the AI',
        (tester) async {
      final h = await withTvResults(tester, later: (_) => advisory('ok', entities: const {}));
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);
      final aiCalls = h.assistant.requests.length;

      await h.send(tester, 'Can they do ₹24,000?');
      await h.send(tester, 'Is it in stock?');

      expect(h.lifecycle.calls, ['OFFER:24000', 'QUESTION:Is it in stock?']);
      expect(h.assistant.requests.length, aiCalls, reason: 'ASKODOX did not guess seller-only facts');
      for (final text in ['price proposal to the seller', 'Only the seller can confirm this']) {
        await tester.scrollUntilVisible(find.textContaining(text), 300, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining(text), findsOneWidget);
      }
    });

    testWidgets('counter-offer, delivery, customer confirmation and review close the deal in the same chat',
        (tester) async {
      final h = await withTvResults(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);

      h.lifecycle.messages.add(const OrderMessage(fromRole: 'seller', kind: 'COUNTER_OFFER', amount: 25000));
      await tester.tap(find.byTooltip('Refresh'));
      await _Harness.settle(tester);
      expect(find.textContaining('counter-offer ₹25000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxDealAcceptOffer')));
      await _Harness.settle(tester);
      expect(find.text('Price: ₹25000'), findsOneWidget);

      h.lifecycle.status = 'DELIVERED';
      await tester.tap(find.byTooltip('Refresh'));
      await _Harness.settle(tester);
      expect(find.text('Seller marked delivered — please confirm'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxDealConfirm')));
      await _Harness.settle(tester);
      expect(find.text('Did you receive the product?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxDealConfirmYes')));
      await _Harness.settle(tester);
      expect(find.text('Deal closed'), findsOneWidget);
      expect(find.byKey(const Key('askodoxDealReview')), findsOneWidget);
    });

    testWidgets('confirming completion reveals the server-decided Scratch & Reveal reward once', (tester) async {
      final h = await withTvResults(tester);
      h.benefits.scratchReward = const AskodoxClaimResult(value: 50, kind: 'credit', name: 'Thank-you credit');
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);
      h.lifecycle.status = 'DELIVERED';
      await tester.tap(find.byTooltip('Refresh'));
      await _Harness.settle(tester);
      expect(h.benefits.scratched, isEmpty, reason: 'nothing before the customer confirms');
      await tester.tap(find.byKey(const Key('askodoxDealConfirm')));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const Key('askodoxDealConfirmYes')));
      await _Harness.settle(tester);
      expect(h.benefits.scratched, hasLength(1), reason: 'asked once, for this order');
      expect(find.byKey(const Key('askodoxScratchCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxScratchArea')));
      await _Harness.settle(tester);
      expect(find.text('₹50 ASKODOX credit'), findsOneWidget, reason: 'exactly what the server issued');
    });

    testWidgets('a declined request keeps the need and shows other options without starting over',
        (tester) async {
      final h = await withTvResults(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);
      h.lifecycle.status = 'REJECTED';
      await tester.tap(find.byTooltip('Refresh'));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const Key('askodoxDealAlternatives')));
      await _Harness.settle(tester);
      expect(find.textContaining('Your requirement is kept'), findsOneWidget);
      expect(find.text('Other 43 inch TV'), findsOneWidget);
      expect(h.matches.deals, hasLength(1), reason: 'no new search, no retyping');
    });

    testWidgets('a service asks "completed properly?" and a problem goes to Customer Care, not closed',
        (tester) async {
      final h = await withTvResults(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);
      h.lifecycle
        ..kind = 'service'
        ..status = 'SERVICE_COMPLETED';
      await tester.tap(find.byTooltip('Refresh'));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const Key('askodoxDealConfirm')));
      await _Harness.settle(tester);
      expect(find.text('Was the service completed properly?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxDealConfirmNo')));
      await _Harness.settle(tester);
      await tester.enterText(find.byKey(const Key('askodoxDealInput')), 'Installation incomplete');
      await tester.tap(find.byKey(const Key('askodoxDealSubmit')));
      await _Harness.settle(tester);
      expect(h.lifecycle.calls.last, 'problem:Installation incomplete');
      expect(find.text('Problem reported — Customer Care is handling it'), findsOneWidget);
      expect(find.byKey(const Key('askodoxDealConfirm')), findsNothing, reason: 'a dispute blocks closing');
    });

    testWidgets('History restores the deal with its live status after an app relaunch', (tester) async {
      final h = await withTvResults(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxAsk-42')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.text('Send request').first);
      await tester.tap(find.text('Send request').first);
      await _Harness.settle(tester);
      await h.relaunch(tester);
      expect(find.byKey(const Key('askodoxDealPanel')), findsNothing, reason: 'fresh Main Chat (PR #97)');
      final c = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
      h.lifecycle.status = 'DISPATCHED';
      c.read(askodoxChatRequestProvider.notifier).state =
          AskodoxChatRequest.restore(c.read(askodoxConversationArchiveProvider).single.id);
      await _Harness.settle(tester);
      expect(find.byKey(const Key('askodoxDealPanel')), findsOneWidget);
      expect(find.text('Dispatched'), findsOneWidget, reason: 'current state, not a stale copy');
      expect(h.matches.deals, hasLength(1), reason: 'restoring never re-runs matching');
    });

    testWidgets('Compare and Details are AI-first actions; Details shows only verified fields',
        (tester) async {
      final h = await withTvResults(tester, later: (_) => advisory('The Sony is cheaper.', entities: const {}));
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxDetails-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxDetails-42')));
      await _Harness.settle(tester);
      final sheet = find.byKey(const Key('askodoxDetailsSheet'));
      expect(find.descendant(of: sheet, matching: find.textContaining('₹24999')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('Distance')), findsNothing,
          reason: 'no distance was verified, so none is shown');
      Navigator.of(tester.element(sheet)).pop();
      await _Harness.settle(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('askodoxCompare-42')));
      await tester.tap(find.byKey(const ValueKey('askodoxCompare-42')));
      await _Harness.settle(tester);
      final compare = h.assistant.requests.last['message'] as String;
      expect(compare, contains('Compare'));
      expect(compare, contains('43 inch battery backup TV'), reason: 'other options are in the AI context');
      expect(h.matches.deals, hasLength(1), reason: 'comparing never restarts the search');
    });
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
    // Asked in Telugu -> clarified in Telugu (the app UI is English here).
    expect(find.textContaining('బ్యాటరీతో నడిచే పోర్టబుల్ టీవీ'), findsWidgets);
    expect(find.textContaining('Do you mean a portable TV'), findsNothing);
    expect(h.matches.deals, isEmpty);

    await h.send(tester, 'inverter backup');
    expect(h.matches.deals, isEmpty, reason: 'size still needed for a TV');
    await h.send(tester, '32 inch');
    await h.send(tester, 'Vijayawada');

    expect(h.matches.deals, hasLength(1));
    expect(h.matches.deals.single.subject, 'low power TV for inverter battery backup');
  });

  testWidgets('Telugu 43-inch TV "show me" with a budget searches at once -- no questionnaire', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '801', matches: [_onlineMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'నాకు 43-inch TV ₹20,000–₹30,000 లో కావాలి — show me');

    expect(h.matches.deals, hasLength(1), reason: 'show me + known subject = search now');
    final deal = h.matches.deals.single;
    expect(deal.subject, isNot(contains('₹')));
    expect(deal.subject!.toLowerCase(), contains('tv'));
    expect(deal.price, 30000);
    expect(deal.dynamicFields['budget_min'], 20000);
    expect(deal.dynamicFields['budget_max'], 30000);
    expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
    final trace = h.matches.traces.single!;
    expect(trace['query'], contains('43-inch TV'));
  });

  testWidgets('fridge + TV + car in one message: separate state and results per category', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '811', matches: [_onlineMatch]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'నాకు fridge ₹30–40k, TV ₹20–30k, car ₹10 lakh లో కావాలి — show me');

    expect(h.matches.deals, hasLength(3));
    final bySubject = {for (final d in h.matches.deals) d.subject!.toLowerCase(): d};
    expect(bySubject.keys, containsAll(['fridge', 'tv', 'car']));
    expect(bySubject['fridge']!.dynamicFields['budget_min'], 30000);
    expect(bySubject['fridge']!.dynamicFields['budget_max'], 40000);
    expect(bySubject['tv']!.dynamicFields['budget_max'], 30000);
    expect(bySubject['car']!.price, 1000000);
    expect(find.textContaining('fridge · ₹30000–₹40000'), findsOneWidget);
    expect(find.textContaining('car · ₹10 lakh'), findsOneWidget);

    // Coming back to one category restores ITS answers, not another's.
    await h.send(tester, 'TV show me');
    expect(h.matches.deals, hasLength(4));
    expect(h.matches.deals.last.subject!.toLowerCase(), 'tv');
    expect(h.matches.deals.last.dynamicFields['budget_max'], 30000);
  });

  group('universal "show me" acceptance (no AI available, one pipeline for every category)', () {
    for (final (label, message, subjectWord, intents, price) in [
      ('chicken', '1 kg chicken curry cut in Vijayawada, show me', 'chicken', {DealIntent.buy}, null),
      ('car', 'I want a used car under ₹8 lakh in Vijayawada — show me', 'car', {DealIntent.buy}, 800000.0),
      ('service', 'I need a plumber in Vijayawada, show me options', 'plumber', {DealIntent.needService, DealIntent.needWorker}, null),
      ('job', 'I need a delivery boy job in Vijayawada, show me', 'delivery', {DealIntent.seekWork}, null),
      ('AC installation', 'I need AC installation service, show me', 'ac', {DealIntent.needService, DealIntent.needWorker}, null),
      ('TV', '43 inch TV under ₹30,000, show me', 'tv', {DealIntent.buy}, 30000.0),
      // Categories no keyword list knows: the same universal pipeline.
      ('guitar', 'I want an acoustic guitar under ₹6,000, show me', 'guitar', {DealIntent.buy}, 6000.0),
      ('tailor', 'I need a tailor for blouse stitching, show me', 'tailor', {DealIntent.needService, DealIntent.needWorker, DealIntent.buy}, null),
      ('solar panel', 'I want to buy a 1 kW solar panel, show me', 'solar', {DealIntent.buy}, null),
    ]) {
      testWidgets('$label: one search, real results in chat, no questionnaire restart', (tester) async {
        final h = _Harness(
          matches: _FakeMatchRepository([
            const UniversalMatchResult(dealId: '901', matches: [_localMatch]),
          ]),
        );
        await h.pump(tester);
        await h.send(tester, message);

        expect(h.matches.deals, hasLength(1), reason: '$label: show me searches once');
        final deal = h.matches.deals.single;
        // ignore: avoid_print
        print('ACCEPT $label -> intent=${deal.intent} subject=${deal.subject} price=${deal.price}');
        expect(deal.subject!.toLowerCase(), contains(subjectWord));
        expect(intents, contains(deal.intent));
        if (price != null) expect(deal.price, price);
        expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget);
        expect(find.textContaining('Sign in'), findsNothing);
        expect(h.matches.traces.single!['query'], message);
      });
    }
  });

  testWidgets('guest can browse; the sign-in prompt appears only when sending a request', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '', matches: [_registeredTv]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, '43 inch TV ₹25,000 show me');
    expect(h.matches.deals, hasLength(1));
    expect(find.textContaining('Sign in'), findsNothing, reason: 'viewing results never needs sign-in');
  });

  group('human flow: chat actions are real backend actions', () {
    testWidgets('typed "yes, order the second one" places the SAME order as the Send request button', (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([
          const UniversalMatchResult(dealId: '901', matches: [_registeredTv, _registeredTv2]),
        ]),
      );
      h.orders.orderId = '501';
      await h.pump(tester);
      await h.send(tester, '43 inch TV ₹30,000 show me');
      expect(h.matches.deals, hasLength(1));

      await h.send(tester, 'yes, order the second one');
      expect(h.orders.placed, ['43'], reason: 'POST /api/orders for the chosen registered listing');
      expect(h.orders.contexts.single, isNotNull, reason: 'the requirement travels with the request');
      expect(find.textContaining('Request sent to "43 inch battery backup TV" (#501)'), findsOneWidget);
      expect(h.matches.deals, hasLength(1), reason: 'confirming never restarts the search');

      await h.send(tester, 'order it');
      expect(h.orders.placed, ['43'], reason: 'no duplicate order');
      expect(find.textContaining('already sent (#501)'), findsOneWidget);
    });

    testWidgets('a snippet price is labelled, never shown as a confirmed price', (tester) async {
      const page = UniversalMatch(
        id: 'online-0-urbancompany.com',
        title: 'AC repair service Vijayawada',
        source: 'online',
        destinationUrl: 'https://www.urbancompany.com/vijayawada-ac-repair',
        price: 499,
        priceVerified: false,
      );
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '902', matches: [page]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need AC repair service in Vijayawada, show me');
      expect(find.text('Page mentions ₹499'), findsOneWidget);
      expect(find.text('₹499'), findsNothing);
    });

    testWidgets('catering: a saved need shows the REAL broadcast count, not "saved"', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '903', matches: [], broadcastSent: 4,
            sourceStatus: {'askodox': 'no_results', 'nearby': 'no_results'}),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need 10 catering staff tomorrow 6 pm in Vijayawada, ₹800 each, show me');
      expect(h.matches.deals, hasLength(1));
      expect(find.textContaining('sent your request to 4 registered ASKODOX provider(s)'), findsOneWidget);
      expect(find.textContaining('I saved your need'), findsNothing);
    });

    testWidgets('parcel with pickup + drop + time is searched at once -- no repeated questions', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '904', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'send a document from Benz Circle Vijayawada to Kukatpally Hyderabad tomorrow');
      expect(find.textContaining('Where does it start'), findsNothing);
      expect(find.textContaining('Where should it go'), findsNothing);
      expect(h.matches.deals, hasLength(1));
      final deal = h.matches.deals.single;
      expect(deal.intent, DealIntent.sendParcel);
      expect(deal.subject, isNot(contains('Hyderabad')), reason: 'route words never match listings');
      expect(deal.dynamicFields['to'], 'Kukatpally Hyderabad');
    });

    testWidgets('job seeker: skill + salary give results, never "Matching is unavailable"', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '905', matches: [], sourceStatus: {'askodox': 'no_results'}),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need a delivery driver job in Vijayawada, salary 18000, show me');
      expect(h.matches.deals, hasLength(1));
      expect(h.matches.deals.single.intent, DealIntent.seekWork);
      expect(askodoxEffectiveSubject(h.matches.deals.single), isNotNull);
      expect(find.textContaining('Matching is unavailable'), findsNothing);
      expect(find.textContaining('#905 stays open'), findsOneWidget);
    });

    testWidgets('electric scooter: a buyer search with its own slots; web price stays unverified', (tester) async {
      const shop = UniversalMatch(
        id: 'online-0-ev.example.in',
        title: 'Electric scooter 2 kW -- EV Store',
        source: 'online',
        destinationUrl: 'https://ev.example.in/p/scooter',
        price: 89999,
        priceVerified: false,
      );
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '907', matches: [shop]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I want to buy an electric scooter in Vijayawada under ₹1,00,000, show me');
      expect(h.matches.deals, hasLength(1));
      expect(h.matches.deals.single.intent, DealIntent.buy);
      expect(askodoxEffectiveSubject(h.matches.deals.single)?.toLowerCase(), contains('scooter'));
      expect(find.text('Page mentions ₹89999'), findsOneWidget);
      expect(h.listings.listed, isEmpty, reason: 'a buyer is never switched to Seller');
    });

    testWidgets('insurance: an online page opens its source link, never a fake "Send request"', (tester) async {
      const page = UniversalMatch(
        id: 'online-0-ins.example.in',
        title: 'Two wheeler insurance -- buy online',
        source: 'online',
        destinationUrl: 'https://ins.example.in/buy',
      );
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '908', matches: [page], nextActions: ['refer_provider']),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need two wheeler insurance in Vijayawada, show me');
      expect(h.matches.deals, hasLength(1));
      expect(find.text('Two wheeler insurance -- buy online'), findsOneWidget);
      expect(find.text('Send request'), findsNothing, reason: 'web pages are link-only');
      expect(find.byKey(const Key('askodoxReferProvider')), findsNothing, reason: 'no unsolicited referral prompt');
      expect(find.byKey(const Key('askodoxJoinAsProvider')), findsNothing, reason: 'no unsolicited join prompt');
    });

    testWidgets('browsing "best selling TV" keeps the Buyer role and never lists an item', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '906', matches: [_registeredTv]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'show me the best selling 43 inch TV under ₹30,000');
      expect(h.matches.deals.single.intent, DealIntent.buy);
      expect(h.listings.listed, isEmpty, reason: 'no listing published from a buyer search');
      expect(find.textContaining('Seller'), findsNothing);
    });
  });

  group('advisory, refer-to-ASKODOX, offers and route pins', () {
    testWidgets('contextual advice shows as a short notice under results', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '950', matches: [_localMatch], advice: [
          (text: 'For 10 people, ask 1-2 backup staff to stay available.', textTe: 'బ్యాకప్ సిబ్బంది'),
        ]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need 10 catering staff tomorrow in Vijayawada, show me');
      expect(find.byKey(const ValueKey('askodoxAdvice-0')), findsOneWidget);
      expect(find.textContaining('backup staff'), findsOneWidget);
    });

    testWidgets('no ASKODOX provider: "Refer them to ASKODOX" creates a real referral invite', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '951', matches: [], nextActions: ['refer_provider', 'find_more']),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need a welder in Vijayawada, show me -- or I can refer one');
      await tester.ensureVisible(find.byKey(const Key('askodoxReferProvider')));
      await tester.tap(find.byKey(const Key('askodoxReferProvider')));
      await _Harness.settle(tester);
      expect(h.growth.referrals.single.dealId, '951');
      expect(h.growth.referrals.single.category.toLowerCase(), contains('welder'));
      expect(find.textContaining('Referral code ASK1A2B3C'), findsOneWidget);
    });

    testWidgets('guests are asked to sign in only when they refer (browsing stayed open)', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '', matches: [], nextActions: ['refer_provider']),
      ]));
      h.growth.signedIn = false;
      await h.pump(tester);
      await h.send(tester, 'I need a welder in Vijayawada, show me -- or I can refer one');
      expect(find.textContaining('Sign in'), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('askodoxReferProvider')));
      await tester.tap(find.byKey(const Key('askodoxReferProvider')));
      await _Harness.settle(tester);
      expect(find.textContaining('Sign in to refer someone'), findsOneWidget);
    });

    testWidgets('guest refer: sign-in opens, then the SAME referral resumes (category, place, request kept)',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '953', matches: [], nextActions: ['refer_provider']),
      ]))
        ..signedIn = false
        ..withRouter = true;
      h.growth.signedIn = false;
      await h.pump(tester);
      await h.send(tester, 'I need a welder in Vijayawada, show me -- or I can refer one');
      await tester.ensureVisible(find.byKey(const Key('askodoxReferProvider')));
      await tester.tap(find.byKey(const Key('askodoxReferProvider')));
      await _Harness.settle(tester);
      expect(find.byKey(const Key('fakeOtpVerify')), findsOneWidget, reason: 'guests go to real sign-in');
      await tester.tap(find.byKey(const Key('fakeOtpVerify')));
      await _Harness.settle(tester);
      expect(h.growth.referrals.single.dealId, '953');
      expect(h.growth.referrals.single.category.toLowerCase(), contains('welder'));
      expect(find.textContaining('Referral code ASK1A2B3C'), findsOneWidget);
      expect(find.textContaining('I need a welder in Vijayawada'), findsWidgets, reason: 'the conversation is kept');
    });

    testWidgets('"Seller or provider? Join ASKODOX" continues in the same chat as the supply side',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '954', matches: [], nextActions: ['refer_provider']),
        const UniversalMatchResult(dealId: '955', matches: []),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need a welder in Vijayawada, show me -- or I can refer one');
      expect(find.text('Seller or provider? Join ASKODOX'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('askodoxJoinAsProvider')));
      await tester.tap(find.byKey(const Key('askodoxJoinAsProvider')));
      await _Harness.settle(tester);
      final said = find.textContaining(RegExp(r'I provide welder.* service in Vijayawada|I sell welder.* in Vijayawada',
          caseSensitive: false));
      expect(said, findsWidgets, reason: 'category and place are carried over');
      expect(find.textContaining('I need a welder in Vijayawada'), findsWidgets, reason: 'earlier chat is kept');
    });

    testWidgets('guest "contact the seller" -> sign in -> the SAME Send request runs', (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('Sign in required -- no session token was sent')]),
        products: [
          {'id': '42', 'title': 'Mixer grinder — 750W', 'subtitle': '₹3,200 • Vijayawada', 'price': 3200, 'provider_id': ''},
        ],
      )
        ..signedIn = false
        ..withRouter = true;
      await h.pump(tester);
      await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
      await h.send(tester, 'Please contact the seller');
      expect(h.orders.placed, isEmpty);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxSignInToAct')));
      await tester.tap(find.byKey(const ValueKey('askodoxSignInToAct')));
      await _Harness.settle(tester);
      await tester.tap(find.byKey(const Key('fakeOtpVerify')));
      await _Harness.settle(tester);
      expect(h.orders.placed, ['42'], reason: 'the exact action resumes after sign-in');
      expect(find.textContaining('Request sent to "Mixer grinder — 750W"'), findsOneWidget);
    });

    testWidgets('partner (affiliate) rows come after local ones, are labelled, open via the tracked redirect',
        (tester) async {
      const partner = UniversalMatch(
        id: 'partner-example-mart', title: '43 inch TV on Example Mart', source: 'online', segment: 'partner',
        sourceName: 'Example Mart', affiliate: true, disclosure: 'Partner link -- ASKODOX may earn a commission.',
        destinationUrl: 'https://mart.example/s?k=43+inch+TV&subid=ck1', clickId: 'ck1', redirectPath: '/go/ck1',
        priceVerified: false,
      );
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '956', matches: [_registeredTv, partner]),
      ]));
      await h.pump(tester);
      await h.send(tester, '43 inch TV ₹30,000 show me');
      _expectKind('affiliate');
      final partnerCard = find.byKey(const ValueKey('askodoxResultCard-online-partner-example-mart'));
      final localCard = find.byKey(ValueKey('askodoxResultCard-${_registeredTv.source}-${_registeredTv.id}'));
      expect(tester.getTopLeft(localCard).dx, lessThan(tester.getTopLeft(partnerCard).dx), reason: 'local first');
      expect(find.byKey(const ValueKey('askodoxPaidBadge-partner-example-mart')), findsOneWidget,
          reason: 'affiliate rows are disclosed');
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxDetails-partner-example-mart')));
      await tester.tap(find.byKey(const ValueKey('askodoxDetails-partner-example-mart')));
      await _Harness.settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxOpen-partner-example-mart')));
      await tester.tap(find.byKey(const ValueKey('askodoxOpen-partner-example-mart')));
      await _Harness.settle(tester);
      expect(h.partnerTracker.events, [('ck1', 'card_view'), ('ck1', 'click')]);
      expect(h.partnerTracker.openUri(partner).toString(), 'https://api.askodox.test/go/ck1');
      expect(h.partnerTracker.openUri(_registeredTv), isNull, reason: 'non-partner rows keep their own link');
    });

    testWidgets('verified offers show compactly; terms and coupon claim come from the server', (tester) async {
      const withBenefits = UniversalMatch(id: '78', title: 'Sony 43 inch TV', source: 'local', segment: 'registered',
          price: 25000, benefits: {
            'offers': [
              {'id': 1, 'name': 'Card offer', 'provider': 'Bank A', 'type': 'bank_card', 'kind': 'instant_discount',
               'value': 2000, 'conditions': [{'type': 'payment_method', 'value': ['Bank A credit card']},
                                            {'type': 'min_purchase', 'value': 20000}],
               'expires_at': '2026-10-31T23:59:00+05:30', 'verified_at': '2026-09-28T10:00:00+00:00',
               'source_url': 'https://banka.example/offers/tv', 'claimable': false},
              {'id': 2, 'name': 'ASKODOX coupon', 'provider': '', 'type': 'coupon', 'kind': 'coupon', 'value': 500,
               'conditions': [], 'claimable': true},
            ],
            'more': 0,
            'comparison_note': "Values depend on each offer's conditions (payment method, minimum purchase, limits).",
          });
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '957', matches: [withBenefits]),
      ]));
      await h.pump(tester);
      await h.send(tester, '43 inch TV ₹30,000 show me');
      expect(find.text('2 offer(s) · up to ₹2000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('askodoxBenefits-78')));
      await _Harness.settle(tester);
      expect(find.text('₹2000 instant discount'), findsOneWidget);
      expect(find.text('Pay with: Bank A credit card'), findsOneWidget);
      expect(find.text('Min purchase: ₹20000'), findsOneWidget);
      expect(find.text('Valid till: 2026-10-31'), findsOneWidget);
      expect(find.textContaining('best'), findsNothing, reason: 'never claims a best offer');
      await tester.tap(find.byKey(const ValueKey('askodoxBenefitTerms-1')));
      await _Harness.settle(tester);
      expect(h.benefits.opened, [1]);
      await tester.tap(find.byKey(const ValueKey('askodoxBenefitClaim-2')));
      await _Harness.settle(tester);
      expect(h.benefits.claimed, [2]);
      expect(find.byKey(const ValueKey('askodoxCouponCode-2')), findsOneWidget);
      expect(find.text('SAVE500A'), findsOneWidget);
    });

    testWidgets('a live offer shows on the registered result card', (tester) async {
      const withOffer = UniversalMatch(id: '77', title: 'Sony 43 inch TV', source: 'local', segment: 'registered',
          price: 25000, offerTitle: 'Diwali 10% off');
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '952', matches: [withOffer]),
      ]));
      await h.pump(tester);
      await h.send(tester, '43 inch TV ₹30,000 show me');
      expect(find.textContaining('Diwali 10% off'), findsOneWidget);
    });

    testWidgets('provider leads inbox: a broadcast request shows and "I can do this" sends real interest',
        (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '960', matches: []),
      ]));
      h.growth.leadList = const [
        AskodoxLead(requestId: '42', message: 'New ASKODOX request: catering staff, qty 10, in Vijayawada'),
      ];
      await h.pump(tester);
      expect(find.byKey(const Key('askodoxLeadsInbox')), findsOneWidget);
      expect(find.textContaining('catering staff, qty 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('askodoxLeadReply-42')));
      await _Harness.settle(tester);
      expect(h.growth.interests, ['42']);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('a parcel missing pickup/drop offers real map pins instead of re-asking', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '953', matches: [_localMatch]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'I need to send a parcel');
      expect(find.byKey(const Key('askodoxRoutePins')), findsOneWidget);
      expect(find.byKey(const Key('askodoxPickPickup')), findsOneWidget);
      expect(find.byKey(const Key('askodoxPickDrop')), findsOneWidget);
      expect(h.matches.deals, isEmpty, reason: 'nothing searched before the route is known');
    });
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

    for (final kind in ['local', 'used', 'online', 'videos']) {
      _expectKind(kind);
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


  testWidgets('a video ask searches even when the AI files it as chat (real production decision)',
      (tester) async {
    const video = UniversalMatch(
      id: 'video-yt_cgQhFuIFREs', title: 'Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026]',
      source: 'video', segment: 'video', sourceName: 'Udrawat', videoId: 'yt_cgQhFuIFREs',
      destinationUrl: 'https://www.youtube.com/watch?v=cgQhFuIFREs',
      embedUrl: 'https://www.youtube-nocookie.com/embed/cgQhFuIFREs?playsinline=1&rel=0',
      disclosure: "Creator's opinion -- not verified by ASKODOX",
    );
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: 'v1', matches: [video], sourceStatus: {'videos': 'ok'}),
      ]),
      // Exactly what production's model answered (proof run 36581475451).
      assistant: _Assistant((_) => {
            'reply': 'Here are review videos for the Samsung 43-inch TV.', 'domain': 'GENERAL',
            'transactional': false, 'action': 'search_reviews', 'confidence': 0.95, 'source': 'universal_ai',
            'entities': {'subject': 'TV review videos', 'brand': 'Samsung', 'size': '43 inch',
                'location': 'Vijayawada'},
          }),
    );
    await h.pump(tester);
    await h.send(tester, 'Samsung 43 inch TV review videos in Vijayawada');
    await tester.pumpAndSettle();
    expect(find.textContaining('screen size'), findsNothing, reason: 'no purchase questions for a video ask');
    expect(h.matches.deals, isNotEmpty, reason: 'the video ask ran the real discovery');
    expect(find.textContaining('Samsung 43 Inch Crystal UHD'), findsWidgets, reason: 'real video shown');
    expect(find.text('Here are review videos for the Samsung 43-inch TV.'), findsNothing,
        reason: 'never an AI claim of results');
  });

  testWidgets('a video ask shows videos even when the AI asks a clarifying question (real production decision)',
      (tester) async {
    const video = UniversalMatch(
      id: 'video-yt_KOYoiZG5_3E', title: 'Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best??',
      source: 'video', segment: 'video', sourceName: 'Crazyy Unboxing', videoId: 'yt_KOYoiZG5_3E',
      destinationUrl: 'https://www.youtube.com/watch?v=KOYoiZG5_3E',
      embedUrl: 'https://www.youtube-nocookie.com/embed/KOYoiZG5_3E?playsinline=1&rel=0',
      disclosure: "Creator's opinion -- not verified by ASKODOX",
    );
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: 'v1', matches: [video], sourceStatus: {'videos': 'ok'}),
      ]),
      // What production's model answered for "AC service video" (proof run 36599793393).
      assistant: _Assistant((_) => {
            'reply': 'Are you looking for an AC service tutorial video, or do you want to book an AC servicing technician?',
            'domain': 'SERVICE', 'transactional': true, 'action': 'clarify_need', 'confidence': 0.8,
            'source': 'universal_ai',
            'entities': {'subject': 'AC service', 'clarify_options': ['AC service tutorial video', 'Book AC service technician']},
          }),
    );
    await h.pump(tester);
    await h.send(tester, 'AC service video');
    await tester.pumpAndSettle();
    expect(find.text('Book AC service technician'), findsNothing, reason: 'no clarifying question for a video ask');
    expect(h.matches.deals, isNotEmpty, reason: 'the video ask ran the real discovery');
    expect(find.textContaining('Urban Company AC Service'), findsWidgets, reason: 'real video shown');
  });

  // APK 1285 real phone: the deal's raw_text is the app's rewrite ("i want to
  // buy chicken biryani in Vijayawada"); the backend reads the customer's own
  // words ("videos, ... offers") from trace.query. Keep both on every search.
  testWidgets('signed-in search keeps the customer\'s own words (videos/offers) in trace.query', (tester) async {
    final h = _Harness(
      matches: _FakeMatchRepository([_productionResult('discover_biryani_mixed.json')]),
      assistant: _Assistant((_) => {
            'reply': 'సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను -- ఫలితాలు కింద కనిపిస్తాయి.',
            'domain': 'PRODUCT', 'transactional': true, 'action': 'search_videos', 'confidence': 0.95,
            'source': 'universal_ai', 'entities': {'subject': 'chicken biryani', 'location': 'Vijayawada'},
          }),
    );
    await h.pump(tester, locale: 'te');
    const said = 'Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు';
    await h.send(tester, said);
    await tester.pumpAndSettle();
    expect(h.matches.deals, hasLength(1));
    expect(h.matches.deals.single.subject, 'chicken biryani');
    expect(h.matches.traces.single?['query'], said, reason: 'the backend derives videos/offers from these words');
  });

  group('compact same-page results (mixed groups, categories, conversation below)', () {
    const mixedTe = 'Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు';
    Map<String, Object?> searchDecision(String lang) => {
          'reply': lang == 'te'
              ? 'సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను -- ఫలితాలు కింద కనిపిస్తాయి.'
              : 'Sure -- looking for real videos and reviews; the results appear below.',
          'domain': 'FOOD', 'transactional': true, 'action': 'search_videos', 'confidence': 0.95,
          'source': 'universal_ai', 'entities': {'subject': 'chicken biryani', 'location': 'Vijayawada'},
        };
    Finder cards() => find.byWidgetPredicate(
        (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxResultCard-'));
    Finder thumbs() => find.byWidgetPredicate(
        (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxVideoThumb-'));

    _Harness mixed({String lang = 'te', int searches = 1}) {
      var n = 0;
      return _Harness(
        matches: _FakeMatchRepository([_productionResult('discover_biryani_mixed.json')]),
        assistant: _Assistant((_) => n++ < searches ? searchDecision(lang) : null),
      );
    }

    for (final (lang, text) in [
      ('te', mixedTe),
      ('en', 'Vijayawada chicken biryani videos, restaurants, online links and offers'),
      ('en', 'chicken biryani వీడియోలు, restaurants, online links, offers చూపించు'),
    ]) {
      testWidgets('mixed request ($lang): LOCAL + DEALS + ONLINE + VIDEOS from the real production payload',
          (tester) async {
        final h = mixed(lang: lang);
        await h.pump(tester, locale: lang);
        await h.send(tester, text);
        await tester.pumpAndSettle();
        expect(h.matches.deals, hasLength(1), reason: 'ONE discovery returns every group');
        for (final kind in ['all', 'local', 'deals', 'online', 'videos']) {
          expect(find.byKey(ValueKey('askodoxCompareTab-$kind')), findsOneWidget, reason: kind);
        }
        // "All": at most 2 previews per group, "View all" for the rest.
        expect(cards(), findsNWidgets(1 + 1 + 2 + 2));
        expect(find.byKey(const ValueKey('askodoxViewAll-online')), findsOneWidget);
        expect(find.byKey(const ValueKey('askodoxViewAll-videos')), findsOneWidget);
        expect(find.byKey(const ValueKey('askodoxViewAll-local')), findsNothing, reason: 'only 1 local row');
        expect(find.text(lang == 'te' ? 'అన్ని చూడండి' : 'View all'), findsNWidgets(2));
        // Real YouTube card: thumbnail, title, channel, duration.
        expect(find.byKey(const ValueKey('askodoxVideoThumb-video-yt-0-P8NlIQPsXNY')), findsOneWidget);
        expect(find.textContaining('Full Bucket Biryani Unboxing'), findsOneWidget);
        expect(find.text('Chetana Foods'), findsWidgets);
        expect(find.text('0:15'), findsOneWidget);
      });
    }

    testWidgets('category switching: a selected category shows only its compact results; All restores previews',
        (tester) async {
      final h = mixed();
      await h.pump(tester, locale: 'te');
      await h.send(tester, mixedTe);
      await tester.pumpAndSettle();
      Future<void> tab(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey('askodoxCompareTab-$key')));
        await tester.tap(find.byKey(ValueKey('askodoxCompareTab-$key')));
        await tester.pumpAndSettle();
      }

      await tab('videos');
      expect(cards(), findsNWidgets(5));
      expect(thumbs(), findsNWidgets(5), reason: 'every video row has its thumbnail');
      expect(find.textContaining('KG BIRYANI'), findsNothing);
      await tab('online');
      expect(cards(), findsNWidgets(3));
      expect(thumbs(), findsNothing);
      await tab('deals');
      expect(cards(), findsOneWidget);
      expect(find.textContaining('EazyDiner'), findsOneWidget);
      await tab('local');
      expect(cards(), findsOneWidget);
      await tab('all');
      expect(cards(), findsNWidgets(6));
      // "View all" opens that category.
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxViewAll-videos')));
      await tester.tap(find.byKey(const ValueKey('askodoxViewAll-videos')));
      await tester.pumpAndSettle();
      expect(cards(), findsNWidgets(5));
    });

    testWidgets('layout: results above the latest conversation, then the input; compact card size', (tester) async {
      final h = mixed();
      await h.pump(tester, locale: 'te');
      await h.send(tester, mixedTe);
      await tester.pumpAndSettle();
      final context = find.byKey(const Key('askodoxResultContext'));
      expect(context, findsOneWidget);
      final input = find.byType(TextField).last;
      final userMessage = find.text(mixedTe).last;
      expect(tester.getBottomLeft(context).dy, lessThanOrEqualTo(tester.getTopLeft(userMessage).dy),
          reason: 'results sit above the conversation');
      expect(tester.getBottomLeft(userMessage).dy, lessThan(tester.getTopLeft(input).dy),
          reason: 'conversation sits above the input');
      expect(find.byKey(const ValueKey('askodoxChatResults-1')), findsOneWidget, reason: 'shown once, no duplicate');
      final card = find.byKey(const ValueKey('askodoxResultCard-video-video-yt-0-P8NlIQPsXNY'));
      expect(tester.getSize(card).width, askodoxCompactCardWidth + 8, reason: 'card + its 8px gap');
      expect(tester.getSize(card).height, lessThan(300), reason: 'compact row, not a tall card (test font is wider)');
      final thumb = tester.getSize(find.byKey(const ValueKey('askodoxVideoThumb-video-yt-0-P8NlIQPsXNY')));
      expect(thumb.width, lessThanOrEqualTo(96));
      // Folding the context keeps one line and gives the conversation room.
      await tester.tap(find.byKey(const Key('askodoxResultContextToggle')));
      await tester.pumpAndSettle();
      expect(cards(), findsNothing);
      await tester.tap(find.byKey(const Key('askodoxResultContextToggle')));
      await tester.pumpAndSettle();
      expect(cards(), findsNWidgets(6));
    });

    testWidgets('small phone (360x640): results, the latest message and a usable input on one screen',
        (tester) async {
      final h = mixed();
      await h.pump(tester, locale: 'te');
      tester.view.physicalSize = const Size(1080, 1920);
      await tester.pumpAndSettle();
      await h.send(tester, mixedTe);
      await tester.pumpAndSettle();
      const screen = Size(360, 640);
      final context = tester.getRect(find.byKey(const Key('askodoxResultContext')));
      expect(context.height, lessThanOrEqualTo(screen.height * .5), reason: 'results never take the whole screen');
      final input = tester.getRect(find.byType(TextField).last);
      expect(input.bottom, lessThanOrEqualTo(screen.height), reason: 'input on screen');
      expect(input.top, greaterThan(context.bottom));
      await tester.enterText(find.byType(TextField).last, 'ఏది తక్కువ ధర?');
      await tester.pump();
      expect(find.text('ఏది తక్కువ ధర?'), findsOneWidget, reason: 'the input is usable');
      expect(tester.takeException(), isNull, reason: 'no overflow on a small screen');
    });

    testWidgets('long conversation: the active results stay above the latest follow-up', (tester) async {
      final h = mixed();
      await h.pump(tester, locale: 'en');
      await h.send(tester, 'Vijayawada chicken biryani videos, restaurants, online links and offers');
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await h.send(tester, 'Which one is better, the first or the second? ($i)');
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('askodoxResultContext')), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxCompareTab-videos')), findsOneWidget);
      final latest = find.textContaining('(5)').last;
      expect(tester.getBottomLeft(find.byKey(const Key('askodoxResultContext'))).dy,
          lessThanOrEqualTo(tester.getTopLeft(latest).dy));
      final chatResults = find.byWidgetPredicate(
          (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxChatResults-'));
      expect(chatResults, findsOneWidget, reason: 'one results block, never repeated in the chat');
    });

    testWidgets('actions: video Play opens the in-app player; URL and offer clicks open their real links',
        (tester) async {
      final h = mixed();
      await h.pump(tester, locale: 'te');
      await h.send(tester, mixedTe);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxOpen-online-0-swiggy.com')));
      await tester.tap(find.byKey(const ValueKey('askodoxOpen-online-0-swiggy.com')));
      await _Harness.settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('askodoxOpen-deals-0-eazydiner.com')));
      await tester.tap(find.byKey(const ValueKey('askodoxOpen-deals-0-eazydiner.com')));
      await _Harness.settle(tester);
      expect(h.matches.clicks, [
        'https://www.swiggy.com/city/vijayawada/kg-biryani-benz-circle-and-auto-nagar-tulasi-nagar-rest360679',
        'https://www.eazydiner.com/vijayawada/restaurants/biryani',
      ]);
      for (final id in ['online-0-swiggy.com', 'video-yt-0-P8NlIQPsXNY']) {
        expect(find.byKey(ValueKey('askodoxSave-$id')), findsOneWidget, reason: 'Save on $id');
        expect(find.byKey(ValueKey('askodoxShare-$id')), findsOneWidget, reason: 'Share on $id');
        expect(find.byKey(ValueKey('askodoxDetails-$id')), findsOneWidget, reason: 'Details on $id');
      }
      const thumb = ValueKey('askodoxVideoThumb-video-yt-0-P8NlIQPsXNY');
      await tester.ensureVisible(find.byKey(thumb));
      await tester.tap(find.byKey(thumb));
      await tester.pumpAndSettle();
      expect(find.byType(AskodoxVideoViewerScreen), findsOneWidget);
      expect(h.embeddedVideos.single.toString(), startsWith('https://www.youtube-nocookie.com/embed/P8NlIQPsXNY'));
    });

    // One kind only: no tab row, every row shown (nothing hidden behind "View all").
    for (final (name, rows) in [
      ('local only', const [
        UniversalMatch(id: 'l1', title: 'Sri Biryani Point', source: 'external', segment: 'nearby_external',
            latitude: 16.51, longitude: 80.64, locationLabel: 'Benz Circle, Vijayawada'),
        UniversalMatch(id: 'l2', title: 'Ravi Biryani House', source: 'external', segment: 'nearby_external',
            latitude: 16.50, longitude: 80.65, locationLabel: 'Labbipet, Vijayawada'),
        UniversalMatch(id: 'l3', title: 'Hotel Annapurna', source: 'external', segment: 'nearby_external',
            latitude: 16.52, longitude: 80.63, locationLabel: 'Governorpet, Vijayawada'),
      ]),
      ('online only (generic HTTPS)', const [
        UniversalMatch(id: 'o1', title: 'Biryani order page', source: 'online', destinationUrl: 'https://a.example/b'),
        UniversalMatch(id: 'o2', title: 'Second store', source: 'online', destinationUrl: 'https://b.example/c'),
        UniversalMatch(id: 'o3', title: 'Third store', source: 'online', destinationUrl: 'https://c.example/d'),
      ]),
      ('deals only', const [
        UniversalMatch(id: 'd1', title: 'Flat 25% off biryani', source: 'online', segment: 'deals',
            destinationUrl: 'https://deals.example/1'),
        UniversalMatch(id: 'd2', title: 'Combo offer', source: 'online', segment: 'deals',
            destinationUrl: 'https://deals.example/2'),
        UniversalMatch(id: 'd3', title: 'Bank offer', source: 'online', segment: 'deals',
            destinationUrl: 'https://deals.example/3'),
      ]),
      ('videos only (YouTube)', const [
        UniversalMatch(id: 'v1', title: 'Biryani review 1', source: 'video', sourceName: 'Food Vlogs',
            destinationUrl: 'https://www.youtube.com/watch?v=abc123def45', imageUrl: 'https://i.ytimg.com/vi/abc123def45/hqdefault.jpg',
            duration: '4:10'),
        UniversalMatch(id: 'v2', title: 'Biryani review 2', source: 'video', sourceName: 'Taste Trips',
            destinationUrl: 'https://www.youtube.com/watch?v=xyz987uvw65', imageUrl: 'https://i.ytimg.com/vi/xyz987uvw65/hqdefault.jpg',
            duration: '9:02'),
        UniversalMatch(id: 'v3', title: 'Biryani review 3', source: 'video', sourceName: 'Street Eats',
            destinationUrl: 'https://www.youtube.com/watch?v=qwe456rty78', imageUrl: 'https://i.ytimg.com/vi/qwe456rty78/hqdefault.jpg',
            duration: '2:33'),
      ]),
      ('affiliate only', const [
        UniversalMatch(id: 'a1', title: 'Partner store A', source: 'online', affiliate: true,
            disclosure: 'Affiliate link', destinationUrl: 'https://partner.example/a'),
        UniversalMatch(id: 'a2', title: 'Partner store B', source: 'online', affiliate: true,
            disclosure: 'Affiliate link', destinationUrl: 'https://partner.example/b'),
        UniversalMatch(id: 'a3', title: 'Partner store C', source: 'online', affiliate: true,
            disclosure: 'Affiliate link', destinationUrl: 'https://partner.example/c'),
      ]),
    ]) {
      testWidgets('$name: every row shown compactly with its own action', (tester) async {
        final h = _Harness(matches: _FakeMatchRepository([UniversalMatchResult(dealId: 'k1', matches: rows)]));
        await h.pump(tester);
        await h.send(tester, 'chicken biryani in Vijayawada show me');
        await tester.pumpAndSettle();
        expect(cards(), findsNWidgets(3), reason: 'no preview limit for a single kind');
        expect(find.byKey(const ValueKey('askodoxCompareTab-all')), findsNothing, reason: 'one kind: no tab row');
        final first = rows.first;
        if (first.source == 'video') {
          expect(thumbs(), findsNWidgets(3));
          expect(find.text('4:10'), findsOneWidget);
        } else if (first.destinationUrl != null) {
          await tester.ensureVisible(find.byKey(ValueKey('askodoxOpen-${first.id}')));
          await tester.tap(find.byKey(ValueKey('askodoxOpen-${first.id}')));
          await _Harness.settle(tester);
          expect(h.matches.clicks, [first.destinationUrl]);
        } else {
          expect(find.byKey(ValueKey('askodoxDirections-${first.id}')), findsOneWidget, reason: 'Map / directions');
        }
      });
    }

    testWidgets('Local + Online only: two tabs plus All, no empty groups invented', (tester) async {
      final h = _Harness(matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: 'k2', matches: [
          UniversalMatch(id: 'l1', title: 'Sri Biryani Point', source: 'external', segment: 'nearby_external',
              latitude: 16.51, longitude: 80.64, locationLabel: 'Benz Circle, Vijayawada'),
          UniversalMatch(id: 'o1', title: 'Biryani order page', source: 'online', destinationUrl: 'https://a.example/b'),
        ]),
      ]));
      await h.pump(tester);
      await h.send(tester, 'chicken biryani in Vijayawada show me');
      await tester.pumpAndSettle();
      for (final kind in ['all', 'local', 'online']) {
        expect(find.byKey(ValueKey('askodoxCompareTab-$kind')), findsOneWidget, reason: kind);
      }
      expect(find.byKey(const ValueKey('askodoxCompareTab-videos')), findsNothing);
      expect(find.byKey(const ValueKey('askodoxCompareTab-deals')), findsNothing);
    });
  });

  group('production replay (exact production JSON + decisions)', () {
    testWidgets('Telugu YouTube ask: real video cards (thumbnail, title, channel) + online links + in-app playback',
        (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([_productionResult('discover_biryani_videos.json')]),
        assistant: _Assistant((_) => {
              'reply': 'సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను -- ఫలితాలు కింద కనిపిస్తాయి.',
              'domain': 'PRODUCT', 'transactional': true, 'action': 'search_videos', 'confidence': 0.95,
              'source': 'universal_ai', 'entities': {'subject': 'Vijayawada chicken biryani', 'location': 'Vijayawada'},
            }),
      );
      await h.pump(tester, locale: 'te');
      await h.send(tester, 'Vijayawada chicken biryani YouTube videos చూపించు');
      await tester.pumpAndSettle();
      expect(h.matches.deals, isNotEmpty, reason: 'discovery ran');
      const thumb = ValueKey('askodoxVideoThumb-video-yt-0-P8NlIQPsXNY');
      expect(find.byKey(thumb), findsOneWidget, reason: 'YouTube card with thumbnail');
      expect(find.textContaining('Full Bucket Biryani Unboxing'), findsWidgets, reason: 'video title');
      expect(find.text('Chetana Foods'), findsWidgets, reason: 'channel');
      expect(find.textContaining('KG BIRYANI in Tulasi Nagar'), findsWidgets, reason: 'online link card');
      await tester.ensureVisible(find.byKey(thumb));
      await tester.tap(find.byKey(thumb));
      await tester.pumpAndSettle();
      expect(find.byType(AskodoxVideoViewerScreen), findsOneWidget, reason: 'plays in ASKODOX');
      expect(h.embeddedVideos.single.toString(), startsWith('https://www.youtube-nocookie.com/embed/P8NlIQPsXNY'));
    });

    // ROOT CAUSE of "no links since ~1276/1277" (production logs: the phone sent
    // POST /api/in-app/assistant then POST /api/products/mine, never /deals):
    // with the Seller role saved on the device, every search was rewritten into
    // a SELL deal and published as a listing -- text reply, no results.
    for (final (lang, text, decision, fixture, visible) in [
      ('te', 'Vijayawada chicken biryani YouTube videos చూపించు', {
        'reply': 'సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను -- ఫలితాలు కింద కనిపిస్తాయి.',
        'domain': 'PRODUCT', 'transactional': true, 'action': 'search_videos', 'confidence': 0.95,
        'source': 'universal_ai', 'entities': {'subject': 'Vijayawada chicken biryani', 'location': 'Vijayawada'},
      }, 'discover_biryani_videos.json', 'Full Bucket Biryani Unboxing'),
      ('en', 'AC repair near me', {
        'reply': 'I can help you find AC repair services in Vijayawada.', 'domain': 'SERVICE', 'transactional': true,
        'action': 'search_service', 'confidence': 0.95, 'source': 'universal_ai',
        'entities': {'subject': 'AC repair', 'location': 'Vijayawada'},
      }, 'discover_ac_repair.json', 'AC Repair & Service in Vijaywada'),
    ]) {
      testWidgets('Seller role saved on the phone: a search ($lang) still searches and shows links, never lists',
          (tester) async {
        final h = _Harness(
          matches: _FakeMatchRepository([_productionResult(fixture)]),
          assistant: _Assistant((_) => decision),
        );
        await h.pump(tester, locale: lang);
        ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)))
            .read(askodoxRoleProvider.notifier)
            .setActive(AskodoxUserRole.seller);
        await _Harness.settle(tester);
        await h.send(tester, text);
        await tester.pumpAndSettle();
        if (h.matches.deals.isEmpty && h.listings.listed.isEmpty) {
          await h.send(tester, lang == 'te' ? 'చూపించు' : 'show me');
          await tester.pumpAndSettle();
        }
        expect(h.listings.listed, isEmpty, reason: 'a search is never published as the seller\'s listing');
        expect(h.matches.deals, isNotEmpty, reason: 'the search ran');
        expect(h.matches.deals.last.intent, isNot(DealIntent.sell));
        expect(find.textContaining(visible), findsWidgets, reason: 'real result cards are visible');
      });
    }

    testWidgets('Seller describing their own goods still creates a listing (seller flow intact)', (tester) async {
      final h = _Harness(
        matches: _FakeMatchRepository([const UniversalMatchResult(dealId: 's1', matches: [])]),
        assistant: _Assistant((_) => {
              'reply': 'Great, I can list your fresh tomatoes.', 'domain': 'PRODUCT', 'transactional': true,
              'action': 'list_product', 'confidence': 0.9, 'source': 'universal_ai',
              'entities': {'subject': 'tomatoes', 'quantity': 50, 'unit': 'kg', 'price': 30},
            }),
      );
      await h.pump(tester);
      ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)))
          .read(askodoxRoleProvider.notifier)
          .setActive(AskodoxUserRole.seller);
      await _Harness.settle(tester);
      await h.send(tester, '50 kg fresh tomatoes at 30 rupees per kg');
      await tester.pumpAndSettle();
      for (var i = 0; i < 4 && h.listings.listed.isEmpty; i++) {
        await h.send(tester, 'Vuyyuru');
        await tester.pumpAndSettle();
      }
      expect(h.listings.listed, isNotEmpty, reason: 'a seller offering goods is still listed');
    });

    for (final (lang, text, reply) in [
      ('en', 'AC repair near me', 'I can help you find AC repair services in Vijayawada. What type of AC is it, or what issue are you facing?'),
      ('te', 'AC రిపేర్ కావాలి', 'విజయవాడలో AC రిపేర్ సర్వీస్ కోసం వివరాలు వెతుకుతున్నాను.'),
    ]) {
      testWidgets('service ask ($lang): real online result cards with links appear', (tester) async {
        final h = _Harness(
          matches: _FakeMatchRepository([_productionResult('discover_ac_repair.json')]),
          assistant: _Assistant((_) => {
                'reply': reply, 'domain': 'SERVICE', 'transactional': true, 'action': 'search_service',
                'confidence': 0.95, 'source': 'universal_ai',
                'entities': {'subject': 'AC repair', 'category': 'appliance repair', 'location': 'Vijayawada'},
              }),
        );
        await h.pump(tester, locale: lang);
        await h.send(tester, text);
        await tester.pumpAndSettle();
        // A detail question may come first; "show me" must then show the cards.
        if (h.matches.deals.isEmpty) {
          await h.send(tester, lang == 'te' ? 'చూపించు' : 'show me');
          await tester.pumpAndSettle();
        }
        expect(h.matches.deals, isNotEmpty, reason: 'discovery ran');
        expect(find.textContaining('AC Repair & Service in Vijaywada'), findsWidgets, reason: 'online card');
        expect(find.textContaining('Professional AC service'), findsWidgets);
      });
    }
  });

  // Real-content video proof (opt-in; run by .github/workflows/
  // video-real-content-proof.yml): the rows, thumbnails, explanations and
  // AI answers are the REAL ones that run captured.
  //   ASKODOX_VIDEO_PROOF=<dir with proof.json, thumbs.json, thumbs/>
  //   flutter test --update-goldens --plain-name "Real video proof"
  testWidgets('Real video proof render: search, videos, watch, ask, next step (EN + TE)',
      skip: !Platform.environment.containsKey('ASKODOX_VIDEO_PROOF'), (tester) async {
    final dir = Platform.environment['ASKODOX_VIDEO_PROOF']!;
    final proof = jsonDecode(File('$dir/proof.json').readAsStringSync()) as Map<String, dynamic>;
    final thumbs = jsonDecode(File('$dir/thumbs.json').readAsStringSync()) as Map<String, dynamic>;
    final out = Directory('$dir/renders')..createSync(recursive: true);
    Future<void> font(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files.where((f) => File(f).existsSync())) {
        loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
      await loader.load();
    }

    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/root/sdk/flutter';
    final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final telugu = Platform.environment['ASKODOX_TELUGU_FONT'] ?? '$dir/NotoSansTelugu-Regular.ttf';
    await tester.runAsync(() async {
      // Telugu glyphs come from Noto Sans Telugu in the same family.
      await font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf',
          '$fonts/Roboto-Black.ttf']);
      await font('NotoSansTelugu', [telugu]);
      await font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
      // Real thumbnails, pre-decoded into the image cache under their URLs.
      for (final entry in thumbs.entries) {
        final file = File('$dir/thumbs/${entry.value}');
        if (!file.existsSync()) continue;
        try {
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final frame = await codec.getNextFrame();
          PaintingBinding.instance.imageCache.putIfAbsent(
              NetworkImage(entry.key), () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: frame.image))));
        } catch (_) {
          // an undecodable image keeps the card's normal fallback
        }
      }
    });
    Future<void> shot(String name) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await _Harness.settle(tester);
      }
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('${out.path}/$name.png')));
    }

    // Scroll a target to the middle of its list (not under a header) before tapping.
    Future<void> centre(Finder target) async {
      await tester.runAsync(() => Scrollable.ensureVisible(tester.element(target.first), alignment: 0.5));
      await tester.pumpAndSettle();
    }

    for (final label in ['electronics', 'electronics-te', 'service']) {
      final c = (proof['cases'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['label'] == label,
          orElse: () => <String, dynamic>{});
      final videos = (c['videos'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (videos.isEmpty) continue;
      final te = c['language'] == 'te';
      final videoMatches = [
        for (final v in videos)
          UniversalMatch.fromJson({
            ...v, 'id': 'video-${v['video_id']}', 'source': 'video', 'match_source': 'video', 'segment': 'video',
            'subtitle': null,
          }),
      ];
      final nextOptions = [
        for (final (i, o) in ((c['next'] as Map?)?['options'] as List? ?? const []).cast<Map<String, dynamic>>().indexed)
          UniversalMatch.fromJson({...o, 'id': 'next-$i', 'source': o['match_source'] ?? 'online'}),
      ];
      final ai = (c['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
      final h = _Harness(
        matches: _FakeMatchRepository([
          UniversalMatchResult(dealId: 'proof-$label', matches: videoMatches, sourceStatus: const {'videos': 'ok'}),
          UniversalMatchResult(dealId: 'proof-$label-next', matches: nextOptions,
              sourceStatus: ((c['next'] as Map?)?['status'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
                  const {}),
        ]),
        // The REAL production AI decisions captured by the proof run: for
        // the search message itself and for "tell me more about this video".
        assistant: _Assistant((message) => message.contains('Option the user is asking about')
            ? {'reply': ai['reply'] ?? '', 'domain': 'PRODUCT', 'transactional': false, 'source': 'universal_ai'}
            : message.trim() == (c['text'] as String).trim()
                ? (c['search_decision'] as Map?)?.cast<String, Object?>()
                : null),
      );
      h.api = _ProofApi(c['explain'] as Map<String, dynamic>?);
      h.theme = ThemeData(fontFamily: 'Roboto', fontFamilyFallback: const ['NotoSansTelugu'], useMaterial3: true);
      await h.pump(tester, locale: te ? 'te' : 'en');
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      // The phone's location (as in the real app); discovery is local-first.
      final scope = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
      await tester.runAsync(() => scope.read(locationControllerProvider.notifier).selectManualLocation(
          const BuyerSavedLocation(id: 'proof', name: 'Vijayawada', address: 'Vijayawada, Andhra Pradesh',
              point: GeoPoint(16.5062, 80.648), type: SavedLocationType.custom)));
      await _Harness.settle(tester);
      await h.send(tester, c['text'] as String);
      await shot('${label}_1_search_videos');
      final thumb = find.byKey(ValueKey('askodoxVideoThumb-video-${videos.first['video_id']}'));
      expect(thumb, findsWidgets, reason: '$label: the real video must be shown for the video ask');
      await centre(thumb);
      await tester.tap(thumb);
      await tester.pumpAndSettle();
      await shot('${label}_2_watch');
      await centre(find.byKey(const Key('askodoxVideoAsk')));
      await tester.tap(find.byKey(const Key('askodoxVideoAsk')));
      await _Harness.settle(tester);
      await tester.pumpAndSettle();
      await shot('${label}_3_ask_ai_answer');
      await centre(thumb);
      await tester.tap(thumb);
      await tester.pumpAndSettle();
      final step = (c['next'] as Map?)?['step'] as String? ?? 'find_local';
      final chip = find.byKey(Key('askodoxVideoNext_$step'));
      await centre(chip);
      await tester.tap(chip);
      await _Harness.settle(tester);
      await tester.pumpAndSettle();
      await shot('${label}_4_next_step_options');
      expect(h.matches.deals, hasLength(2), reason: 'the next step ran the same discovery in the same chat');
      await tester.pumpWidget(const SizedBox());
    }
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
      await _tapVoice(tester);
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

    testWidgets('60 s of continuous Telugu speech records to the end and the full transcript is answered in Telugu voice',
        (tester) async {
      // Build 1241: ~35 s of Telugu became one word. The recording must run
      // for the whole utterance, finalize once, and hand the complete file
      // (not a chunk) to STT; the complete transcript drives the reply.
      mockRecorder(levels: [
        ...quiet(const Duration(milliseconds: 600)),
        for (var i = 0; i < 12; i++) ...[
          ...speech(const Duration(seconds: 4), level: 2400),
          ...quiet(const Duration(seconds: 1), level: 300), // breaths, not silence
        ],
        ...quiet(const Duration(seconds: 4)),
      ]);
      const longTranscript = 'నాకు విజయవాడలో రేపు ఉదయం పది గంటలకు రెండు కిలోల చికెన్ కావాలి '
          'స్కిన్‌లెస్ కర్రీ కట్ కావాలి డెలివరీ మా ఇంటికి కావాలి ధర ఎంత అవుతుందో కూడా చెప్పండి';
      final h = _Harness(
        matches: _FakeMatchRepository([StateError('unused')]),
        voiceTranscript: longTranscript,
        assistant: _Assistant((_) => {
              'reply': 'సరే, రెండు కిలోల స్కిన్‌లెస్ కర్రీ కట్ చికెన్ కోసం చూస్తున్నాను.',
              'domain': 'FOOD',
              'transactional': false,
              'confidence': 0.9,
              'source': 'universal_ai',
            }),
      );
      await h.pump(tester, locale: 'te');
      await _tapVoice(tester);
      await runFor(tester, const Duration(seconds: 58));
      expect(methods(), isNot(contains('stopVoiceRecording')), reason: 'still speaking at 58 s');

      await runFor(tester, const Duration(seconds: 10));

      expect(methods().where((m) => m == 'stopVoiceRecording'), hasLength(1), reason: 'finalized exactly once');
      expect(methods(), isNot(contains('cancelVoiceRecording')), reason: 'audio kept, not discarded');
      expect(levelPolls(), greaterThan(290), reason: 'recorded for the full ~60 s');
      expect(h.voice.calls.single, ('/cache/askodox_voice_1.m4a', 'te'), reason: 'the one complete file reaches STT');
      expect(find.text(longTranscript), findsOneWidget, reason: 'the full transcript, not the last word');
      final speak = calls.lastWhere((c) => c.method == 'speakReply');
      expect((speak.arguments as Map)['text'], 'సరే, రెండు కిలోల స్కిన్‌లెస్ కర్రీ కట్ చికెన్ కోసం చూస్తున్నాను.');
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
      await _tapVoice(tester);
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
      await _tapVoice(tester);
      await runFor(tester, const Duration(seconds: 3));
      expect(find.textContaining('Tap the companion again to stop'), findsOneWidget);

      await _tapVoice(tester);
      await _Harness.settle(tester);

      expect(methods(), contains('stopVoiceRecording'));
      expect(h.voice.calls, hasLength(1));
      expect(find.text('I need AC repair'), findsOneWidget);
    });

    testWidgets('no speech at all is reported after the long timeout, chat untouched', (tester) async {
      mockRecorder(levels: quiet(const Duration(seconds: 30)));
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await _tapVoice(tester);
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
      await _tapVoice(tester);
      await runFor(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('askodoxVoiceCancel')));
      await _Harness.settle(tester);

      expect(methods(), contains('cancelVoiceRecording'));
      expect(methods(), isNot(contains('stopVoiceRecording')));
      expect(h.voice.calls, isEmpty);
      // Back to idle: the voice panel (and its stop hint) is gone.
      expect(find.byKey(const Key('askodoxVoiceStopHint')), findsNothing);
      expect(find.byKey(const Key('askodoxVoiceElapsed')), findsNothing);
    });

    testWidgets('microphone permission denied shows a clear error and no fallback recognizer',
        (tester) async {
      mockRecorder(startError: PlatformException(code: 'mic_denied'));
      final h = _Harness(matches: _FakeMatchRepository([StateError('unused')]));
      await h.pump(tester);
      await _tapVoice(tester);
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
      await _tapVoice(tester);
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
      await _tapVoice(tester);
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

      await _tapVoice(tester);
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
      await _tapVoice(tester);
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
      await _tapVoice(tester);
      await runFor(tester, const Duration(seconds: 8));
      expect(find.text('Speaking…'), findsOneWidget);

      await _tapVoice(tester);
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

  test('guests and expired sessions browse real results via /deals/discover (no sign-in wall)', () async {
    final deal = UniversalDeal(
      rawText: '43 inch TV show me',
      intent: DealIntent.buy,
      partyA: const DealPartyRequirement(side: DealSide.demand, role: 'buyer', action: 'buy'),
      partyB: const DealPartyRequirement(side: DealSide.supply, role: 'seller', action: 'sell'),
      subject: '43 inch TV',
    );
    const discover = {
      'matches': [
        {'id': 'online-0', 'source': 'online', 'title': 'TV', 'destination_url': 'https://a.b'},
      ],
      'source_status': {'master_web': 'ok'},
    };
    final guestClient = _RecordingClient({'/deals/discover': discover});
    final guest = ApiUniversalMatchRepository(guestClient, appUserId: 'guest-1', authToken: '');
    final result = await guest.createAndMatch(deal, trace: {'query': '43 inch TV show me'});
    expect(guestClient.posts.map((p) => p.$1), ['/deals/discover'], reason: 'no /deals create without sign-in');
    expect(result.dealId, isEmpty);
    expect(result.matches.single.id, 'online-0');
    expect(result.sourceStatus['master_web'], 'ok');
    final sentTrace = guestClient.posts.single.$2['trace'] as Map;
    expect(sentTrace['query'], '43 inch TV show me');
    expect(sentTrace['auth_gate'], contains('guest'));

    final expiredClient = _RecordingClient({'/deals/discover': discover}, unauthorized: {'/deals'});
    final expired = ApiUniversalMatchRepository(expiredClient, appUserId: 'app-1', authToken: 'old');
    final again = await expired.createAndMatch(deal);
    expect(expiredClient.posts.map((p) => p.$1), ['/deals', '/deals/discover']);
    expect(again.matches.single.id, 'online-0');
  });

  testWidgets('comparison flow: kind tabs filter, paid rows disclosed, Chat continues the SAME chat, Open is tracked',
      (tester) async {
    const local = UniversalMatch(id: '401', title: 'Sri Sai AC Services', source: 'local', segment: 'registered',
        ratingAverage: 4.6, reviewCount: 38, distanceKm: 1.2);
    const paid = UniversalMatch(id: 'sponsored-7', title: 'Blue Star 1.5 T AC', source: 'sponsored',
        segment: 'sponsored', sponsored: true, sponsoredLabel: 'Sponsored', clickId: 'spk1',
        redirectPath: '/go/sp/spk1', destinationUrl: 'https://ads.example/ac');
    const online = UniversalMatch(id: 'online-0-shop.example', title: 'LG 1.5 Ton AC', source: 'online',
        price: 42490, sourceName: 'shop.example', destinationUrl: 'https://shop.example/ac');
    final h = _Harness(
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '41', matches: [local, paid, online]),
      ]),
    );
    await h.pump(tester);
    await h.send(tester, 'I want to buy a 1.5 ton AC in Vijayawada');

    // Only the kinds this request returned, in column order.
    for (final kind in ['all', 'local', 'sponsored', 'online']) {
      expect(find.byKey(ValueKey('askodoxCompareTab-$kind')), findsOneWidget, reason: kind);
    }
    for (final kind in ['deals', 'affiliate', 'used', 'surplus', 'videos', 'jobs']) {
      expect(find.byKey(ValueKey('askodoxCompareTab-$kind')), findsNothing, reason: kind);
    }
    final x = [local, paid, online]
        .map((m) => tester.getTopLeft(find.byKey(ValueKey('askodoxResultCard-${m.source}-${m.id}'))).dx)
        .toList();
    expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: 'LOCAL | SPONSORED | ONLINE');
    // The paid row carries its disclosure, never the organic LOCAL label.
    expect(find.byKey(const ValueKey('askodoxPaidBadge-sponsored-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxKindLabel-sponsored-7')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxKindLabel-401')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPaidBadge-401')), findsNothing, reason: 'organic stays unlabelled as paid');

    // A tab shows only that kind; tapping it again (or All) shows every kind.
    await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-sponsored')));
    await tester.pump();
    expect(find.byKey(const ValueKey('askodoxResultCard-sponsored-sponsored-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxResultCard-local-401')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('askodoxResultCard-local-401')), findsOneWidget);

    // Paid links open through ASKODOX's tracked redirect; organic links open directly.
    expect(h.partnerTracker.openUri(paid).toString(), 'https://api.askodox.test/go/sp/spk1');
    expect(h.partnerTracker.openUri(online).toString(), 'https://shop.example/ac');

    // Chat on a card: the conversation continues below, no new search.
    final searches = h.matches.deals.length;
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxAsk-401')));
    await tester.tap(find.byKey(const ValueKey('askodoxAsk-401')));
    await _Harness.settle(tester);
    expect(find.textContaining('Sri Sai AC Services'), findsWidgets);
    expect(h.matches.deals, hasLength(searches), reason: 'asking about an option is not a new search');
    final results = tester.getTopLeft(find.byKey(const ValueKey('askodoxComparison'))).dy;
    final composer = tester.getTopLeft(find.byType(TextField)).dy;
    expect(results, lessThan(composer), reason: 'results above, input at the bottom');
  });

  testWidgets('a single option stays one full card (no comparison board)', (tester) async {
    final h = _Harness(matches: _FakeMatchRepository([
      const UniversalMatchResult(dealId: '42', matches: [_localMatch]),
    ]));
    await h.pump(tester);
    await h.send(tester, 'I want to buy a mixer grinder in Vijayawada');
    expect(find.byKey(const Key('askodoxComparison')), findsNothing);
    expect(find.byKey(ValueKey('askodoxResultCard-${_localMatch.source}-${_localMatch.id}')), findsOneWidget);
  });

  // Visual renders for comparison with the approved reference (opt-in:
  // ASKODOX_RENDER=1 flutter test --update-goldens --plain-name "Home render").
  testWidgets('Home render: home, local, comparison, selected + chat, companion actions, floating',
      skip: !Platform.environment.containsKey('ASKODOX_RENDER'), (tester) async {
    Future<void> font(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
      await loader.load();
    }

    const fonts = '/root/sdk/flutter/bin/cache/artifacts/material_fonts';
    await tester.runAsync(() async {
      await font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf',
          '$fonts/Roboto-Black.ttf']);
      await font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<void> shot(String name) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await _Harness.settle(tester);
      }
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('renders/$name.png'));
    }

    // Real-looking fixtures: only facts a source would return (nothing
    // invented by the app).
    const acLocal1 = UniversalMatch(id: '301', title: 'Sri Sai AC Services', subtitle: 'AC installation & repair',
        source: 'local', segment: 'registered', ratingAverage: 4.6, reviewCount: 38, distanceKm: 1.2,
        availability: 'Available today', locationLabel: 'Vuyyuru');
    const acLocal2 = UniversalMatch(id: 'external-p9', title: 'Cool Point Refrigeration', subtitle: 'Split AC installation',
        source: 'external', segment: 'nearby_external', ratingAverage: 4.3, reviewCount: 112, distanceKm: 2.8,
        sourceName: 'Google Maps', destinationUrl: 'https://maps.google.com/?cid=1', locationLabel: 'Vuyyuru');
    const sponsoredRow = UniversalMatch(id: 'sponsored-4', title: 'Blue Star 1.5 T Inverter AC', subtitle: 'Free installation',
        source: 'sponsored', segment: 'sponsored', sponsored: true, sponsoredLabel: 'Sponsored', price: 38990,
        priceVerified: false, sourceName: 'Advertiser', destinationUrl: 'https://ads.example/ac', offerTitle: '10% bank offer');
    const onlineRow = UniversalMatch(id: 'online-0-shop.example', title: 'LG 1.5 Ton 5 Star Split AC', source: 'online',
        price: 42490, sourceName: 'shop.example', availability: 'In stock', destinationUrl: 'https://shop.example/ac');
    final h = _Harness(
      // What the AI router returns for these two asks (service, then product).
      assistant: _Assistant((message) => message.contains('Tell me more') || message.contains('tomorrow')
          ? {
              'reply': message.contains('tomorrow')
                  ? 'I will ask Sri Sai AC Services about tomorrow and tell you here.'
                  : 'Sri Sai AC Services is 1.2 km away, rated 4.6 from 38 reviews, available today.',
              'transactional': false,
              'source': 'universal_ai',
            }
          : message.contains('installation')
          ? {
              'reply': 'Here are AC installation providers near Vuyyuru.',
              'domain': 'SERVICE',
              'transactional': true,
              'action': 'need_service',
              'confidence': 0.9,
              'source': 'universal_ai',
              'entities': {'service': 'AC installation', 'location': 'Vuyyuru'},
            }
          : {
              'reply': 'Here are 1.5 ton ACs -- local, sponsored and online, side by side.',
              'domain': 'PRODUCT',
              'transactional': true,
              'action': 'buy',
              'confidence': 0.9,
              'source': 'universal_ai',
              'entities': {'subject': '1.5 ton AC', 'location': 'Vuyyuru'},
            }),
      matches: _FakeMatchRepository([
        const UniversalMatchResult(dealId: '31', matches: [acLocal1, acLocal2]),
        const UniversalMatchResult(dealId: '32', matches: [acLocal1, sponsoredRow, onlineRow]),
      ]),
    )..withShell = true;
    await h.pump(tester);
    await shot('01_home');

    await h.send(tester, 'I need AC installation service in Vuyyuru');
    await shot('02_local_results');

    await h.send(tester, 'I want to buy a 1.5 ton AC in Vuyyuru');
    await shot('03_comparison');

    await _tapAsk(tester);
    await h.send(tester, 'Can they install it tomorrow?');
    await shot('04_selected_and_chat');

    await tester.tap(find.byKey(const Key('askodoxNavSpeak')));
    await tester.pump(const Duration(milliseconds: 400));
    await shot('05_companion_actions');
    await tester.tap(find.byKey(const Key('askodoxHubScrim')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxPrimaryHomeScreen)));
    container.read(askodoxInAppFloatProvider.notifier).setEnabled(true);
    await tester.tap(find.byKey(const Key('askodoxNavUpdates')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('askodoxFloatingCompanion')));
    await shot('06_floating_companion');
  });
}

// Compact same-page renders from the REAL production payload (opt-in:
// ASKODOX_RENDER=<out dir> flutter test --update-goldens --plain-name "Compact results render").
void _compactRenders() {
  testWidgets('Compact results render: mixed request (TE/EN), categories, follow-up, small phone',
      skip: !Platform.environment.containsKey('ASKODOX_RENDER'), (tester) async {
    final out = Platform.environment['ASKODOX_RENDER']!;
    Future<void> font(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files.where((f) => File(f).existsSync())) {
        loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
      await loader.load();
    }

    const fonts = '/root/sdk/flutter/bin/cache/artifacts/material_fonts';
    final telugu = Platform.environment['ASKODOX_TELUGU_FONT'] ?? '';
    await tester.runAsync(() async {
      await font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf',
          '$fonts/Roboto-Black.ttf']);
      await font('NotoSansTelugu', [telugu]);
      await font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    });
    Future<void> shot(String name) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await _Harness.settle(tester);
      }
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$out/$name.png')));
    }

    for (final (lang, text, size) in [
      ('te', 'Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు', const Size(1080, 2340)),
      ('en', 'Vijayawada chicken biryani videos, restaurants, online links and offers', const Size(1080, 2340)),
      ('te', 'Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు', const Size(1080, 1920)),
    ]) {
      var n = 0;
      final h = _Harness(
        matches: _FakeMatchRepository([_productionResult('discover_biryani_mixed.json')]),
        assistant: _Assistant((m) => n++ == 0
            ? {
                'reply': lang == 'te'
                    ? 'సరే, నిజమైన వీడియోలు, రెస్టారెంట్లు, లింకులు, ఆఫర్లు -- ఫలితాలు పైన కనిపిస్తాయి.'
                    : 'Here are real videos, restaurants, online links and offers -- results are above.',
                'domain': 'FOOD', 'transactional': true, 'action': 'search_videos', 'confidence': 0.95,
                'source': 'universal_ai', 'entities': {'subject': 'chicken biryani', 'location': 'Vijayawada'},
              }
            : {
                'reply': lang == 'te'
                    ? 'Swiggyలో KG BIRYANI ఆర్డర్ పేజీ ఉంది; EazyDinerలో బ్యాంక్ ఆఫర్లు కనిపిస్తున్నాయి -- ధర చెల్లించే ముందు నిర్ధారించుకోండి.'
                    : 'KG BIRYANI has an order page on Swiggy; EazyDiner lists bank offers -- confirm the price before paying.',
                'transactional': false, 'source': 'universal_ai',
              }),
      )
        // The shell applies the app's own light theme (the phone's system
        // font draws Telugu); the test renderer has no system font, so the
        // Telugu renders use the bare screen with a Telugu fallback font.
        ..withShell = lang != 'te'
        ..theme = ThemeData(fontFamily: 'Roboto', fontFamilyFallback: const ['NotoSansTelugu'], useMaterial3: true);
      await h.pump(tester, locale: lang);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final tag = '${lang}_${size.height.toInt() ~/ 3}';
      await h.send(tester, text);
      await shot('${tag}_1_all');
      if (size.height > 2000) {
        await tester.ensureVisible(find.byKey(const ValueKey('askodoxCompareTab-videos')));
        await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-videos')));
        await shot('${tag}_2_videos');
        await tester.ensureVisible(find.byKey(const ValueKey('askodoxCompareTab-local')));
        await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-local')));
        await shot('${tag}_3_local');
        await tester.ensureVisible(find.byKey(const ValueKey('askodoxCompareTab-all')));
        await tester.tap(find.byKey(const ValueKey('askodoxCompareTab-all')));
      }
      await h.send(tester, lang == 'te' ? 'వీటిలో ఏది మంచిది? ఆఫర్ ఉందా?' : 'Which of these is best? Any offer?');
      await shot('${tag}_4_followup');
    }
  });
}

class _RecordingClient extends _ScriptedClient {
  _RecordingClient(super.routes, {this.unauthorized = const {}});
  final Set<String> unauthorized;
  final List<(String, Map<String, Object?>)> posts = [];

  @override
  Future<ApiResult<T>> post<T>(String path,
      {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add((path, Map<String, Object?>.from((body as Map?) ?? const {})));
    if (unauthorized.contains(path)) {
      return ApiError<T>(const ApiFailure(ApiFailureType.authentication, statusCode: 401, message: 'expired'));
    }
    return super.post<T>(path, body: body, options: options);
  }
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


/// The companion (in-chat stage, or the Home companion before the first
/// message).
Finder _companion() => find.byKey(const Key('askodoxCompanionStage')).evaluate().isNotEmpty
    ? find.byKey(const Key('askodoxCompanionStage'))
    : find.byKey(const Key('askodoxHomeOrb'));

Future<void> _openCompanionHub(WidgetTester tester) async {
  await tester.ensureVisible(_companion().first);
  await tester.pump();
  await tester.tap(_companion().first);
  await tester.pump();
  expect(find.byKey(const Key('askodoxCompanionHub')), findsOneWidget);
}

/// Voice is the companion's: tap it -> Voice starts listening; while
/// listening, a tap on the companion stops ("tap again to stop").
Future<void> _tapVoice(WidgetTester tester) async {
  final listening = find.byKey(const Key('askodoxVoiceElapsed')).evaluate().isNotEmpty;
  if (listening) {
    await tester.ensureVisible(_companion().first);
    await tester.pump();
    await tester.tap(_companion().first);
    await tester.pump();
    return;
  }
  await _openCompanionHub(tester);
  await tester.tap(find.byKey(const ValueKey('askodoxHubAction-voice')));
  await tester.pump();
}


/// Replays the branch backend's real explain answer for the proof render.
class _ProofApi implements ApiClient {
  _ProofApi(this.explain);
  final Map<String, dynamic>? explain;

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    if (path.endsWith('/explain') && explain != null) return ApiSuccess(Map<String, Object?>.from(explain!) as T);
    return ApiSuccess(<String, Object?>{'recorded': true} as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{} as T);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => get<T>(path);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(Uri.parse('mock://$fileName'));
}

// ---------------------------------------------------------------------------
// Production replay: the EXACT /deals/discover JSON and /api/in-app/assistant
// decisions production returned (results probe, 2026-10-03) go through the
// app's real parser (UniversalMatch.fromJson) and the real chat screen.
UniversalMatchResult _productionResult(String fixture) {
  final data = jsonDecode(File('test/fixtures/production/$fixture').readAsStringSync()) as Map<String, dynamic>;
  final rows = [
    for (final m in (data['matches'] as List).whereType<Map>()) UniversalMatch.fromJson(Map<String, Object?>.from(m)),
  ]..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
  final status = data['source_status'] as Map;
  return UniversalMatchResult(
      dealId: '', matches: rows, sourceStatus: {for (final e in status.entries) '${e.key}': '${e.value}'});
}

