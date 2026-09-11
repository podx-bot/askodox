import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deals/domain/sandbox_deal_lifecycle.dart';
import 'package:podx/features/deals/domain/sandbox_investor_flow_coordinator.dart';

void main() {
  test('Party A acceptance alone cannot unlock sandbox payment', () {
    final flow = SandboxInvestorFlowCoordinator();
    const dealId = 'local-investor-deal';
    const matchId = 'demo-seller-1';

    flow.acceptPartyA(dealId: dealId, matchId: matchId);

    expect(flow.canStartPayment(dealId: dealId, matchId: matchId), isFalse);
    expect(
      () => flow.setPayment(
        dealId: dealId,
        matchId: matchId,
        status: SandboxPaymentStatus.success,
      ),
      throwsStateError,
    );
  });

  test('bilateral acceptance unlocks payment but invoice still needs success', () {
    final flow = SandboxInvestorFlowCoordinator();
    const dealId = 'local-investor-deal-2';
    const matchId = 'demo-provider-1';

    flow.acceptPartyA(dealId: dealId, matchId: matchId);
    flow.acceptPartyB(dealId: dealId, matchId: matchId);

    expect(flow.canStartPayment(dealId: dealId, matchId: matchId), isTrue);
    expect(flow.canShareContact(dealId: dealId, matchId: matchId), isTrue);

    flow.confirmDeal(dealId: dealId, matchId: matchId);
    flow.setPayment(
      dealId: dealId,
      matchId: matchId,
      status: SandboxPaymentStatus.pending,
    );
    expect(
      () => flow.createInvoice(dealId: dealId, matchId: matchId),
      throwsStateError,
    );

    flow.setPayment(
      dealId: dealId,
      matchId: matchId,
      status: SandboxPaymentStatus.success,
    );
    final invoiced = flow.createInvoice(dealId: dealId, matchId: matchId);
    expect(invoiced.invoiceCreated, isTrue);

    final completed = flow.complete(dealId: dealId, matchId: matchId);
    expect(completed.reviewAllowed, isTrue);
  });
}
