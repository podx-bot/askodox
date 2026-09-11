enum SandboxPaymentStatus { notStarted, pending, success, failed, refunded }

enum SandboxDealStatus {
  negotiating,
  confirmed,
  readyForPickup,
  outForDelivery,
  completed,
  cancelled,
}

enum SandboxFulfilmentMode { delivery, pickup }

class SandboxFulfilmentConfirmation {
  const SandboxFulfilmentConfirmation({
    required this.mode,
    required this.locationConfirmed,
    required this.timingConfirmed,
    required this.chargeConfirmed,
  });

  final SandboxFulfilmentMode mode;
  final bool locationConfirmed;
  final bool timingConfirmed;
  final bool chargeConfirmed;

  bool get isComplete => locationConfirmed && timingConfirmed && chargeConfirmed;
}

class SandboxDealLifecycleState {
  const SandboxDealLifecycleState({
    required this.dealId,
    this.dealStatus = SandboxDealStatus.negotiating,
    this.paymentStatus = SandboxPaymentStatus.notStarted,
    this.fulfilment,
    this.invoiceCreated = false,
    this.reviewAllowed = false,
  });

  final String dealId;
  final SandboxDealStatus dealStatus;
  final SandboxPaymentStatus paymentStatus;
  final SandboxFulfilmentConfirmation? fulfilment;
  final bool invoiceCreated;
  final bool reviewAllowed;

  bool get fulfilmentConfirmed => fulfilment?.isComplete ?? false;
  bool get paymentSettled => paymentStatus == SandboxPaymentStatus.success;
  bool get canStartPayment =>
      fulfilmentConfirmed && dealStatus != SandboxDealStatus.cancelled;
  bool get canCreateInvoice =>
      fulfilmentConfirmed && paymentSettled && dealStatus != SandboxDealStatus.cancelled;
  bool get canComplete => fulfilmentConfirmed &&
      paymentSettled &&
      invoiceCreated &&
      dealStatus != SandboxDealStatus.cancelled;

  SandboxDealLifecycleState copyWith({
    SandboxDealStatus? dealStatus,
    SandboxPaymentStatus? paymentStatus,
    SandboxFulfilmentConfirmation? fulfilment,
    bool? invoiceCreated,
    bool? reviewAllowed,
  }) => SandboxDealLifecycleState(
        dealId: dealId,
        dealStatus: dealStatus ?? this.dealStatus,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        fulfilment: fulfilment ?? this.fulfilment,
        invoiceCreated: invoiceCreated ?? this.invoiceCreated,
        reviewAllowed: reviewAllowed ?? this.reviewAllowed,
      );
}

class SandboxDealLifecycleStore {
  final Map<String, SandboxDealLifecycleState> _states =
      <String, SandboxDealLifecycleState>{};

  SandboxDealLifecycleState stateFor(String dealId) =>
      _states[dealId] ?? SandboxDealLifecycleState(dealId: dealId);

  SandboxDealLifecycleState confirm(String dealId) =>
      _save(stateFor(dealId).copyWith(dealStatus: SandboxDealStatus.confirmed));

  SandboxDealLifecycleState confirmFulfilment(
    String dealId,
    SandboxFulfilmentConfirmation fulfilment,
  ) {
    final current = stateFor(dealId);
    if (current.dealStatus == SandboxDealStatus.cancelled) {
      throw StateError('Cancelled sandbox deal cannot confirm fulfilment.');
    }
    if (!fulfilment.isComplete) {
      throw StateError(
        'Location, timing and delivery/pickup charge must be confirmed before payment.',
      );
    }
    return _save(current.copyWith(fulfilment: fulfilment));
  }

  SandboxDealLifecycleState setPayment(
    String dealId,
    SandboxPaymentStatus status,
  ) {
    final current = stateFor(dealId);
    if (current.dealStatus == SandboxDealStatus.cancelled) {
      throw StateError('Cancelled sandbox deal cannot accept a payment change.');
    }
    if (status != SandboxPaymentStatus.notStarted && !current.canStartPayment) {
      throw StateError(
        'Delivery or pickup fulfilment must be confirmed before payment.',
      );
    }
    return _save(current.copyWith(paymentStatus: status));
  }

  SandboxDealLifecycleState markInvoiceCreated(String dealId) {
    final current = stateFor(dealId);
    if (!current.canCreateInvoice) {
      throw StateError(
        'Confirmed fulfilment and successful sandbox payment are required before invoice creation.',
      );
    }
    return _save(current.copyWith(invoiceCreated: true));
  }

  SandboxDealLifecycleState complete(String dealId) {
    final current = stateFor(dealId);
    if (!current.canComplete) {
      throw StateError(
        'Fulfilment, payment and invoice must be complete before deal completion.',
      );
    }
    return _save(current.copyWith(
      dealStatus: SandboxDealStatus.completed,
      reviewAllowed: true,
    ));
  }

  SandboxDealLifecycleState cancel(String dealId) =>
      _save(stateFor(dealId).copyWith(
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
