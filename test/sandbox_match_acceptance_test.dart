import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/features/matching/domain/sandbox_party_gate.dart';

void main() {
  test('sandbox acceptance is persisted instead of silently no-oping', () async {
    final store = SandboxMatchAcceptanceStore();
    final gate = SandboxPartyGateStore();
    final repository = ApiUniversalMatchRepository(
      MockApiClient(),
      appUserId: 'app-test-user',
      sandboxAcceptanceStore: store,
      sandboxPartyGateStore: gate,
    );

    expect(
      store.isAccepted(dealId: 'local-deal-1', matchId: 'demo-seller-1'),
      isFalse,
    );

    await repository.acceptMatch(
      dealId: 'local-deal-1',
      matchId: 'demo-seller-1',
    );

    expect(
      store.isAccepted(dealId: 'local-deal-1', matchId: 'demo-seller-1'),
      isTrue,
    );
    expect(
      gate.stateFor(dealId: 'local-deal-1', matchId: 'demo-seller-1').partyAAccepted,
      isTrue,
    );
  });

  test('contact and conversation stay locked until Party B explicitly accepts', () async {
    final repository = ApiUniversalMatchRepository(
      MockApiClient(),
      appUserId: 'app-test-user',
    );

    const dealId = 'local-deal-2';
    const matchId = 'demo-provider-2';

    expect(
      repository.sandboxConversationReady(dealId: dealId, matchId: matchId),
      isFalse,
    );
    expect(
      repository.sandboxContactSharingAllowed(dealId: dealId, matchId: matchId),
      isFalse,
    );

    await repository.acceptMatch(dealId: dealId, matchId: matchId);

    expect(
      repository.sandboxConversationReady(dealId: dealId, matchId: matchId),
      isFalse,
    );
    expect(
      repository.sandboxContactSharingAllowed(dealId: dealId, matchId: matchId),
      isFalse,
    );

    await repository.acceptSandboxPartyB(dealId: dealId, matchId: matchId);

    expect(
      repository.sandboxConversationReady(dealId: dealId, matchId: matchId),
      isTrue,
    );
    expect(
      repository.sandboxContactSharingAllowed(dealId: dealId, matchId: matchId),
      isTrue,
    );
  });

  test('Party B cannot accept sandbox match before Party A', () async {
    final repository = ApiUniversalMatchRepository(
      MockApiClient(),
      appUserId: 'app-test-user',
    );

    await expectLater(
      repository.acceptSandboxPartyB(
        dealId: 'local-deal-3',
        matchId: 'demo-provider-3',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('sandbox Party B helper cannot be used for a live deal', () async {
    final repository = ApiUniversalMatchRepository(
      MockApiClient(),
      appUserId: 'app-test-user',
    );

    await expectLater(
      repository.acceptSandboxPartyB(
        dealId: '123',
        matchId: '456',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('acceptance store keeps different deal-match pairs isolated', () {
    final store = SandboxMatchAcceptanceStore()
      ..accept(dealId: 'local-a', matchId: 'demo-1');

    expect(store.isAccepted(dealId: 'local-a', matchId: 'demo-1'), isTrue);
    expect(store.isAccepted(dealId: 'local-a', matchId: 'demo-2'), isFalse);
    expect(store.isAccepted(dealId: 'local-b', matchId: 'demo-1'), isFalse);
  });
}
