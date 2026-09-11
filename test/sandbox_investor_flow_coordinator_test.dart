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

  test('bilateral acceptance alone still cannot unlock payment before fulfilment', () {
    final flow = SandboxInvestorFlowCoordinator();
    const dealId = 'local-investor-deal-2';
    const matchId = 'demo-provider-1';

    flow.acceptPartyA(dealId: dealId, matchId: matchId);
    flow.acceptPartyB(dealId: dealId, matchId: matchId);
    flow.confirmDeal(dealId: dealId, matchId: matchId);

    expect(flow.hasBilateralAcceptance(dealId: dealId, matchId: matchId), isTrue);
    expect(flow.canShareContact(dealId: dealId, matchId: matchId), isTrue);
    expect(flow.canStartPayment(dealId: dealId, matchId: matchId), isFalse);

    expect(
      () => flow.setPayment(
        dealId: dealId,
        matchId: matchId,
        status: SandboxPaymentStatus.pending,
      ),
      throwsStateError,
    );
  });

  test('delivery fulfilment confirmation unlocks payment then invoice completion review', () {
    final flow = SandboxInvestorFlowCoordinator();
    const dealId = 'local-delivery-deal';
    const matchId = 'demo-seller-2';

    flow.acceptPartyA(dealId: dealId, matchId: matchId);
    flow.acceptPartyB(dealId: dealId, matchId: matchId);
    flow.confirmDeal(dealId: dealId, matchId: matchId);

    final fulfilled = flow.confirmFulfilment(
      dealId: dealId,
      matchId: matchId,
      mode: SandboxFulfilmentMode.delivery,
      location: 'Vijayawada',
      timing: 'Today 6 PM',
      charge: 40,
    );
    expect(fulfilled.fulfilmentConfirmed, isTrue);
    expect(flow.canStartPayment(dealId: dealId, matchId: matchId), isTrue);

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

  test('pickup fulfilment also requires place time and charge confirmation before payment', () {
    final flow = SandboxInvestorFlowCoordinator();
    const dealId = 'local-pickup-deal';
    const matchId = 'demo-shop-1';

    flow.acceptPartyA(dealId: dealId, matchId: matchId);
    flow.acceptPartyB(dealId: dealId, matchId: matchId);
    flow.confirmDeal(dealId: dealId, matchId: matchId);

    final fulfilled = flow.confirmFulfilment(
      dealId: dealId,
      matchId: matchId,
      mode: SandboxFulfilmentMode.pickup,
      location: 'Shop counter',
      timing: 'Tomorrow 10 AM',
      charge: 0,
    );

    expect(fulfilled.fulfilmentConfirmed, isTrue);
    expect(flow.canStartPayment(dealId: dealId, matchId: matchId), isTrue);
  });
}
