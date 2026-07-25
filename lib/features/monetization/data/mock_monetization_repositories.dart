import 'dart:async';
import '../domain/monetization_models.dart';
import '../domain/monetization_repositories.dart';

const _listing = FeatureEntitlement.listMoreProducts;
PlanFeature feature(FeatureEntitlement value) => PlanFeature(value, description: value.name);

final mockSellerPlans = <SellerPlan>[
  SellerPlan(id: 'free', name: 'Free', monthlyPrice: 0, annualPrice: 0, visibility: 'Standard', supportLevel: 'Community', features: [feature(FeatureEntitlement.paidLeadAccess)], limits: const PlanLimit(activeListings: 5, offerCampaigns: 0, shopLocations: 1, buyerRequestResponses: 3, analyticsHistoryDays: 7)),
  SellerPlan(id: 'starter', name: 'Starter', monthlyPrice: 299, annualPrice: 2990, trialDays: 7, visibility: 'Standard+', supportLevel: 'Email', features: [feature(_listing), feature(FeatureEntitlement.sellerAnalytics), feature(FeatureEntitlement.promotionalOffers), feature(FeatureEntitlement.paidLeadAccess)], limits: const PlanLimit(activeListings: 25, offerCampaigns: 2, shopLocations: 1, buyerRequestResponses: 30, analyticsHistoryDays: 30)),
  SellerPlan(id: 'growth', name: 'Growth', monthlyPrice: 799, annualPrice: 7990, trialDays: 14, visibility: 'Priority placeholder', supportLevel: 'Priority email', features: [feature(_listing), feature(FeatureEntitlement.sellerAnalytics), feature(FeatureEntitlement.advancedDemandInsights), feature(FeatureEntitlement.promotionalOffers), feature(FeatureEntitlement.priorityRequests), feature(FeatureEntitlement.paidLeadAccess)], limits: const PlanLimit(activeListings: 100, offerCampaigns: 10, shopLocations: 2, buyerRequestResponses: 150, analyticsHistoryDays: 180)),
  SellerPlan(id: 'pro', name: 'Pro', monthlyPrice: 1499, annualPrice: 14990, trialDays: 14, visibility: 'Featured eligible', supportLevel: 'Priority placeholder', features: [for (final e in FeatureEntitlement.values) feature(e)], limits: const PlanLimit(activeListings: 500, offerCampaigns: 50, shopLocations: 10, buyerRequestResponses: 1000, analyticsHistoryDays: 365)),
];

class MockSubscriptionRepository implements SubscriptionRepository {
  MockSubscriptionRepository({DateTime? now}) : _now = now ?? DateTime(2026, 7, 25) { _current = Subscription(id: 'sub-demo', sellerId: 'seller-demo', planId: 'free', status: SubscriptionStatus.free, billingCycle: BillingCycle.monthly, startDate: _now, renewalDate: _now.add(const Duration(days: 30)), trialStatus: TrialStatus.eligible, autoRenew: false); }
  final DateTime _now; late Subscription _current; final _stream = StreamController<Subscription>.broadcast();
  @override List<SellerPlan> get plans => mockSellerPlans; @override Subscription get current => _current; @override Stream<Subscription> watch() => _stream.stream;
  Subscription _save(Subscription value) { _current = value; _stream.add(value); return value; }
  @override Future<Subscription> activate(String planId, BillingCycle cycle) async => _save(_current.copyWith(planId: planId, billingCycle: cycle, status: SubscriptionStatus.active, trialStatus: TrialStatus.converted, autoRenew: true, renewalDate: _now.add(Duration(days: cycle == BillingCycle.monthly ? 30 : 365)), clearPendingPlan: true));
  @override Future<Subscription> activateTrial(String planId) async { final plan = plans.firstWhere((e) => e.id == planId); if (_current.trialStatus != TrialStatus.eligible || plan.trialDays == 0) throw StateError('Trial unavailable'); return _save(_current.copyWith(planId: planId, status: SubscriptionStatus.trial, trialStatus: TrialStatus.active, trialEndsAt: _now.add(Duration(days: plan.trialDays)), autoRenew: false)); }
  @override Future<Subscription> cancel() async => _save(_current.copyWith(status: SubscriptionStatus.cancelled, autoRenew: false, cancelAtPeriodEnd: true));
  @override Future<Subscription> reactivate() async => _save(_current.copyWith(status: SubscriptionStatus.active, autoRenew: true, cancelAtPeriodEnd: false));
  @override Future<Subscription> scheduleDowngrade(String planId) async => _save(_current.copyWith(pendingPlanId: planId));
  @override Future<Subscription> adminChangePlan(String planId, String reason) async { if (reason.trim().isEmpty) throw ArgumentError('Admin reason required'); return activate(planId, _current.billingCycle); }
  @override Future<Subscription> extendTrial(int days, String reason) async { if (reason.trim().isEmpty) throw ArgumentError('Admin reason required'); return _save(_current.copyWith(status: SubscriptionStatus.trial, trialStatus: TrialStatus.active, trialEndsAt: (_current.trialEndsAt ?? _now).add(Duration(days: days)))); }
}

