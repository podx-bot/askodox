import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/matching/domain/sandbox_party_gate.dart';

void main() {
  test('contact stays locked until both Party A and Party B accept', () {
    final store = SandboxPartyGateStore();

    expect(
      store.canShareContact(dealId: 'local-1', matchId: 'demo-1'),
      isFalse,
    );

    store.accept(
      dealId: 'local-1',
      matchId: 'demo-1',
      side: SandboxPartySide.partyA,
    );

    expect(
      store.canOpenConversation(dealId: 'local-1', matchId: 'demo-1'),
      isFalse,
    );
    expect(
      store.canShareContact(dealId: 'local-1', matchId: 'demo-1'),
      isFalse,
    );

    store.accept(
      dealId: 'local-1',
      matchId: 'demo-1',
      side: SandboxPartySide.partyB,
    );

    expect(
      store.canOpenConversation(dealId: 'local-1', matchId: 'demo-1'),
      isTrue,
    );
    expect(
      store.canShareContact(dealId: 'local-1', matchId: 'demo-1'),
      isTrue,
    );
  });

  test('Party A/B gate is transaction scoped, not role hard-coded', () {
    final store = SandboxPartyGateStore();

    store.accept(
      dealId: 'ride-1',
      matchId: 'driver-1',
      side: SandboxPartySide.partyA,
    );
    store.accept(
      dealId: 'ride-1',
      matchId: 'driver-1',
      side: SandboxPartySide.partyB,
    );

    expect(
      store.canShareContact(dealId: 'ride-1', matchId: 'driver-1'),
      isTrue,
    );
    expect(
      store.canShareContact(dealId: 'service-1', matchId: 'provider-1'),
      isFalse,
    );
  });
}
