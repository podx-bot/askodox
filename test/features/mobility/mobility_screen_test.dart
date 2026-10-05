import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/mobility/application/mobility_draft.dart';
import 'package:podx/features/mobility/data/mobility_repository.dart';
import 'package:podx/features/mobility/presentation/mobility_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'app-phone-919800000000', role: UserRole.buyer, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

MobilityJob _job(String status, {bool accepted = false, String phone = ''}) => MobilityJob.fromJson({
      'id': 'dj_1',
      'kind': 'ride_auto',
      'status': status,
      'stage': accepted ? 'Partner accepted' : 'Request sent to nearby partners -- waiting for one to accept',
      'pickup': {'label': 'Benz Circle'},
      'drop': {'label': 'Bus stand'},
      'distance_km': 3.2,
      'confirmed_by_partner': accepted,
      'details': {'passengers': 2},
      if (phone.isNotEmpty) 'customer_phone': phone,
    });

class _Repo implements MobilityRepository {
  String partnerStatus = 'PENDING_REVIEW';
  bool online = false;
  final calls = <String>[];
  List<MobilityJob> offerList = [_job('PARTNER_SEARCH')];
  List<MobilityJob> active = [];

  MobilityPartner get _partner => MobilityPartner(
      id: 'dlp_1', status: partnerStatus, name: 'Ravi', services: const ['ride_auto'], vehicle: 'three_wheeler',
      available: online);

  @override
  Future<MobilityResult<MobilityPartner?>> myPartner() async => MobilityResult.ok(_partner);
  @override
  Future<List<MobilityJob>> offers() async => offerList;
  @override
  Future<({List<MobilityJob> active, List<MobilityJob> history})> trips() async =>
      (active: active, history: const <MobilityJob>[]);
  @override
  Future<MobilityResult<MobilityJob>> accept(String id) async {
    calls.add('accept:$id');
    offerList = [];
    active = [_job('PARTNER_ACCEPTED', accepted: true, phone: '+919000000001')];
    return MobilityResult.ok(active.first);
  }

  @override
  Future<MobilityResult<MobilityJob>> step(String id, String status) async {
    calls.add('step:$status');
    active = [_job(status, accepted: true)];
    return MobilityResult.ok(active.first);
  }

  Map<String, Object?>? lastPickup;
  Map<String, Object?>? lastDrop;
  String? lastKind;

  @override
  Future<MobilityResult<MobilityJob>> request({required String kind, required Map<String, Object?> pickup,
      required Map<String, Object?> drop, Map<String, Object?> details = const {}, String scheduleAt = ''}) async {
    lastKind = kind;
    lastPickup = pickup;
    lastDrop = drop;
    return MobilityResult.ok(_job('PARTNER_SEARCH'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Places implements GrowthRepository {
  final routes = <(String, String)>[];

  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async =>
      query.toLowerCase().startsWith('air')
          ? const [AskodoxPlace(latitude: 16.53, longitude: 80.80, label: 'Vijayawada Airport, Gannavaram')]
          : const [];

  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async {
    routes.add((pickup.label, drop.label));
    return const AskodoxRouteQuote(distanceKm: 18.4, durationMinutes: 32);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

Widget _app(_Repo repo, {int tab = 3, bool signedIn = true}) => ProviderScope(
      overrides: [
        if (signedIn) authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        mobilityRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: MobilityScreen(initialTab: tab)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('trip steps only move forward; a request is not confirmed until a partner accepts', () {
    expect(askodoxNextTripStep('PARTNER_ACCEPTED'), 'EN_ROUTE_PICKUP');
    expect(askodoxNextTripStep('IN_TRANSIT'), 'ARRIVED_DROP');
    expect(askodoxNextTripStep('DELIVERED'), isNull);
    expect(askodoxNextTripStep('PARTNER_SEARCH'), isNull);
    final pending = _job('PARTNER_SEARCH');
    expect(pending.confirmedByPartner, isFalse);
    expect(pending.partnerPhone, isEmpty);
    expect(pending.cancellable, isTrue);
    expect(_job('PICKED_UP', accepted: true).cancellable, isFalse);
  });

  testWidgets('signed-out users are asked to sign in, never shown a fake booking', (tester) async {
    await tester.pumpWidget(_app(_Repo(), tab: 0, signedIn: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobility-signin')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobility-submit')), findsNothing);
  });

  testWidgets('partner awaiting review cannot go online; once approved accepts and steps a trip', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('partner-status')), findsOneWidget);
    expect(find.textContaining('waiting for review'), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-online')), findsNothing);

    repo.partnerStatus = 'ACTIVE';
    await tester.pumpWidget(_app(repo, tab: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('partner-online')), findsOneWidget);
    expect(find.text('Not confirmed'), findsOneWidget);
    expect(find.textContaining('+91'), findsNothing, reason: 'no customer phone before acceptance');
    await tester.ensureVisible(find.byKey(const ValueKey('partner-accept-dj_1')));
    await tester.tap(find.byKey(const ValueKey('partner-accept-dj_1')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['accept:dj_1']);
    expect(find.textContaining('+919000000001'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('partner-step-dj_1')));
    expect(find.text('On my way to pickup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('partner-step-dj_1')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'step:EN_ROUTE_PICKUP');
  });

  testWidgets('chat draft pre-fills From; To autocompletes; route distance by road; request carries coordinates',
      (tester) async {
    final repo = _Repo();
    final places = _Places();
    final container = ProviderContainer(overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      mobilityRepositoryProvider.overrideWithValue(repo),
      growthRepositoryProvider.overrideWithValue(places),
    ]);
    addTearDown(container.dispose);
    // What Main Chat understood ("auto from Benz Circle"), with its map pin.
    container.read(askodoxMobilityDraftProvider.notifier).state = const MobilityDraft(
        kind: 'ride_airport', from: AskodoxPlace(latitude: 16.4991, longitude: 80.6563, label: 'Benz Circle'));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MobilityScreen(initialKind: 'ride_airport', initialFrom: 'Benz Circle'))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Benz Circle'), findsOneWidget, reason: 'prefilled from the chat');
    await tester.enterText(find.byKey(const ValueKey('mobility-to')), 'Airport');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobility-to-suggest-Vijayawada Airport, Gannavaram')));
    await tester.pumpAndSettle();
    expect(places.routes.last, ('Benz Circle', 'Vijayawada Airport, Gannavaram'));
    expect(find.textContaining('18.4 km'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobility-directions')), findsOneWidget);
    final draft = container.read(askodoxMobilityDraftProvider)!;
    expect(draft.to?.label, 'Vijayawada Airport, Gannavaram', reason: 'the chat sees the edit (one shared draft)');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('mobility-submit')), 200,
        scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const ValueKey('mobility-submit')));
    await tester.pumpAndSettle();
    expect(repo.lastKind, 'ride_airport');
    expect(repo.lastPickup, {'label': 'Benz Circle', 'latitude': 16.4991, 'longitude': 80.6563});
    expect(repo.lastDrop?['latitude'], 16.53);
    expect(draft.location, contains('kind=ride_airport'));
    expect(askodoxRouteDirectionsUri(draft.from!, draft.to!).toString(), contains('origin=16.4991%2C80.6563'));
  });
}
