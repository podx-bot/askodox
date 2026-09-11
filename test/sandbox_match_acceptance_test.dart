import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

void main() {
  test('sandbox acceptance is persisted instead of silently no-oping', () async {
    final store = SandboxMatchAcceptanceStore();
    final repository = ApiUniversalMatchRepository(
      MockApiClient(),
      appUserId: 'app-test-user',
      sandboxAcceptanceStore: store,
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
  });

  test('acceptance store keeps different deal-match pairs isolated', () {
    final store = SandboxMatchAcceptanceStore()
      ..accept(dealId: 'local-a', matchId: 'demo-1');

    expect(store.isAccepted(dealId: 'local-a', matchId: 'demo-1'), isTrue);
    expect(store.isAccepted(dealId: 'local-a', matchId: 'demo-2'), isFalse);
    expect(store.isAccepted(dealId: 'local-b', matchId: 'demo-1'), isFalse);
  });
}
