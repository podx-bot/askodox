import '../../matching/domain/sandbox_party_gate.dart';
import 'sandbox_deal_lifecycle.dart';

class SandboxInvestorFlowState {
  const SandboxInvestorFlowState({
    required this.partyGate,
    required this.lifecycle,
  });

  final SandboxPartyGateState partyGate;
  final SandboxDealLifecycleState lifecycle;

  bool get conversationReady => partyGate.conversationReady;
  bool get contactSharingAllowed => partyGate.contactSharingAllowed;
  bool get paymentReady => partyGate.conversationReady && lifecycle.dealStatus == SandboxDealStatus.confirmed;
  bool get reviewAllowed => lifecycle.reviewAllowed;
}

class SandboxInvestorFlow {
  SandboxInvestorFlow({
    SandboxPartyGateStore? partyGateStore,
    SandboxDealLifecycleStore? lifecycleStore,
  })  : partyGateStore = partyGateStore ?? SandboxPartyGateStore(),
        lifecycleStore = lifecycleStore ?? SandboxDealLifecycleStore();

  final SandboxPartyGateStore partyGateStore;
  final SandboxDealLifecycleStore lifecycleStore;

  SandboxInvestorFlowState stateFor({
    required String dealId,
    required String matchId,
  }) => SandboxInvestorFlowState(
        partyGate: partyGateStore.stateFor(dealId: dealId, matchId: matchId),
        lifecycle: lifecycleStore.stateFor(dealId),
      );

  SandboxInvestorFlowState acceptParty({
    required String dealId,
    required String matchId,
    required SandboxPartySide side,
  }) {
    partyGateStore.accept(dealId: dealId, matchId: matchId, side: side);
    return stateFor(dealId: dealId, matchId: matchId);
  }

  SandboxInvestorFlowState confirmDeal({
    required String dealId,
    required String matchId,
  }) {
    final gate = partyGateStore.stateFor(dealId: dealId, matchId: matchId);
    if (!gate.conversationReady) {
      throw StateError('Both Party A and Party B must accept before deal confirmation.');
    }
    lifecycleStore.confirm(dealId);
    return stateFor(dealId: dealId, matchId: matchId);
  }

  SandboxInvestorFlowState setPayment({
    required String dealId,
    required String matchId,
    required SandboxPaymentStatus status,
  }) {
    final state = stateFor(dealId: dealId, matchId: matchId);
    if (!state.paymentReady) {
      throw StateError('Sandbox deal must be mutually accepted and confirmed before payment.');
    }
    lifecycleStore.setPayment(dealId, status);
    return stateFor(dealId: dealId, matchId: matchId);
  }

  SandboxInvestorFlowState markInvoiceCreated({
    required String dealId,
    required String matchId,
  }) {
    lifecycleStore.markInvoiceCreated(dealId);
    return stateFor(dealId: dealId, matchId: matchId);
  }

  SandboxInvestorFlowState complete({
    required String dealId,
    required String matchId,
  }) {
    lifecycleStore.complete(dealId);
    return stateFor(dealId: dealId, matchId: matchId);
  }

  SandboxInvestorFlowState cancel({
    required String dealId,
    required String matchId,
  }) {
    lifecycleStore.cancel(dealId);
    return stateFor(dealId: dealId, matchId: matchId);
  }
}
