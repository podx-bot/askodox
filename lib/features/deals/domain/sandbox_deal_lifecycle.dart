enum SandboxPaymentStatus { notStarted, pending, success, failed, refunded }

enum SandboxDealStatus { negotiating, confirmed, readyForPickup, outForDelivery, completed, cancelled }

class SandboxDealLifecycleState {
  const SandboxDealLifecycleState({
    required this.dealId,
    this.dealStatus = SandboxDealStatus.negotiating,
    this.paymentStatus = SandboxPaymentStatus.notStarted,
    this.invoiceCreated = false,
    this.reviewAllowed = false,
  });

  final String dealId;
  final SandboxDealStatus dealStatus;
  final SandboxPaymentStatus paymentStatus;
  final bool invoiceCreated;
  final bool reviewAllowed;

  bool get paymentSettled => paymentStatus == SandboxPaymentStatus.success;
  bool get canCreateInvoice => paymentSettled && dealStatus != SandboxDealStatus.cancelled;
  bool get canComplete => paymentSettled && invoiceCreated && dealStatus != SandboxDealStatus.cancelled;

  SandboxDealLifecycleState copyWith({
    SandboxDealStatus? dealStatus,
    SandboxPaymentStatus? paymentStatus,
    bool? invoiceCreated,
    bool? reviewAllowed,
  }) => SandboxDealLifecycleState(
        dealId: dealId,
        dealStatus: dealStatus ?? this.dealStatus,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        invoiceCreated: invoiceCreated ?? this.invoiceCreated,
        reviewAllowed: reviewAllowed ?? this.reviewAllowed,
      );
}

class SandboxDealLifecycleStore {
  final Map<String, SandboxDealLifecycleState> _states = <String, SandboxDealLifecycleState>{};

  SandboxDealLifecycleState stateFor(String dealId) =>
      _states[dealId] ?? SandboxDealLifecycleState(dealId: dealId);

  SandboxDealLifecycleState confirm(String dealId) =>
      _save(stateFor(dealId).copyWith(dealStatus: SandboxDealStatus.confirmed));

  SandboxDealLifecycleState setPayment(String dealId, SandboxPaymentStatus status) {
    final current = stateFor(dealId);
    if (current.dealStatus == SandboxDealStatus.cancelled) {
      throw StateError('Cancelled sandbox deal cannot accept a payment change.');
    }
    return _save(current.copyWith(paymentStatus: status));
  }

  SandboxDealLifecycleState markInvoiceCreated(String dealId) {
    final current = stateFor(dealId);
    if (!current.canCreateInvoice) {
      throw StateError('Successful sandbox payment is required before invoice creation.');
    }
    return _save(current.copyWith(invoiceCreated: true));
  }

  SandboxDealLifecycleState complete(String dealId) {
    final current = stateFor(dealId);
    if (!current.canComplete) {
      throw StateError('Payment and invoice must be complete before deal completion.');
    }
    return _save(current.copyWith(
      dealStatus: SandboxDealStatus.completed,
      reviewAllowed: true,
    ));
  }

  SandboxDealLifecycleState cancel(String dealId) => _save(stateFor(dealId).copyWith(
        dealStatus: SandboxDealStatus.cancelled,
        reviewAllowed: false,
      ));

  SandboxDealLifecycleState refund(String dealId) {
    final current = stateFor(dealId);
    if (!current.paymentSettled) {
      throw StateError('Only a successful sandbox payment can be refunded.');
    }
    return _save(current.copyWith(
      paymentStatus: SandboxPaymentStatus.refunded,
      reviewAllowed: false,
    ));
  }

  SandboxDealLifecycleState _save(SandboxDealLifecycleState state) {
    _states[state.dealId] = state;
    return state;
  }
}
