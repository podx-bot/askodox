import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/home/domain/active_role.dart';
import 'package:podx/features/home/domain/chat_action_intent.dart';
import 'package:podx/features/location/presentation/map_pin_picker.dart';

class _Client implements ApiClient {
  _Client(this.routes);
  final Map<String, Map<String, Object?>> routes;
  final List<(String, Object?, String?)> calls = [];

  Future<ApiResult<T>> _reply<T>(String path, Object? body, ApiRequestOptions options) async {
    calls.add((path, body, options.authToken));
    // Most specific route first ("/drafts/7/publish" before "/drafts").
    final keys = routes.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    final key = keys.firstWhere((k) => path.startsWith(k), orElse: () => '');
    return ApiSuccess<T>((routes[key] ?? <String, Object?>{}) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path, null, options);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path, body, options);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path, body, options);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path, body, options);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply<T>(path, null, options);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess<Uri>(Uri.parse('https://files.example/$fileName'));
}

class _Growth implements GrowthRepository {
  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async =>
      [const AskodoxPlace(latitude: 16.51, longitude: 80.62, label: 'Governorpet, Vijayawada')];
  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async => null;
  @override
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId}) async => null;
  @override
  Future<AskodoxCatalogDraft?> draftListing(
          {String text = '', Map<String, Object?>? imageAnalysis, Map<String, Object?>? videoAnalysis}) async =>
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

void main() {
  group('growth repository', () {
    test('place search and route quote parse real backend fields only', () async {
      final client = _Client({
        '/api/discover/places': {
          'items': [
            {'name': 'Benz Circle', 'address': 'Vijayawada', 'latitude': 16.5, 'longitude': 80.65},
            {'name': 'No coordinates'},
          ],
        },
        '/api/discover/route': {
          'distance_km': 12.5,
          'duration_minutes': 34,
          'quotes': [
            {'title': 'parcel delivery bike', 'quote': 150, 'rate_unit': 'per km'},
          ],
        },
      });
      final repo = ApiGrowthRepository(client);
      final places = await repo.searchPlaces('Benz');
      expect(places.single.label, 'Benz Circle, Vijayawada');
      final quote = await repo.routeQuote(places.single, places.single);
      expect(quote!.distanceKm, 12.5);
      expect(quote.quotes.single.quote, 150);
    });

    test('referral and catalog drafts need sign-in and send the token', () async {
      final client = _Client({
        '/api/referrals': {'code': 'ASKABC123', 'share_text': 'Join'},
        '/api/catalog/drafts': {
          'id': 7,
          'draft': {'title': 'Preethi mixer grinder'},
          'missing': ['price'],
        },
        '/api/catalog/drafts/7/publish': {'listing_id': 99},
      });
      final guest = ApiGrowthRepository(client);
      expect(await guest.refer(category: 'AC repair'), isNull);
      expect(client.calls, isEmpty, reason: 'no anonymous referral records');
      final user = ApiGrowthRepository(client, authToken: 't');
      expect((await user.refer(category: 'AC repair', area: 'Vijayawada'))!.code, 'ASKABC123');
      final draft = await user.draftListing(imageAnalysis: {'subject': 'mixer grinder'});
      expect(draft!.title, 'Preethi mixer grinder');
      expect(draft.missing, ['price']);
      expect(await user.publishDraft(7, {'price': 3200}), 99);
      expect(client.calls.every((c) => c.$3 == 't'), isTrue);
    });
  });

  testWidgets('map pin: tap names the point, search jumps to a place, "Use" returns real coordinates',
      (tester) async {
    AskodoxPlace? picked;
    await tester.pumpWidget(ProviderScope(
      overrides: [growthRepositoryProvider.overrideWithValue(_Growth())],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<AskodoxPlace>(MaterialPageRoute(
                builder: (_) => AskodoxMapPinPicker(
                  title: 'Pickup point',
                  showTiles: false,
                  namer: (lat, lon) async => 'Benz Circle, Vijayawada, Andhra Pradesh',
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to drop a pin'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMapSurface')));
    await tester.pumpAndSettle();
    expect(find.text('Benz Circle, Vijayawada, Andhra Pradesh'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('askodoxPlaceSearch')), 'Governorpet');
    await tester.tap(find.byKey(const Key('askodoxPlaceSearchGo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Governorpet, Vijayawada'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxUsePin')));
    await tester.pumpAndSettle();
    expect(picked!.label, 'Governorpet, Vijayawada');
    expect([picked!.latitude, picked!.longitude], [16.51, 80.62]);
  });

  test('a map pin fills that route end with its real coordinates, never asked again', () {
    final controller = UniversalDealController();
    controller.start('I need to send a parcel');
    controller.setRoutePoint(pickup: true, label: 'Benz Circle', latitude: 16.5, longitude: 80.65);
    controller.setRoutePoint(pickup: false, label: 'Governorpet', latitude: 16.51, longitude: 80.62);
    final deal = controller.state.deal!;
    expect(deal.missingForMatch, isNot(contains('from')));
    expect(deal.missingForMatch, isNot(contains('to')));
    expect(deal.dynamicFields['from_lat'], 16.5);
    expect(deal.dynamicFields['to'], 'Governorpet');
  });

  test('participation roles come only from how people describe themselves', () {
    expect(askodoxDetectRole("I'm a farmer, I grow tomatoes")!.role, AskodoxUserRole.farmer);
    expect(askodoxDetectRole('I am an influencer with 50k followers')!.role, AskodoxUserRole.influencer);
    expect(askodoxDetectRole("I'm a commission agent for used cars")!.role, AskodoxUserRole.agent);
    expect(askodoxDetectRole('I am a distributor for FMCG')!.role, AskodoxUserRole.distributor);
    expect(askodoxDetectRole('I want to buy a TV')!.role, AskodoxUserRole.buyer);
    expect(askodoxParticipationRoles, contains(AskodoxUserRole.influencer));
    expect(askodoxContextRole(spoken: null, fromIntent: AskodoxUserRole.farmer), isNull,
        reason: 'a guessed supply role never flips the user');
    expect(askodoxUserRoleLabel(AskodoxUserRole.agent), 'Agent / Middleman');
  });

  test('"sell this" with media drafts a listing; buying words do not', () {
    for (final yes in ['sell this', 'I want to list this', 'put up my mixer for sale', 'ఇది అమ్మాలి']) {
      expect(askodoxWantsToList(yes), isTrue, reason: yes);
    }
    for (final no in ['what is this?', 'I want to buy this', 'best selling TV']) {
      expect(askodoxWantsToList(no), isFalse, reason: no);
    }
  });
}
