import 'monetization_models.dart';

/// Provider-neutral boundary. Production implementations must return only a
/// backend-verified result; a client callback is never proof of payment.
abstract interface class PaymentGateway { String get providerName; Future<PaymentAttempt> pay({required SellerPlan plan, required BillingCycle cycle, required PaymentMethodType method, bool simulateFailure = false}); }
abstract interface class SubscriptionRepository { List<SellerPlan> get plans; Subscription get current; Stream<Subscription> watch(); Future<Subscription> activate(String planId, BillingCycle cycle); Future<Subscription> activateTrial(String planId); Future<Subscription> cancel(); Future<Subscription> reactivate(); Future<Subscription> scheduleDowngrade(String planId); Future<Subscription> adminChangePlan(String planId, String reason); Future<Subscription> extendTrial(int days, String reason); }
abstract interface class BillingRepository { List<PaymentAttempt> get attempts; Future<RefundStatus> updateRefund(String paymentId, RefundStatus status, String adminReason); }
abstract interface class InvoiceRepository { Future<List<Invoice>> invoicesFor(String sellerId); Future<void> requestDownload(String invoiceNumber); }
abstract interface class PromoCodeRepository { Future<PromoValidation> validate(String code); }
abstract interface class EntitlementService { bool isEntitled(Subscription subscription, FeatureEntitlement entitlement); LimitResult checkLimit(SellerUsage usage, PlanLimit limit, String limitName); }

/// Future adapters should implement [PaymentGateway] without leaking SDK types.
abstract interface class RazorpayGateway implements PaymentGateway {}
abstract interface class CashfreeGateway implements PaymentGateway {}
abstract interface class StripeGateway implements PaymentGateway {}
abstract interface class GooglePlayBillingGateway implements PaymentGateway {}
abstract interface class AppleInAppPurchaseGateway implements PaymentGateway {}
