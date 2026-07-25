enum BillingCycle { monthly, annual }
enum SubscriptionStatus { free, trial, active, paymentPending, paymentFailed, gracePeriod, cancelled, expired, suspended }
enum TrialStatus { eligible, active, expired, converted, cancelled, ineligible }
enum PaymentStatus { processing, successful, failed, cancelled }
enum PaymentMethodType { upi, card, netBanking, wallet }
enum DiscountType { percentage, fixed, trialExtension }
enum InvoiceStatus { paid, pending, failed, refunded }
enum RefundStatus { notRequested, requested, approved, rejected, processing, refunded }
enum FeatureEntitlement { listMoreProducts, advancedDemandInsights, promotionalOffers, priorityRequests, featuredPlacement, sellerAnalytics, multipleShops, exportReports, paidLeadAccess }

class PlanFeature { const PlanFeature(this.entitlement, {required this.description}); final FeatureEntitlement entitlement; final String description; }
class PlanLimit {
  const PlanLimit({required this.activeListings, required this.offerCampaigns, required this.shopLocations, required this.buyerRequestResponses, required this.analyticsHistoryDays});
  final int activeListings, offerCampaigns, shopLocations, buyerRequestResponses, analyticsHistoryDays;
}
class SellerPlan {
  const SellerPlan({required this.id, required this.name, required this.monthlyPrice, required this.annualPrice, required this.features, required this.limits, required this.visibility, required this.supportLevel, this.trialDays = 0, this.available = true});
  final String id, name, visibility, supportLevel; final int monthlyPrice, annualPrice, trialDays; final List<PlanFeature> features; final PlanLimit limits; final bool available;
  int price(BillingCycle cycle) => cycle == BillingCycle.monthly ? monthlyPrice : annualPrice;
  int get annualSavings => monthlyPrice * 12 - annualPrice;
}
class Subscription {
  const Subscription({required this.id, required this.sellerId, required this.planId, required this.status, required this.billingCycle, required this.startDate, required this.renewalDate, required this.trialStatus, required this.autoRenew, this.trialEndsAt, this.pendingPlanId, this.cancelAtPeriodEnd = false, this.paymentMethodLabel = 'Not added (demo)'});
  final String id, sellerId, planId, paymentMethodLabel; final SubscriptionStatus status; final BillingCycle billingCycle; final DateTime startDate, renewalDate; final TrialStatus trialStatus; final DateTime? trialEndsAt; final bool autoRenew, cancelAtPeriodEnd; final String? pendingPlanId;
  int get trialDaysRemaining => trialEndsAt == null ? 0 : (trialEndsAt!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 999).toInt();
  Subscription copyWith({String? planId, SubscriptionStatus? status, BillingCycle? billingCycle, DateTime? renewalDate, TrialStatus? trialStatus, DateTime? trialEndsAt, bool? autoRenew, bool? cancelAtPeriodEnd, String? pendingPlanId, bool clearPendingPlan = false}) => Subscription(id: id, sellerId: sellerId, planId: planId ?? this.planId, status: status ?? this.status, billingCycle: billingCycle ?? this.billingCycle, startDate: startDate, renewalDate: renewalDate ?? this.renewalDate, trialStatus: trialStatus ?? this.trialStatus, trialEndsAt: trialEndsAt ?? this.trialEndsAt, autoRenew: autoRenew ?? this.autoRenew, cancelAtPeriodEnd: cancelAtPeriodEnd ?? this.cancelAtPeriodEnd, pendingPlanId: clearPendingPlan ? null : pendingPlanId ?? this.pendingPlanId, paymentMethodLabel: paymentMethodLabel);
}
class PaymentAttempt { const PaymentAttempt({required this.id, required this.planId, required this.amount, required this.method, required this.status, required this.createdAt, this.serverConfirmationReference}); final String id, planId; final int amount; final PaymentMethodType method; final PaymentStatus status; final DateTime createdAt; final String? serverConfirmationReference; }
class PromoCode { const PromoCode({required this.code, required this.type, required this.value, required this.expiresAt, required this.usageLimit, this.used = 0, this.active = true}); final String code; final DiscountType type; final int value, usageLimit, used; final DateTime expiresAt; final bool active; }
class PromoValidation { const PromoValidation({required this.isValid, required this.message, this.promo}); final bool isValid; final String message; final PromoCode? promo; }
class GstPlaceholder { const GstPlaceholder({this.businessLegalName = '', this.gstin = '', this.billingAddress = '', this.state = '', this.placeOfSupply = '', this.taxableAmount = 0, this.cgst = 0, this.sgst = 0, this.igst = 0}); final String businessLegalName, gstin, billingAddress, state, placeOfSupply; final int taxableAmount, cgst, sgst, igst; }
class Invoice { const Invoice({required this.number, required this.planName, required this.period, required this.amount, required this.taxPlaceholder, required this.total, required this.status, required this.date, this.gst = const GstPlaceholder()}); final String number, planName, period; final int amount, taxPlaceholder, total; final InvoiceStatus status; final DateTime date; final GstPlaceholder gst; }
class SellerUsage { const SellerUsage({required this.activeListings, required this.offers, required this.shopLocations, required this.buyerRequestResponses, this.storageMb = 0}); final int activeListings, offers, shopLocations, buyerRequestResponses, storageMb; }
class LimitResult { const LimitResult({required this.allowed, required this.usage, required this.limit, required this.limitName}); final bool allowed; final int usage, limit; final String limitName; }
class PlanChangeRequest { const PlanChangeRequest({required this.fromPlanId, required this.toPlanId, required this.effectiveAt, required this.isDowngrade, required this.reason}); final String fromPlanId, toPlanId, reason; final DateTime effectiveAt; final bool isDowngrade; }
class RevenueMetric { const RevenueMetric(this.label, this.value, {this.planId}); final String label; final double value; final String? planId; }
