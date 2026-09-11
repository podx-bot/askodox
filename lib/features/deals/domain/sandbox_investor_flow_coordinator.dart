import '../../matching/domain/sandbox_party_gate.dart';
import 'sandbox_deal_lifecycle.dart';

/// Single strict domain gate for the investor sandbox flow.
///
/// Party A acceptance alone never unlocks conversation/payment. Party B must
/// also accept the same transaction, then fulfilment must be confirmed before
/// payment can start.
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

  bool hasBilateralAcceptance({required String dealId, required String matchId}) =>
      partyGateStore.stateFor(dealId: dealId, matchId: matchId).conversationReady;

  bool canStartPayment({required String dealId, required String matchId}) =>
      hasBilateralAcceptance(dealId: dealId, matchId: matchId) &&
      lifecycleStore.stateFor(dealId).canStartPayment;

  SandboxDealLifecycleState confirmDeal({required String dealId, required String matchId}) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.confirm(dealId);
  }

  SandboxDealLifecycleState confirmFulfilment({
    required String dealId,
    required String matchId,
    required SandboxFulfilmentMode mode,
    required String location,
    required String timing,
    required double charge,
  }) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    return lifecycleStore.confirmFulfilment(
      dealId,
      mode: mode,
      location: location,
      timing: timing,
      charge: charge,
    );
  }

  SandboxDealLifecycleState setPayment({
    required String dealId,
    required String matchId,
    required SandboxPaymentStatus status,
  }) {
    _requirePaymentReady(dealId: dealId, matchId: matchId);
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
    if (!hasBilateralAcceptance(dealId: dealId, matchId: matchId)) {
      throw StateError('Party A and Party B must both accept before sandbox deal can continue.');
    }
  }

  void _requirePaymentReady({required String dealId, required String matchId}) {
    _requireBilateralAcceptance(dealId: dealId, matchId: matchId);
    if (!lifecycleStore.stateFor(dealId).canStartPayment) {
      throw StateError('Delivery/pickup fulfilment must be confirmed before sandbox payment can start.');
    }
  }
}
