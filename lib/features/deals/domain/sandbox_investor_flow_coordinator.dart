import '../../matching/domain/sandbox_party_gate.dart';
import 'sandbox_deal_lifecycle.dart';

/// Single strict domain gate for the investor sandbox flow.
///
/// Party A acceptance alone never unlocks conversation/payment. Party B must
/// also accept the same transaction before payment can be started.
class SandboxInvestorFlowCoordinator {
  SandboxInvestorFlowCoordinator({
    SandboxPartyGateStore? partyGateStore,
    SandboxDealLifecycleStore? lifecycleStore,
  })  : partyGateStore = partyGateStore ?? SandboxPartyGateStore(),
        lifecycleStore = lifecycleStore ?? SandboxDealLifecycleStore();

  final SandboxPartyGateStore partyGateStore;
  final SandboxDealLifecycleStore lifecycleStore;

  String transactionKey({required String dealId, required String matchId}) =>
      SandboxPartyGateStore.transactionKey(dealId: dealId, matchId: matchId);

  SandboxPartyGateState acceptPartyA({required String dealId, required String matchId}) =>
      partyGateStore.accept(
        dealId: dealId,
        matchId: matchId,
        side: SandboxPartySide.partyA,
      );

  SandboxPartyGateState acceptPartyB({required String dealId, required String matchId}) =>
      partyGateStore.accept(
        dealId: dealId,
        matchId: matchId,
        side: SandboxPartySide.partyB,
      );

  bool canStartPayment({required String dealId, required String matchId}) =>
      partyGateStore.stateFor(dealId: dealId, matchId: matchId).conversationReady;

  SandboxDealLifecycleState confirmDeal({required String dealId, required String matchId}) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.confirm(dealId);
  }

  SandboxDealLifecycleState setPayment({
    required String dealId,
    required String matchId,
    required SandboxPaymentStatus status,
  }) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.setPayment(dealId, status);
  }

  SandboxDealLifecycleState createInvoice({required String dealId, required String matchId}) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.markInvoiceCreated(dealId);
  }

  SandboxDealLifecycleState complete({required String dealId, required String matchId}) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.complete(dealId);
  }

  bool canShareContact({required String dealId, required String matchId}) =>
      partyGateStore.stateFor(dealId: dealId, matchId: matchId).contactSharingAllowed;

  void _requireBilateralAcceptance({required String dealId, required String matchId}) {
    if (!canStartPayment(dealId: dealId, matchId: matchId)) {
      throw StateError('Party A and Party B must both accept before sandbox deal/payment can continue.');
    }
  }
}
