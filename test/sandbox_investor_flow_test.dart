import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deals/domain/sandbox_deal_lifecycle.dart';
import 'package:podx/features/deals/domain/sandbox_investor_flow.dart';
import 'package:podx/features/matching/domain/sandbox_party_gate.dart';

void main() {
  test('investor sandbox flow requires bilateral acceptance and fulfilment before payment', () {
    final flow = SandboxInvestorFlow();
    const dealId = 'local-investor-e2e';
    const matchId = 'demo-party-b-1';

    expect(
      () => flow.confirmDeal(dealId: dealId, matchId: matchId),
      throwsStateError,
    );

    flow.acceptParty(
      dealId: dealId,
      matchId: matchId,
      side: SandboxPartySide.partyA,
    );
    expect(
      flow.stateFor(dealId: dealId, matchId: matchId).contactSharingAllowed,
      isFalse,
    );

    flow.acceptParty(
      dealId: dealId,
      matchId: matchId,
      side: SandboxPartySide.partyB,
    );
    expect(
      flow.stateFor(dealId: dealId, matchId: matchId).contactSharingAllowed,
      isTrue,
    );

    flow.confirmDeal(dealId: dealId, matchId: matchId);
    expect(
      flow.stateFor(dealId: dealId, matchId: matchId).paymentReady,
      isFalse,
    );
    expect(
      () => flow.setPayment(
        dealId: dealId,
        matchId: matchId,
        status: SandboxPaymentStatus.success,
      ),
      throwsStateError,
    );

    flow.confirmFulfilment(
      dealId: dealId,
      matchId: matchId,
      fulfilment: const SandboxFulfilmentConfirmation(
        mode: SandboxFulfilmentMode.delivery,
        locationConfirmed: true,
        timingConfirmed: true,
        chargeConfirmed: true,
      ),
    );
    expect(
      flow.stateFor(dealId: dealId, matchId: matchId).paymentReady,
      isTrue,
    );

    flow.setPayment(
      dealId: dealId,
      matchId: matchId,
      status: SandboxPaymentStatus.success,
    );
    flow.markInvoiceCreated(dealId: dealId, matchId: matchId);
    final completed = flow.complete(dealId: dealId, matchId: matchId);

    expect(completed.lifecycle.dealStatus, SandboxDealStatus.completed);
    expect(completed.reviewAllowed, isTrue);
  });

  test('payment cannot start after only one side accepts', () {
    final flow = SandboxInvestorFlow();
    const dealId = 'local-one-sided';
    const matchId = 'demo-provider';

    flow.acceptParty(
      dealId: dealId,
      matchId: matchId,
      side: SandboxPartySide.partyA,
    );

    expect(
      () => flow.setPayment(
        dealId: dealId,
        matchId: matchId,
        status: SandboxPaymentStatus.success,
      ),
      throwsStateError,
    );
  });
}
