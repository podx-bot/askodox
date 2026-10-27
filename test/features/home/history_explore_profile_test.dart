import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/profile/data/user_profile_repository.dart';
import 'package:podx/features/profile/presentation/profile_screen.dart';
import 'package:podx/features/watchlist/presentation/watchlist_screen.dart';
import 'package:podx/services/support_escalation_service.dart';
import 'package:podx/shared/widgets/navigator_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _snapshot(String id, String title, String status) => {
      'id': id,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'status': status,
      'data': {'turns': []},
    };

Future<ProviderContainer> _pumpRouted(
  WidgetTester tester, {
  required String initial,
  required Map<String, Widget> screens,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1440, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: [
    for (final entry in screens.entries)
      GoRoute(path: entry.key, builder: (_, __) => entry.value),
  ]);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

void main() {
  testWidgets('History lists real conversations, filters work, open restores and New ask starts clean',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.conversation_archive.v1': jsonEncode([
        _snapshot('c-3', 'AC service', 'completed'),
        _snapshot('c-2', 'Chicken nearby', 'matched'),
        _snapshot('c-1', 'Computer operator job', 'active'),
      ]),
    });
    final container = await _pumpRouted(tester, initial: '/history', screens: {
      '/history': const WatchlistScreen(),
      '/': const Text('MAIN CHAT'),
    });

    expect(find.text('Chicken nearby'), findsOneWidget);
    expect(find.text('AC service'), findsOneWidget);
    expect(find.text('Computer operator job'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('historyFilter-matched')));
    await tester.pump();
    expect(find.text('Chicken nearby'), findsOneWidget);
    expect(find.text('AC service'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-completed')));
    await tester.pump();
    expect(find.text('AC service'), findsOneWidget);
    expect(find.text('Chicken nearby'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-active')));
    await tester.pump();
    expect(find.text('Computer operator job'), findsOneWidget);
    expect(find.text('AC service'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-all')));
    await tester.pump();
    await tester.tap(find.text('Chicken nearby'));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.conversationId, 'c-2');
    expect(find.text('MAIN CHAT'), findsOneWidget);
  });

  testWidgets('History New ask requests a clean conversation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpRouted(tester, initial: '/history', screens: {
      '/history': const WatchlistScreen(),
      '/': const Text('MAIN CHAT'),
    });
    expect(find.textContaining('No conversations yet'), findsOneWidget);
    expect(find.text('Chicken nearby'), findsNothing, reason: 'no hardcoded demo history');
    await tester.tap(find.byKey(const Key('historyNewAsk')));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.newConversation, isTrue);
    expect(find.text('MAIN CHAT'), findsOneWidget);
  });

  testWidgets("Profile shows the user's own stored data (no placeholders) and edits update it", (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.roles.v1': jsonEncode({'owned': ['buyer', 'seller'], 'active': 'seller'}),
    });
    final profiles = _Profiles(const AskodoxUserProfile(
      userId: 'app-phone-919876543210',
      name: 'Lakshmi',
      mobile: '+919876543210',
      address: 'Main Road, Vuyyuru',
      language: 'te',
      businessName: 'Sri Lakshmi Kirana',
      businessAddress: 'Main Road, Vuyyuru',
      businessCategory: 'grocery',
      verificationStatus: 'unverified',
      listings: 12,
    ));
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()}, overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      askodoxUserProfileRepositoryProvider.overrideWithValue(profiles),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxProfileName')), findsOneWidget);
    expect(find.text('Lakshmi'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Sri Lakshmi Kirana'), findsOneWidget);
    expect(find.text('Not verified yet'), findsOneWidget, reason: 'verification comes from the server, never claimed');
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Your ASKODOX profile'), findsNothing, reason: 'the generic placeholder header is gone');

    await tester.tap(find.byKey(const Key('askodoxProfileEdit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxEditGrid')), findsOneWidget, reason: 'mini boxes first');
    await tester.tap(find.byKey(const ValueKey('askodoxEditMini-personal')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxEditName')), 'Lakshmi Devi');
    await tester.tap(find.byKey(const Key('askodoxEditSave')));
    await tester.pumpAndSettle();
    expect(profiles.saves.last['name'], 'Lakshmi Devi');
    expect(find.text('Lakshmi Devi'), findsOneWidget, reason: 'the one stored profile updates everywhere');
  });

  testWidgets('Navigator Profile: five grouped sections; every row opens its own screen (never chat)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget page(String name) => Scaffold(body: Text('PAGE $name'));
    await _pumpRouted(tester, initial: '/profile', screens: {
      '/profile': const ProfileScreen(),
      '/': page('HOME'),
      for (final r in ['/business', '/listings/mine', '/orders/incoming', '/business/promotions', '/business/automation',
          '/videos/native', '/business/creations', '/profile/roles', '/opportunities', '/mobility', '/privacy', '/tools', '/me/finance', '/intel/tax'])
        r: page(r),
    });
    // Three tabs instead of one long list: each tab shows its own sections.
    expect(find.byKey(const Key('askodoxProfileSection-roles')), findsOneWidget, reason: 'Me tab first');
    expect(find.byKey(const Key('askodoxProfileSection-business')), findsNothing, reason: 'not all at once');
    for (final (tab, sections) in [
      ('business', ['business', 'studio']),
      ('settings', ['settings', 'help']),
      ('me', ['shopping', 'finance', 'roles']),
    ]) {
      await tester.tap(find.byKey(Key('askodoxProfileTab-$tab')));
      await tester.pumpAndSettle();
      for (final section in sections) {
        expect(find.byKey(Key('askodoxProfileSection-$section')), findsOneWidget, reason: '$tab: $section');
      }
    }
    await tester.tap(find.byKey(const Key('askodoxProfileTab-business')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('askodoxProfileSection-business')), matching: find.byType(Card)),
        findsNothing, reason: 'one grouped card per section, not a card per row');
    for (final (tab, key, route) in [
      ('business', 'profile-my-listings', '/listings/mine'),
      ('business', 'profile-enquiries', '/orders/incoming'),
      ('business', 'profile-native-video', '/videos/native'),
      ('me', 'profile-mobility', '/mobility'),
      ('me', 'profile-smart-tools', '/tools'),
      ('me', 'profile-tax-assistant', '/intel/tax'),
      ('me', 'profile-personal-finance', '/me/finance'),
    ]) {
      await tester.tap(find.byKey(Key('askodoxProfileTab-$tab')));
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey(key));
      await tester.ensureVisible(row);
      await tester.tap(row);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('PAGE $route'), findsOneWidget, reason: '$key opens $route');
      expect(find.text('PAGE HOME'), findsNothing, reason: 'never routed to chat');
      GoRouter.of(tester.element(find.text('PAGE $route'))).pop();
      // Let the back transition finish before the next tap.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  });

  testWidgets('Profile highlights the active role without changing stored roles', (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.roles.v1': jsonEncode({'owned': ['buyer', 'serviceProvider'], 'active': 'seller'}),
    });
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()});

    expect(find.text('Seller · Active now'), findsOneWidget);
    final seller = tester.widget<FilterChip>(find.byKey(const ValueKey('profileRole-seller')));
    expect(seller.selected, isFalse, reason: 'active role is highlighted, not added to stored roles');
    final provider = tester.widget<FilterChip>(find.byKey(const ValueKey('profileRole-serviceProvider')));
    expect(provider.selected, isTrue);
    expect(find.widgetWithText(FilterChip, 'Buyer'), findsOneWidget);
  });

  testWidgets('Master profile: e-mail, links and per-role details save to the ONE profile; active role switches '
      'only when picked', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'askodox.roles.v1': jsonEncode({'owned': ['buyer', 'seller', 'deliveryPartner'], 'active': 'buyer'}),
    });
    final profiles = _Profiles(const AskodoxUserProfile(
      userId: 'app-phone-919876543210',
      name: 'Lakshmi',
      roleDetails: {
        'seller': {'business_type': 'grocery'},
      },
    ));
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()}, overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      askodoxUserProfileRepositoryProvider.overrideWithValue(profiles),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxProfileEdit')));
    await tester.pumpAndSettle();
    // Each held role has its own mini box; only roles the person holds.
    expect(find.byKey(const ValueKey('askodoxEditMini-role-seller')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxEditMini-role-delivery_partner')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxEditMini-role-service_provider')), findsNothing,
        reason: 'only roles the person holds');
    Future<void> open(String id) async {
      final mini = find.byKey(ValueKey('askodoxEditMini-$id'));
      await tester.ensureVisible(mini);
      await tester.pumpAndSettle();
      await tester.tap(mini);
      await tester.pumpAndSettle();
    }

    await open('role-seller');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('askodoxEditRole-seller-business_type'))).controller!.text,
        'grocery', reason: 'existing role details are loaded');

    final savesBefore = profiles.saves.length; // the screen syncs held roles + language on open
    await open('personal');
    await tester.enterText(find.byKey(const Key('askodoxEditEmail')), 'bad-email');
    tester.widget<FilledButton>(find.byKey(const Key('askodoxEditSave'))).onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxEditError')), findsOneWidget);
    expect(profiles.saves.length, savesBefore, reason: 'invalid e-mail is not sent');

    await tester.enterText(find.byKey(const Key('askodoxEditEmail')), 'lakshmi@example.com');
    await open('links');
    await tester.enterText(find.byKey(const ValueKey('askodoxEditLink-website')), 'https://lakshmi.example');
    await open('role-delivery_partner');
    final vehicle = find.byKey(const ValueKey('askodoxEditRole-delivery_partner-vehicle_type'));
    await tester.ensureVisible(vehicle);
    await tester.enterText(vehicle, 'two_wheeler');
    tester.widget<FilledButton>(find.byKey(const Key('askodoxEditSave'))).onPressed!();
    await tester.pumpAndSettle();
    final saved = profiles.saves.lastWhere((m) => m.containsKey('email'));
    expect(saved['email'], 'lakshmi@example.com');
    expect(saved['links'], [{'kind': 'website', 'url': 'https://lakshmi.example'}]);
    final details = saved['role_details'] as Map;
    expect((details['seller'] as Map)['business_type'], 'grocery');
    expect((details['delivery_partner'] as Map)['vehicle_type'], 'two_wheeler');

    // Explicit switch of the ACTIVE role (in the editor's one roles card), announced, saved.
    await tester.tap(find.byKey(const Key('askodoxProfileEdit')));
    await tester.pumpAndSettle();
    final picker = find.byKey(const Key('askodoxActiveRolePicker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seller').last);
    await tester.pumpAndSettle();
    expect(profiles.saves.where((m) => m['active_role'] == 'seller'), hasLength(1));
    expect(find.byKey(const Key('askodoxActiveRoleChanged')), findsOneWidget);
  });

  testWidgets('Profile editor: numbers with hours, addresses add / delete, "say or paste" fills the right boxes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'askodox.roles.v1': jsonEncode({'owned': ['buyer', 'seller'], 'active': 'seller'}),
    });
    final profiles = _Profiles(const AskodoxUserProfile(
      userId: 'app-phone-919876543210',
      name: 'Lakshmi',
      mobile: '+919876543210',
      addresses: [{'kind': 'home', 'text': 'Vuyyuru'}],
    ));
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()}, overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      askodoxUserProfileRepositoryProvider.overrideWithValue(profiles),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxProfileEdit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxEditPaste')),
        'shop@lakshmi.in https://facebook.com/lakshmikirana 98480 22338 GST 36ABCDE1234F1Z5 ఉదయం 8 నుండి రాత్రి 10');
    await tester.tap(find.byKey(const Key('askodoxEditPasteGo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxEditNotice')), findsOneWidget);
    final mini = find.byKey(const ValueKey('askodoxEditMini-phones'));
    await tester.tap(mini);
    await tester.pumpAndSettle();
    expect(find.text('+91 9876543210'), findsOneWidget, reason: 'the verified number is filled in and locked');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('askodoxEditPhoneNumber-1'))).controller!.text, '9848022338');
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('askodoxEditPhoneAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxEditPhoneAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxEditPhone-2')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxEditPhoneDelete-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxEditPhoneDelete-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxEditPhone-2')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxEditMini-addresses')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxEditMini-addresses')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('askodoxEditAddressAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxEditAddressAdd')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('askodoxEditShopAddress')));
    await tester.enterText(find.byKey(const Key('askodoxEditShopAddress')), 'Bus stand road');
    tester.widget<FilledButton>(find.byKey(const Key('askodoxEditSave'))).onPressed!();
    await tester.pumpAndSettle();
    final saved = profiles.saves.lastWhere((m) => m.containsKey('phones'));
    expect(saved['email'], 'shop@lakshmi.in');
    expect(saved['links'], [{'kind': 'facebook', 'url': 'https://facebook.com/lakshmikirana'}]);
    expect(saved['gstin'], '36ABCDE1234F1Z5');
    expect(saved['phones'], [
      {'kind': 'personal', 'number': '9876543210', 'same_as_personal': false, 'from': '', 'to': ''},
      {'kind': 'business', 'number': '9848022338', 'same_as_personal': false, 'from': '08:00', 'to': '22:00'},
    ]);
    expect(saved['addresses'], [
      {'kind': 'home', 'text': 'Vuyyuru'},
      {'kind': 'business', 'text': 'Bus stand road'},
    ]);
  });

  testWidgets('APK 1275: a sign-in the server rejects (401) asks to sign in again, not "could not be loaded"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()}, overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      askodoxUserProfileRepositoryProvider.overrideWithValue(_RejectedProfiles(const AskodoxUserProfile(userId: 'x'))),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxProfileSignInAgain')), findsOneWidget);
    expect(find.text('Your profile could not be loaded.'), findsNothing);
  });

  test('support escalation client sends full context and reads configured channels', () async {
    late Map<String, dynamic> body;
    final service = SupportEscalationService(client: MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/in-app/support/escalate');
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(jsonEncode({
        'case_id': 7,
        'channels': {'chat': true, 'whatsapp_url': null, 'call_uri': 'tel:+911234'},
      }), 200);
    }));
    final supportCase = await service.escalate(
      issue: 'refund not received',
      category: 'PAYMENT',
      critical: true,
      conversation: const [{'role': 'user', 'text': 'refund not received'}],
      dealId: '42',
      authToken: 'tok',
    );
    expect(supportCase!.caseId, '7');
    expect(supportCase.whatsappUrl, isNull);
    expect(supportCase.callUri, 'tel:+911234');
    expect(body['deal_id'], '42');
    expect(body['critical'], isTrue);

    final failing = SupportEscalationService(client: MockClient((_) async => http.Response('', 500)));
    expect(await failing.escalate(issue: 'x', category: 'GENERAL', critical: false, conversation: const []), isNull);
  });

  testWidgets('Profile grid: every tile has a Guide that starts that screen\'s walkthrough', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()});
    for (final (tab, id) in [('business', 'screen_business'), ('business', 'screen_listings'),
        ('business', 'screen_enquiries'), ('business', 'screen_videos'), ('me', 'screen_mobility'),
        ('settings', 'screen_notifications'), ('settings', 'screen_feedback')]) {
      await tester.tap(find.byKey(Key('askodoxProfileTab-$tab')));
      await tester.pumpAndSettle();
      final button = find.byKey(ValueKey('askodoxTileGuide-$id'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(container.read(askodoxGuideProvider)?.flow.id, id);
      container.read(askodoxGuideProvider.notifier).stop();
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('askodoxProfileGuide')));
    await tester.tap(find.byKey(const Key('askodoxProfileGuide')));
    await tester.pump();
    expect(container.read(askodoxGuideProvider)?.flow.id, 'screen_profile_details');
    container.read(askodoxGuideProvider.notifier).stop();
    expect(find.byType(AskodoxNavTile), findsWidgets, reason: 'grid tiles, not long rows');
  });

  testWidgets('Profile search finds any row in any tab (en / te) and remembers recent ones', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget page(String name) => Scaffold(body: Text('PAGE $name'));
    await _pumpRouted(tester, initial: '/profile', screens: {
      '/profile': const ProfileScreen(),
      '/': page('HOME'),
      '/settings/notifications': page('/settings/notifications'),
    });
    await tester.enterText(find.byKey(const Key('askodoxProfileSearch')), 'నోటిఫికేషన్');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxProfileSearchResult-profile-notifications')), findsOneWidget,
        reason: 'a Settings row found from the Me tab, in Telugu');
    await tester.tap(find.byKey(const ValueKey('askodoxProfileSearchResult-profile-notifications')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('PAGE /settings/notifications'), findsOneWidget);
    GoRouter.of(tester.element(find.text('PAGE /settings/notifications'))).pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byKey(const Key('askodoxProfileSearch')), '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxProfileRecent-profile-notifications')), findsOneWidget,
        reason: 'recently opened rows come first');
    await tester.enterText(find.byKey(const Key('askodoxProfileSearch')), 'zzqx');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxProfileSearchNone')), findsOneWidget, reason: 'nothing found -> ask ASKODOX');
  });
}