class MockPaymentGateway implements PaymentGateway {
  @override String get providerName => 'PODX demo gateway';
  @override Future<PaymentAttempt> pay({required SellerPlan plan, required BillingCycle cycle, required PaymentMethodType method, bool simulateFailure = false}) async { await Future<void>.delayed(const Duration(milliseconds: 30)); return PaymentAttempt(id: 'pay-${DateTime.now().microsecondsSinceEpoch}', planId: plan.id, amount: plan.price(cycle), method: method, status: simulateFailure ? PaymentStatus.failed : PaymentStatus.successful, createdAt: DateTime.now(), serverConfirmationReference: simulateFailure ? null : 'DEMO-NOT-SERVER-VERIFIED'); }
}
class MockEntitlementService implements EntitlementService {
  MockEntitlementService(this.plans); final List<SellerPlan> plans;
  @override bool isEntitled(Subscription subscription, FeatureEntitlement entitlement) { if ({SubscriptionStatus.expired, SubscriptionStatus.suspended, SubscriptionStatus.paymentFailed}.contains(subscription.status)) return false; return plans.firstWhere((e) => e.id == subscription.planId).features.any((e) => e.entitlement == entitlement); }
  @override LimitResult checkLimit(SellerUsage usage, PlanLimit limit, String name) { final (used, maximum) = switch(name) { 'listings' => (usage.activeListings, limit.activeListings), 'offers' => (usage.offers, limit.offerCampaigns), 'shops' => (usage.shopLocations, limit.shopLocations), 'responses' => (usage.buyerRequestResponses, limit.buyerRequestResponses), _ => throw ArgumentError('Unknown limit') }; return LimitResult(allowed: used < maximum, usage: used, limit: maximum, limitName: name); }
}
class MockPromoCodeRepository implements PromoCodeRepository {
  MockPromoCodeRepository({DateTime? now}) : now = now ?? DateTime(2026, 7, 25); final DateTime now;
  final codes = <PromoCode>[PromoCode(code: 'SAVE20', type: DiscountType.percentage, value: 20, expiresAt: DateTime(2027), usageLimit: 100), PromoCode(code: 'EXPIRED', type: DiscountType.fixed, value: 100, expiresAt: DateTime(2025), usageLimit: 100), PromoCode(code: 'USEDUP', type: DiscountType.trialExtension, value: 7, expiresAt: DateTime(2027), usageLimit: 1, used: 1)];
  @override Future<PromoValidation> validate(String input) async { final matches = codes.where((e) => e.code == input.trim().toUpperCase()); final code = matches.isEmpty ? null : matches.first; if (code == null || !code.active) return const PromoValidation(isValid: false, message: 'invalid'); if (code.expiresAt.isBefore(now)) return const PromoValidation(isValid: false, message: 'expired'); if (code.used >= code.usageLimit) return const PromoValidation(isValid: false, message: 'usageLimit'); return PromoValidation(isValid: true, message: 'valid', promo: code); }
}
class MockInvoiceRepository implements InvoiceRepository { final data = <Invoice>[Invoice(number: 'PODX-DEMO-001', planName: 'Starter', period: 'Jul 2026', amount: 299, taxPlaceholder: 54, total: 353, status: InvoiceStatus.paid, date: DateTime(2026, 7, 1))]; @override Future<List<Invoice>> invoicesFor(String sellerId) async => List.unmodifiable(data); @override Future<void> requestDownload(String invoiceNumber) async {} }
class MockBillingRepository implements BillingRepository { @override final List<PaymentAttempt> attempts = []; @override Future<RefundStatus> updateRefund(String paymentId, RefundStatus status, String adminReason) async { if (adminReason.trim().isEmpty) throw ArgumentError('Admin reason required'); return status; } }
