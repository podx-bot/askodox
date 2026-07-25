import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_monetization_repositories.dart';
import '../domain/monetization_models.dart';
import '../domain/monetization_repositories.dart';

class MonetizationState {
  const MonetizationState({required this.plans, required this.subscription, required this.usage, this.selectedPlan, this.cycle = BillingCycle.monthly, this.payment, this.promo, this.changeRequest, this.busy = false});
  final List<SellerPlan> plans; final Subscription subscription; final SellerUsage usage; final SellerPlan? selectedPlan; final BillingCycle cycle; final PaymentAttempt? payment; final PromoValidation? promo; final PlanChangeRequest? changeRequest; final bool busy;
  SellerPlan get currentPlan => plans.firstWhere((e) => e.id == subscription.planId);
  MonetizationState copyWith({Subscription? subscription, SellerUsage? usage, SellerPlan? selectedPlan, BillingCycle? cycle, PaymentAttempt? payment, PromoValidation? promo, PlanChangeRequest? changeRequest, bool? busy}) => MonetizationState(plans: plans, subscription: subscription ?? this.subscription, usage: usage ?? this.usage, selectedPlan: selectedPlan ?? this.selectedPlan, cycle: cycle ?? this.cycle, payment: payment ?? this.payment, promo: promo ?? this.promo, changeRequest: changeRequest ?? this.changeRequest, busy: busy ?? this.busy);
}
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((_) => MockSubscriptionRepository());
final paymentGatewayProvider = Provider<PaymentGateway>((_) => MockPaymentGateway());
final promoRepositoryProvider = Provider<PromoCodeRepository>((_) => MockPromoCodeRepository());
final invoiceRepositoryProvider = Provider<InvoiceRepository>((_) => MockInvoiceRepository());
final entitlementServiceProvider = Provider<EntitlementService>((ref) => MockEntitlementService(ref.read(subscriptionRepositoryProvider).plans));
final monetizationControllerProvider = StateNotifierProvider<MonetizationController, MonetizationState>((ref) => MonetizationController(ref.read(subscriptionRepositoryProvider), ref.read(paymentGatewayProvider), ref.read(promoRepositoryProvider)));
class MonetizationController extends StateNotifier<MonetizationState> {
  MonetizationController(this.repository, this.gateway, this.promos) : super(MonetizationState(plans: repository.plans, subscription: repository.current, usage: const SellerUsage(activeListings: 5, offers: 0, shopLocations: 1, buyerRequestResponses: 3)));
  final SubscriptionRepository repository; final PaymentGateway gateway; final PromoCodeRepository promos;
  void selectPlan(SellerPlan plan, BillingCycle cycle) => state = state.copyWith(selectedPlan: plan, cycle: cycle);
  Future<void> activateTrial(String id) async => state = state.copyWith(subscription: await repository.activateTrial(id));
  Future<PaymentAttempt> pay(PaymentMethodType method, {bool simulateFailure = false}) async { final plan = state.selectedPlan; if (plan == null) throw StateError('Select a plan'); state = state.copyWith(busy: true); final result = await gateway.pay(plan: plan, cycle: state.cycle, method: method, simulateFailure: simulateFailure); var subscription = state.subscription; if (result.status == PaymentStatus.successful) subscription = await repository.activate(plan.id, state.cycle); state = state.copyWith(payment: result, subscription: subscription, busy: false); return result; }
  Future<void> cancel() async => state = state.copyWith(subscription: await repository.cancel());
  Future<void> reactivate() async => state = state.copyWith(subscription: await repository.reactivate());
  Future<void> downgrade(String id) async { final updated = await repository.scheduleDowngrade(id); state = state.copyWith(subscription: updated, changeRequest: PlanChangeRequest(fromPlanId: state.subscription.planId, toPlanId: id, effectiveAt: state.subscription.renewalDate, isDowngrade: true, reason: 'Seller requested')); }
  Future<void> applyPromo(String code) async => state = state.copyWith(promo: await promos.validate(code));
  Future<void> adminChangePlan(String id, String reason) async => state = state.copyWith(subscription: await repository.adminChangePlan(id, reason));
  Future<void> adminGrantTrial(String id, String reason) async { if (reason.trim().isEmpty) throw ArgumentError('Admin reason required'); state = state.copyWith(subscription: await repository.activateTrial(id)); }
  LimitResult limit(String name) => MockEntitlementService(state.plans).checkLimit(state.usage, state.currentPlan.limits, name);
}
