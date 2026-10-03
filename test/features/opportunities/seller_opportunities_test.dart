import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/opportunities/data/opportunities_repository.dart';
import 'package:podx/features/opportunities/presentation/seller_opportunities_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919800000000', role: UserRole.seller, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _Repo extends OpportunitiesRepository {
  _Repo() : super(_NoClient());

  final actions = <String>[];
  String status = 'new';

  @override
  Future<SellerOpportunities> mine({String language = 'en'}) async => SellerOpportunities(
        privacy: "Customers' names and numbers are never shared.",
        items: [
          SellerOpportunity(
            id: 7,
            title: '9 customers looking for running shoes',
            body: 'Near Vijayawada, budget ₹1,000-2,000',
            subject: 'running shoes',
            status: status,
            category: 'footwear',
            area: 'vijayawada',
            searches: 9,
            budgetBand: '₹1,000-2,000',
            expiresAt: DateTime.now().add(const Duration(hours: 70)),
            canRespond: status == 'new',
            canFulfil: status == 'accepted',
          ),
          const SellerOpportunity(id: 8, title: 'TV demand', body: '', subject: 'tv', status: 'expired'),
        ],
      );

  @override
  Future<SellerOpportunity?> act(int id, String action, {String reason = ''}) async {
    actions.add('$action:$id:$reason');
    status = action == 'accept' ? 'accepted' : (action == 'decline' ? 'declined' : 'fulfilled');
    return null;
  }
}

class _NoClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('seller sees demand without identities and can accept, then fulfil', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        opportunitiesRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: SellerOpportunitiesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('9 customers looking for running shoes'), findsOneWidget);
    expect(find.textContaining('never shared'), findsOneWidget);
    expect(find.textContaining('Expires'), findsWidgets);
    expect(find.text('Expired'), findsOneWidget);
    // The expired one cannot be answered.
    expect(find.byKey(const ValueKey('askodoxOpportunityAccept-8')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxOpportunityAccept-7')));
    await tester.pumpAndSettle();
    expect(repo.actions, ['accept:7:']);
    expect(find.text('Accepted'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxOpportunityFulfil-7')));
    await tester.pumpAndSettle();
    expect(repo.actions.last, 'fulfil:7:');
  });

  testWidgets('decline asks for a reason', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        opportunitiesRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: SellerOpportunitiesScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxOpportunityDecline-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Out of stock'));
    await tester.pumpAndSettle();
    expect(repo.actions, ['decline:7:Out of stock']);
    expect(find.text('Declined'), findsOneWidget);
  });
}
