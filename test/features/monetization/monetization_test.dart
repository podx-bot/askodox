import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/monetization/application/monetization_controller.dart';
import 'package:podx/features/monetization/data/mock_monetization_repositories.dart';
import 'package:podx/features/monetization/domain/monetization_models.dart';

void main() {
  late MockSubscriptionRepository subscriptions;
  late MonetizationController controller;
  setUp(() { subscriptions = MockSubscriptionRepository(now: DateTime(2026, 7, 25)); controller = MonetizationController(subscriptions, MockPaymentGateway(), MockPromoCodeRepository()); });

  test('plan comparison data has configurable prices and limits', () {
    expect(mockSellerPlans.map((p) => p.monthlyPrice), [0, 299, 799, 1499]);
    expect(mockSellerPlans.firstWhere((p) => p.id == 'growth').limits.activeListings, 100);
    expect(mockSellerPlans.firstWhere((p) => p.id == 'starter').annualSavings, greaterThan(0));
  });
  test('entitlements resolve from feature configuration, not plan names', () {
    final service = MockEntitlementService(mockSellerPlans);
    expect(service.isEntitled(subscriptions.current, FeatureEntitlement.advancedDemandInsights), isFalse);
    final growth = subscriptions.current.copyWith(planId: 'growth', status: SubscriptionStatus.active);
    expect(service.isEntitled(growth, FeatureEntitlement.advancedDemandInsights), isTrue);
  });
  test('listing limit returns usage and plan limit', () { final result = controller.limit('listings'); expect(result.allowed, isFalse); expect(result.usage, 5); expect(result.limit, 5); });
  test('eligible trial activates without payment details', () async { await controller.activateTrial('starter'); expect(controller.state.subscription.status, SubscriptionStatus.trial); expect(controller.state.subscription.trialStatus, TrialStatus.active); expect(controller.state.payment, isNull); });
  test('upgrade and mock payment success activate plan', () async { final plan=mockSellerPlans[2]; controller.selectPlan(plan, BillingCycle.annual); final result=await controller.pay(PaymentMethodType.upi); expect(result.status, PaymentStatus.successful); expect(controller.state.subscription.planId, 'growth'); expect(controller.state.subscription.status, SubscriptionStatus.active); });
  test('mock payment failure does not activate plan', () async { controller.selectPlan(mockSellerPlans[2], BillingCycle.monthly); final result=await controller.pay(PaymentMethodType.card, simulateFailure:true); expect(result.status, PaymentStatus.failed); expect(controller.state.subscription.planId, 'free'); });
  test('cancellation retains plan and allows reactivation', () async { controller.selectPlan(mockSellerPlans[1], BillingCycle.monthly); await controller.pay(PaymentMethodType.wallet); await controller.cancel(); expect(controller.state.subscription.planId, 'starter'); expect(controller.state.subscription.cancelAtPeriodEnd, isTrue); await controller.reactivate(); expect(controller.state.subscription.status, SubscriptionStatus.active); });
  test('downgrade is scheduled for next renewal', () async { controller.selectPlan(mockSellerPlans[3], BillingCycle.monthly); await controller.pay(PaymentMethodType.upi); await controller.downgrade('starter'); expect(controller.state.subscription.pendingPlanId, 'starter'); expect(controller.state.changeRequest?.isDowngrade, isTrue); });
  test('promo validation covers valid invalid expired and usage limit', () async { final repo=MockPromoCodeRepository(now:DateTime(2026,7,25)); expect((await repo.validate('SAVE20')).isValid,isTrue); expect((await repo.validate('nope')).message,'invalid'); expect((await repo.validate('EXPIRED')).message,'expired'); expect((await repo.validate('USEDUP')).message,'usageLimit'); });
  test('invoice history is local demo data', () async { final invoices=await MockInvoiceRepository().invoicesFor('seller-demo'); expect(invoices.single.status,InvoiceStatus.paid); expect(invoices.single.gst.gstin,isEmpty); });
  test('admin plan change requires a reason', () async { expect(() => subscriptions.adminChangePlan('growth',''),throwsArgumentError); final changed=await subscriptions.adminChangePlan('growth','Support adjustment'); expect(changed.planId,'growth'); });
}
