import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deals/domain/sandbox_deal_lifecycle.dart';

void main() {
  test('sandbox deal requires payment and invoice before completion and review', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-investor-deal';

    expect(store.stateFor(dealId).reviewAllowed, isFalse);
    store.confirm(dealId);

    expect(() => store.markInvoiceCreated(dealId), throwsStateError);
    expect(() => store.complete(dealId), throwsStateError);

    store.setPayment(dealId, SandboxPaymentStatus.success);
    expect(store.stateFor(dealId).canCreateInvoice, isTrue);

    store.markInvoiceCreated(dealId);
    expect(store.stateFor(dealId).canComplete, isTrue);

    final completed = store.complete(dealId);
    expect(completed.dealStatus, SandboxDealStatus.completed);
    expect(completed.reviewAllowed, isTrue);
  });

  test('failed payment cannot unlock invoice or completion', () {
    final store = SandboxDealLifecycleStore();
    const dealId = 'local-failed-payment';
    store.confirm(dealId);
    store.setPayment(dealId, SandboxPaymentStatus.failed);

    expect(store.stateFor(dealId).canCreateInvoice, isFalse);
    expect(() => store.markInvoiceCreated(dealId), throwsStateError);
    expect(() => store.complete(dealId), throwsStateError);
  });

  test('refund disables review and cancelled deal rejects payment changes', () {
    final store = SandboxDealLifecycleStore();
    const paidDeal = 'local-paid';
    store.confirm(paidDeal);
    store.setPayment(paidDeal, SandboxPaymentStatus.success);
    store.markInvoiceCreated(paidDeal);
    store.complete(paidDeal);

    final refunded = store.refund(paidDeal);
    expect(refunded.paymentStatus, SandboxPaymentStatus.refunded);
    expect(refunded.reviewAllowed, isFalse);

    const cancelledDeal = 'local-cancelled';
    store.cancel(cancelledDeal);
    expect(
      () => store.setPayment(cancelledDeal, SandboxPaymentStatus.success),
      throwsStateError,
    );
  });
}
