import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deals/domain/sandbox_deal_lifecycle.dart';

void main() {
  const delivery = SandboxFulfilmentConfirmation(
    mode: SandboxFulfilmentMode.delivery,
    locationConfirmed: true,
    timingConfirmed: true,
    chargeConfirmed: true,
  );

  const pickup = SandboxFulfilmentConfirmation(
    mode: SandboxFulfilmentMode.pickup,
    locationConfirmed: true,
    timingConfirmed: true,
    chargeConfirmed: true,
  );

  test('payment stays locked until delivery fulfilment is fully confirmed', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-delivery-gate';

    store.confirm(dealId);
    expect(store.stateFor(dealId).canStartPayment, isFalse);
    expect(
      () => store.setPayment(dealId, SandboxPaymentStatus.success),
      throwsStateError,
    );

    expect(
      () => store.confirmFulfilment(
        dealId,
        const SandboxFulfilmentConfirmation(
          mode: SandboxFulfilmentMode.delivery,
          locationConfirmed: true,
          timingConfirmed: false,
          chargeConfirmed: true,
        ),
      ),
      throwsStateError,
    );

    store.confirmFulfilment(dealId, delivery);
    expect(store.stateFor(dealId).canStartPayment, isTrue);
  });

  test('delivery flow is fulfilment then payment then invoice then completion and review', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-investor-delivery';

    store.confirm(dealId);
    store.confirmFulfilment(dealId, delivery);
    store.setPayment(dealId, SandboxPaymentStatus.success);
    expect(store.stateFor(dealId).canCreateInvoice, isTrue);

    store.markInvoiceCreated(dealId);
    expect(store.stateFor(dealId).canComplete, isTrue);

    final completed = store.complete(dealId);
    expect(completed.dealStatus, SandboxDealStatus.completed);
    expect(completed.reviewAllowed, isTrue);
  });

  test('pickup flow also requires pickup place timing and charge confirmation before payment', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-investor-pickup';

    store.confirm(dealId);
    store.confirmFulfilment(dealId, pickup);
    expect(store.stateFor(dealId).fulfilment?.mode, SandboxFulfilmentMode.pickup);
    expect(store.stateFor(dealId).canStartPayment, isTrue);
  });

  test('failed payment cannot unlock invoice or completion after fulfilment', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-failed-payment';
    store.confirm(dealId);
    store.confirmFulfilment(dealId, delivery);
    store.setPayment(dealId, SandboxPaymentStatus.failed);

    expect(store.stateFor(dealId).canCreateInvoice, isFalse);
    expect(() => store.markInvoiceCreated(dealId), throwsStateError);
    expect(() => store.complete(dealId), throwsStateError);
  });

  test('refund disables review and cancelled deal rejects fulfilment or payment changes', () {
    final store = SandboxDealLifecycleStore();
    const paidDeal = 'local-paid';
    store.confirm(paidDeal);
    store.confirmFulfilment(paidDeal, delivery);
    store.setPayment(paidDeal, SandboxPaymentStatus.success);
    store.markInvoiceCreated(paidDeal);
    store.complete(paidDeal);

    final refunded = store.refund(paidDeal);
    expect(refunded.paymentStatus, SandboxPaymentStatus.refunded);
    expect(refunded.reviewAllowed, isFalse);

    const cancelledDeal = 'local-cancelled';
    store.cancel(cancelledDeal);
    expect(
      () => store.confirmFulfilment(cancelledDeal, delivery),
      throwsStateError,
    );
    expect(
      () => store.setPayment(cancelledDeal, SandboxPaymentStatus.success),
      throwsStateError,
    );
  });
}
