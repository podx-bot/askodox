import 'universal_deal.dart';
import 'universal_negotiation.dart';

enum DealLifecycleEvent {
  matchFound,
  negotiationStarted,
  negotiationAccepted,
  completed,
  cancelled,
  disputeRaised,
  disputeResolved,
}

enum DealDisputeState {
  none,
  open,
  resolved,
}

class DealLifecycleSnapshot {
  const DealLifecycleSnapshot({
    required this.status,
    this.agreedPrice,
    this.disputeState = DealDisputeState.none,
    this.disputeReason,
    this.adminReviewRequired = false,
  });

  final DealStatus status;
  final double? agreedPrice;
  final DealDisputeState disputeState;
  final String? disputeReason;
  final bool adminReviewRequired;

  bool get isTerminal => status == DealStatus.closed || status == DealStatus.cancelled;
  bool get hasOpenDispute => disputeState == DealDisputeState.open;
}

class DealLifecycleEngine {
  const DealLifecycleEngine();

  DealLifecycleSnapshot initial(UniversalDeal deal) => DealLifecycleSnapshot(status: deal.status);

  DealLifecycleSnapshot apply(
    DealLifecycleSnapshot current,
    DealLifecycleEvent event, {
    NegotiationResult? negotiation,
    String? disputeReason,
  }) {
    if (current.status == DealStatus.cancelled && event != DealLifecycleEvent.disputeRaised) {
      return current;
    }

    switch (event) {
      case DealLifecycleEvent.matchFound:
        if (current.status == DealStatus.collecting || current.status == DealStatus.readyToMatch || current.status == DealStatus.matching) {
          return _copy(current, status: DealStatus.matched);
        }
        return current;
      case DealLifecycleEvent.negotiationStarted:
        if (current.status == DealStatus.matched || current.status == DealStatus.negotiating) {
          return _copy(current, status: DealStatus.negotiating);
        }
        return current;
      case DealLifecycleEvent.negotiationAccepted:
        if (negotiation == null || !negotiation.isResolved) return current;
        if (current.status != DealStatus.matched && current.status != DealStatus.negotiating) return current;
        return _copy(current, status: DealStatus.matched, agreedPrice: negotiation.agreedPrice);
      case DealLifecycleEvent.completed:
        if ((current.status == DealStatus.matched || current.status == DealStatus.negotiating) && !current.hasOpenDispute) {
          return _copy(current, status: DealStatus.closed);
        }
        return current;
      case DealLifecycleEvent.cancelled:
        if (current.status == DealStatus.closed) return current;
        return _copy(current, status: DealStatus.cancelled);
      case DealLifecycleEvent.disputeRaised:
        final reason = disputeReason?.trim();
        if (reason == null || reason.isEmpty) return current;
        return _copy(
          current,
          disputeState: DealDisputeState.open,
          disputeReason: reason,
          adminReviewRequired: true,
        );
      case DealLifecycleEvent.disputeResolved:
        if (!current.hasOpenDispute) return current;
        return _copy(
          current,
          disputeState: DealDisputeState.resolved,
          adminReviewRequired: false,
        );
    }
  }

  DealLifecycleSnapshot _copy(
    DealLifecycleSnapshot current, {
    DealStatus? status,
    double? agreedPrice,
    DealDisputeState? disputeState,
    String? disputeReason,
    bool? adminReviewRequired,
  }) {
    return DealLifecycleSnapshot(
      status: status ?? current.status,
      agreedPrice: agreedPrice ?? current.agreedPrice,
      disputeState: disputeState ?? current.disputeState,
      disputeReason: disputeReason ?? current.disputeReason,
      adminReviewRequired: adminReviewRequired ?? current.adminReviewRequired,
    );
  }
}