class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919876543210', role: UserRole.buyer, displayName: 'Lakshmi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _Profiles implements AskodoxUserProfileRepository {
  _Profiles(this.stored);
  AskodoxUserProfile stored;
  final saves = <Map<String, Object?>>[];

  @override
  String? get authToken => 't';

  @override
  Future<AskodoxUserProfile?> load() async => stored;

  @override
  Future<AskodoxUserProfile?> save(Map<String, Object?> fields) async {
    saves.add(fields);
    stored = AskodoxUserProfile(
      userId: stored.userId,
      name: '${fields['name'] ?? stored.name ?? ''}',
      mobile: stored.mobile,
      address: '${fields['address'] ?? stored.address ?? ''}',
      language: stored.language,
      businessName: (fields['business_name'] ?? stored.businessName) as String?,
      businessAddress: stored.businessAddress,
      verificationStatus: stored.verificationStatus,
      listings: stored.listings,
      email: (fields['email'] ?? stored.email) as String?,
      activeRole: (fields['active_role'] ?? stored.activeRole) as String?,
      roleDetails: stored.roleDetails,
      phones: stored.phones,
      addresses: stored.addresses,
    );
    return stored;
  }

  @override
  Future<AskodoxUserProfile?> setPhoto(Uint8List? jpeg) async => stored;
}


class _RejectedProfiles extends _Profiles {
  _RejectedProfiles(super.stored);

  @override
  Future<AskodoxUserProfile?> load() async => throw const AskodoxSessionInvalid();
}
