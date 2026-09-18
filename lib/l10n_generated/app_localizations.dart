import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_or.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n_generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('or'),
    Locale('te')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'ASKODOX'**
  String get appName;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greeting;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover near you'**
  String get discover;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search products, shops and sellers'**
  String get searchHint;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'Featured near you'**
  String get featured;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @watchlist.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get watchlist;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @sellerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Seller dashboard'**
  String get sellerDashboard;

  /// No description provided for @sellerProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get sellerProducts;

  /// No description provided for @sellerRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get sellerRequests;

  /// No description provided for @sellerInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get sellerInsights;

  /// No description provided for @sellerProfile.
  ///
  /// In en, this message translates to:
  /// **'Seller profile'**
  String get sellerProfile;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get inStock;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @verificationPending.
  ///
  /// In en, this message translates to:
  /// **'Verification pending'**
  String get verificationPending;

  /// No description provided for @adminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Admin dashboard'**
  String get adminDashboard;

  /// No description provided for @sellerVerification.
  ///
  /// In en, this message translates to:
  /// **'Seller verification'**
  String get sellerVerification;

  /// No description provided for @productRequests.
  ///
  /// In en, this message translates to:
  /// **'Product requests'**
  String get productRequests;

  /// No description provided for @moderation.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get moderation;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @auditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditLog;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

  /// No description provided for @sellerPlans.
  ///
  /// In en, this message translates to:
  /// **'Seller plans'**
  String get sellerPlans;

  /// No description provided for @comparePlans.
  ///
  /// In en, this message translates to:
  /// **'Compare plans'**
  String get comparePlans;

  /// No description provided for @demoPricing.
  ///
  /// In en, this message translates to:
  /// **'Demo pricing only'**
  String get demoPricing;

  /// No description provided for @noRealBilling.
  ///
  /// In en, this message translates to:
  /// **'Mock and local data only. No real billing or buyer charges.'**
  String get noRealBilling;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @annual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get annual;

  /// No description provided for @currentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get currentPlan;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get month;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'year'**
  String get year;

  /// No description provided for @saveAmount.
  ///
  /// In en, this message translates to:
  /// **'Save {amount}'**
  String saveAmount(String amount);

  /// No description provided for @productLimit.
  ///
  /// In en, this message translates to:
  /// **'{count} active product listings'**
  String productLimit(int count);

  /// No description provided for @shopVisibility.
  ///
  /// In en, this message translates to:
  /// **'Shop visibility'**
  String get shopVisibility;

  /// No description provided for @upgradePlan.
  ///
  /// In en, this message translates to:
  /// **'Upgrade plan'**
  String get upgradePlan;

  /// No description provided for @downgrade.
  ///
  /// In en, this message translates to:
  /// **'Downgrade'**
  String get downgrade;

  /// No description provided for @reactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// No description provided for @cancelPlan.
  ///
  /// In en, this message translates to:
  /// **'Cancel plan'**
  String get cancelPlan;

  /// No description provided for @startFreeTrial.
  ///
  /// In en, this message translates to:
  /// **'Start {days}-day free trial'**
  String startFreeTrial(int days);

  /// No description provided for @feature.
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get feature;

  /// No description provided for @productListings.
  ///
  /// In en, this message translates to:
  /// **'Product listing limit'**
  String get productListings;

  /// No description provided for @buyerRequestAccess.
  ///
  /// In en, this message translates to:
  /// **'Buyer request access'**
  String get buyerRequestAccess;

  /// No description provided for @demandAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Demand analytics'**
  String get demandAnalytics;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @priceAlerts.
  ///
  /// In en, this message translates to:
  /// **'Price alerts'**
  String get priceAlerts;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get basic;

  /// No description provided for @included.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get included;

  /// No description provided for @promotionalOffers.
  ///
  /// In en, this message translates to:
  /// **'Promotional offers'**
  String get promotionalOffers;

  /// No description provided for @featuredPlacement.
  ///
  /// In en, this message translates to:
  /// **'Featured placement'**
  String get featuredPlacement;

  /// No description provided for @supportLevel.
  ///
  /// In en, this message translates to:
  /// **'Support level'**
  String get supportLevel;

  /// No description provided for @multiShop.
  ///
  /// In en, this message translates to:
  /// **'Multi-shop access placeholder'**
  String get multiShop;

  /// No description provided for @sellerUsage.
  ///
  /// In en, this message translates to:
  /// **'Seller usage'**
  String get sellerUsage;

  /// No description provided for @activeListings.
  ///
  /// In en, this message translates to:
  /// **'Active product listings used'**
  String get activeListings;

  /// No description provided for @offers.
  ///
  /// In en, this message translates to:
  /// **'Offers used'**
  String get offers;

  /// No description provided for @requestResponses.
  ///
  /// In en, this message translates to:
  /// **'Buyer request responses used'**
  String get requestResponses;

  /// No description provided for @shopCount.
  ///
  /// In en, this message translates to:
  /// **'Shop count'**
  String get shopCount;

  /// No description provided for @analyticsAccess.
  ///
  /// In en, this message translates to:
  /// **'Analytics access level'**
  String get analyticsAccess;

  /// No description provided for @historyDays.
  ///
  /// In en, this message translates to:
  /// **'{days}-day history'**
  String historyDays(int days);

  /// No description provided for @storageUsage.
  ///
  /// In en, this message translates to:
  /// **'Storage usage'**
  String get storageUsage;

  /// No description provided for @placeholder.
  ///
  /// In en, this message translates to:
  /// **'Placeholder only'**
  String get placeholder;

  /// No description provided for @limitReached.
  ///
  /// In en, this message translates to:
  /// **'Plan limit reached'**
  String get limitReached;

  /// No description provided for @limitExplanation.
  ///
  /// In en, this message translates to:
  /// **'You are using {used} of {limit}. Upgrade to continue without silently blocking your work.'**
  String limitExplanation(int used, int limit);

  /// No description provided for @currentSubscription.
  ///
  /// In en, this message translates to:
  /// **'Current subscription'**
  String get currentSubscription;

  /// No description provided for @billingCycle.
  ///
  /// In en, this message translates to:
  /// **'Billing cycle'**
  String get billingCycle;

  /// No description provided for @subscriptionStatus.
  ///
  /// In en, this message translates to:
  /// **'Subscription status'**
  String get subscriptionStatus;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @renewalDate.
  ///
  /// In en, this message translates to:
  /// **'Renewal date'**
  String get renewalDate;

  /// No description provided for @trialStatus.
  ///
  /// In en, this message translates to:
  /// **'Trial status'**
  String get trialStatus;

  /// No description provided for @autoRenew.
  ///
  /// In en, this message translates to:
  /// **'Auto-renew status'**
  String get autoRenew;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method placeholder'**
  String get paymentMethod;

  /// No description provided for @downgradeScheduled.
  ///
  /// In en, this message translates to:
  /// **'Downgrade scheduled'**
  String get downgradeScheduled;

  /// No description provided for @nextRenewal.
  ///
  /// In en, this message translates to:
  /// **'Effective at next renewal'**
  String get nextRenewal;

  /// No description provided for @invoiceHistory.
  ///
  /// In en, this message translates to:
  /// **'Invoice history'**
  String get invoiceHistory;

  /// No description provided for @restorePurchase.
  ///
  /// In en, this message translates to:
  /// **'Restore purchase placeholder'**
  String get restorePurchase;

  /// No description provided for @planUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Plan unavailable'**
  String get planUnavailable;

  /// No description provided for @reviewOrder.
  ///
  /// In en, this message translates to:
  /// **'Review demo order'**
  String get reviewOrder;

  /// No description provided for @promoCode.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get promoCode;

  /// No description provided for @promoApplied.
  ///
  /// In en, this message translates to:
  /// **'Demo promo applied'**
  String get promoApplied;

  /// No description provided for @promoInvalid.
  ///
  /// In en, this message translates to:
  /// **'Promo code invalid, expired, or usage limit reached'**
  String get promoInvalid;

  /// No description provided for @continueToDemoPayment.
  ///
  /// In en, this message translates to:
  /// **'Continue to demo payment'**
  String get continueToDemoPayment;

  /// No description provided for @demoPayment.
  ///
  /// In en, this message translates to:
  /// **'Demo payment'**
  String get demoPayment;

  /// No description provided for @demoPaymentOnly.
  ///
  /// In en, this message translates to:
  /// **'Demo payment only'**
  String get demoPaymentOnly;

  /// No description provided for @noPaymentDetails.
  ///
  /// In en, this message translates to:
  /// **'Do not enter real card, UPI, wallet, or bank details.'**
  String get noPaymentDetails;

  /// No description provided for @upi.
  ///
  /// In en, this message translates to:
  /// **'UPI placeholder'**
  String get upi;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Credit or debit card placeholder'**
  String get card;

  /// No description provided for @netBanking.
  ///
  /// In en, this message translates to:
  /// **'Net banking placeholder'**
  String get netBanking;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet placeholder'**
  String get wallet;

  /// No description provided for @confirmDemoPayment.
  ///
  /// In en, this message translates to:
  /// **'Confirm mock payment'**
  String get confirmDemoPayment;

  /// No description provided for @simulateFailure.
  ///
  /// In en, this message translates to:
  /// **'Simulate payment failure'**
  String get simulateFailure;

  /// No description provided for @paymentSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Mock payment successful'**
  String get paymentSuccessful;

  /// No description provided for @entitlementsRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Subscription activated and entitlements refreshed. Production confirmation must happen on the backend.'**
  String get entitlementsRefreshed;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentFailed;

  /// No description provided for @paymentFailureHelp.
  ///
  /// In en, this message translates to:
  /// **'Retry, change the demo method, contact support, or continue on the free plan.'**
  String get paymentFailureHelp;

  /// No description provided for @retryPayment.
  ///
  /// In en, this message translates to:
  /// **'Retry payment'**
  String get retryPayment;

  /// No description provided for @continueFree.
  ///
  /// In en, this message translates to:
  /// **'Continue on free plan'**
  String get continueFree;

  /// No description provided for @noInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices'**
  String get noInvoices;

  /// No description provided for @gstPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'GST fields are placeholders'**
  String get gstPlaceholder;

  /// No description provided for @notTaxCompliant.
  ///
  /// In en, this message translates to:
  /// **'Demo invoice only. GST calculations are not tax compliant.'**
  String get notTaxCompliant;

  /// No description provided for @taxPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Tax placeholder'**
  String get taxPlaceholder;

  /// No description provided for @downloadPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Download invoice placeholder'**
  String get downloadPlaceholder;

  /// No description provided for @subscriptionManagement.
  ///
  /// In en, this message translates to:
  /// **'Subscription management'**
  String get subscriptionManagement;

  /// No description provided for @mrr.
  ///
  /// In en, this message translates to:
  /// **'Monthly recurring revenue'**
  String get mrr;

  /// No description provided for @arr.
  ///
  /// In en, this message translates to:
  /// **'Annual recurring revenue'**
  String get arr;

  /// No description provided for @activePaidSellers.
  ///
  /// In en, this message translates to:
  /// **'Active paid sellers'**
  String get activePaidSellers;

  /// No description provided for @trialSellers.
  ///
  /// In en, this message translates to:
  /// **'Trial sellers'**
  String get trialSellers;

  /// No description provided for @conversionRate.
  ///
  /// In en, this message translates to:
  /// **'Conversion rate'**
  String get conversionRate;

  /// No description provided for @failedPayments.
  ///
  /// In en, this message translates to:
  /// **'Failed payments'**
  String get failedPayments;

  /// No description provided for @cancelledSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Cancelled subscriptions'**
  String get cancelledSubscriptions;

  /// No description provided for @demoRevenueData.
  ///
  /// In en, this message translates to:
  /// **'Demo revenue data'**
  String get demoRevenueData;

  /// No description provided for @revenueByPlan.
  ///
  /// In en, this message translates to:
  /// **'Revenue by plan'**
  String get revenueByPlan;

  /// No description provided for @revenueTrend.
  ///
  /// In en, this message translates to:
  /// **'Revenue trend (mock)'**
  String get revenueTrend;

  /// No description provided for @filterStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by subscription status'**
  String get filterStatus;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get allStatuses;

  /// No description provided for @paymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment status'**
  String get paymentStatus;

  /// No description provided for @noPaymentAttempt.
  ///
  /// In en, this message translates to:
  /// **'No payment attempt'**
  String get noPaymentAttempt;

  /// No description provided for @changePlan.
  ///
  /// In en, this message translates to:
  /// **'Change plan'**
  String get changePlan;

  /// No description provided for @grantTrial.
  ///
  /// In en, this message translates to:
  /// **'Grant trial'**
  String get grantTrial;

  /// No description provided for @extendTrial.
  ///
  /// In en, this message translates to:
  /// **'Extend trial'**
  String get extendTrial;

  /// No description provided for @manualDiscount.
  ///
  /// In en, this message translates to:
  /// **'Apply manual discount'**
  String get manualDiscount;

  /// No description provided for @markPaymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Mark payment received placeholder'**
  String get markPaymentReceived;

  /// No description provided for @mockRefund.
  ///
  /// In en, this message translates to:
  /// **'Mock refund action'**
  String get mockRefund;

  /// No description provided for @paymentFailures.
  ///
  /// In en, this message translates to:
  /// **'Payment failures'**
  String get paymentFailures;

  /// No description provided for @noPaymentFailures.
  ///
  /// In en, this message translates to:
  /// **'No payment failures'**
  String get noPaymentFailures;

  /// No description provided for @trialUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Trial is unavailable'**
  String get trialUnavailable;

  /// No description provided for @demoActionRecorded.
  ///
  /// In en, this message translates to:
  /// **'Demo admin action recorded'**
  String get demoActionRecorded;

  /// No description provided for @adminReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Admin reason required'**
  String get adminReasonRequired;

  /// No description provided for @adminReason.
  ///
  /// In en, this message translates to:
  /// **'Internal reason'**
  String get adminReason;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @communicationCenter.
  ///
  /// In en, this message translates to:
  /// **'Communication center'**
  String get communicationCenter;

  /// No description provided for @productRequestsNew.
  ///
  /// In en, this message translates to:
  /// **'Product requests'**
  String get productRequestsNew;

  /// No description provided for @followedShops.
  ///
  /// In en, this message translates to:
  /// **'Followed shops'**
  String get followedShops;

  /// No description provided for @notificationPreferencesNew.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get notificationPreferencesNew;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @requestProduct.
  ///
  /// In en, this message translates to:
  /// **'Request product'**
  String get requestProduct;

  /// No description provided for @customerEngagement.
  ///
  /// In en, this message translates to:
  /// **'Customer engagement'**
  String get customerEngagement;

  /// No description provided for @campaigns.
  ///
  /// In en, this message translates to:
  /// **'Campaigns'**
  String get campaigns;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcements;

  /// No description provided for @smartSearch.
  ///
  /// In en, this message translates to:
  /// **'Smart search'**
  String get smartSearch;

  /// No description provided for @barcodeSearch.
  ///
  /// In en, this message translates to:
  /// **'Barcode search'**
  String get barcodeSearch;

  /// No description provided for @ocrProductMatching.
  ///
  /// In en, this message translates to:
  /// **'OCR product matching'**
  String get ocrProductMatching;

  /// No description provided for @imageSearch.
  ///
  /// In en, this message translates to:
  /// **'Image search'**
  String get imageSearch;

  /// No description provided for @voiceSearch.
  ///
  /// In en, this message translates to:
  /// **'Voice search'**
  String get voiceSearch;

  /// No description provided for @mockDataOnly.
  ///
  /// In en, this message translates to:
  /// **'Demo only • local data • no external APIs'**
  String get mockDataOnly;

  /// No description provided for @analyticsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get analyticsToday;

  /// No description provided for @analytics7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get analytics7Days;

  /// No description provided for @analytics30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get analytics30Days;

  /// No description provided for @analytics90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get analytics90Days;

  /// No description provided for @analyticsCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get analyticsCustom;

  /// No description provided for @buyerInsights.
  ///
  /// In en, this message translates to:
  /// **'Buyer insights'**
  String get buyerInsights;

  /// No description provided for @sellerAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Seller analytics'**
  String get sellerAnalytics;

  /// No description provided for @privacySafeDemo.
  ///
  /// In en, this message translates to:
  /// **'Privacy-safe local demo data. Your individual activity is never shown to sellers.'**
  String get privacySafeDemo;

  /// No description provided for @activitySummary.
  ///
  /// In en, this message translates to:
  /// **'Activity peaked this week; summaries remain understandable without the chart.'**
  String get activitySummary;

  /// No description provided for @aggregatedDemoData.
  ///
  /// In en, this message translates to:
  /// **'Aggregated demo data only · no individual buyer information'**
  String get aggregatedDemoData;

  /// No description provided for @engagementTrendSummary.
  ///
  /// In en, this message translates to:
  /// **'Engagement is increasing compared with the previous period.'**
  String get engagementTrendSummary;

  /// No description provided for @productPerformance.
  ///
  /// In en, this message translates to:
  /// **'Product performance'**
  String get productPerformance;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @noProductPerformance.
  ///
  /// In en, this message translates to:
  /// **'No product performance data'**
  String get noProductPerformance;

  /// No description provided for @marketAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Market analytics'**
  String get marketAnalytics;

  /// No description provided for @priceCompetitiveness.
  ///
  /// In en, this message translates to:
  /// **'Price competitiveness'**
  String get priceCompetitiveness;

  /// No description provided for @areaAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Area analytics'**
  String get areaAnalytics;

  /// No description provided for @campaignAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Campaign analytics'**
  String get campaignAnalytics;

  /// No description provided for @businessIntelligence.
  ///
  /// In en, this message translates to:
  /// **'Analytics and business intelligence'**
  String get businessIntelligence;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @funnels.
  ///
  /// In en, this message translates to:
  /// **'Funnels'**
  String get funnels;

  /// No description provided for @retention.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get retention;

  /// No description provided for @searchIntelligence.
  ///
  /// In en, this message translates to:
  /// **'Search intelligence'**
  String get searchIntelligence;

  /// No description provided for @dataQuality.
  ///
  /// In en, this message translates to:
  /// **'Data quality'**
  String get dataQuality;

  /// No description provided for @reportBuilder.
  ///
  /// In en, this message translates to:
  /// **'Report builder'**
  String get reportBuilder;

  /// No description provided for @analyticsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Analytics privacy'**
  String get analyticsPrivacy;

  /// No description provided for @analyticsPrivacyExplanation.
  ///
  /// In en, this message translates to:
  /// **'Analytics stays on this device, uses aggregated demo data, and never records phone numbers, addresses, OTPs, tokens, documents, identities, or exact locations.'**
  String get analyticsPrivacyExplanation;

  /// No description provided for @basicUsageAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Allow basic usage analytics'**
  String get basicUsageAnalytics;

  /// No description provided for @basicUsageExplanation.
  ///
  /// In en, this message translates to:
  /// **'Records privacy-safe event categories to improve the demo experience.'**
  String get basicUsageExplanation;

  /// No description provided for @recommendationAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Allow product recommendation analytics'**
  String get recommendationAnalytics;

  /// No description provided for @businessPerformanceAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Allow business performance analytics'**
  String get businessPerformanceAnalytics;

  /// No description provided for @marketComparisonAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Allow aggregated market comparisons'**
  String get marketComparisonAnalytics;

  /// No description provided for @collectedCategories.
  ///
  /// In en, this message translates to:
  /// **'View collected event categories'**
  String get collectedCategories;

  /// No description provided for @clearLocalAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Clear local analytics history'**
  String get clearLocalAnalytics;

  /// No description provided for @localAnalyticsCleared.
  ///
  /// In en, this message translates to:
  /// **'Local analytics history cleared.'**
  String get localAnalyticsCleared;

  /// No description provided for @offlineCopy.
  ///
  /// In en, this message translates to:
  /// **'Offline copy'**
  String get offlineCopy;

  /// No description provided for @connectionLimited.
  ///
  /// In en, this message translates to:
  /// **'Connection is limited'**
  String get connectionLimited;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get syncStatus;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @cachedProducts.
  ///
  /// In en, this message translates to:
  /// **'Cached products'**
  String get cachedProducts;

  /// No description provided for @cachedShopData.
  ///
  /// In en, this message translates to:
  /// **'Cached shop data'**
  String get cachedShopData;

  /// No description provided for @searchHistorySize.
  ///
  /// In en, this message translates to:
  /// **'Search history size'**
  String get searchHistorySize;

  /// No description provided for @imageCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Image cache size'**
  String get imageCacheSize;

  /// No description provided for @analyticsCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Analytics cache size'**
  String get analyticsCacheSize;

  /// No description provided for @pendingSyncSize.
  ///
  /// In en, this message translates to:
  /// **'Pending sync size'**
  String get pendingSyncSize;

  /// No description provided for @totalLocalStorage.
  ///
  /// In en, this message translates to:
  /// **'Total local storage used'**
  String get totalLocalStorage;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear search history'**
  String get clearSearchHistory;

  /// No description provided for @clearStaleData.
  ///
  /// In en, this message translates to:
  /// **'Clear stale data'**
  String get clearStaleData;

  /// No description provided for @clearAnalyticsCache.
  ///
  /// In en, this message translates to:
  /// **'Clear analytics cache'**
  String get clearAnalyticsCache;

  /// No description provided for @clearAllLocalData.
  ///
  /// In en, this message translates to:
  /// **'Clear all local data'**
  String get clearAllLocalData;

  /// No description provided for @clearLocalDataConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Clear caches and queued changes? Authentication and preferences are kept.'**
  String get clearLocalDataConfirmation;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @developerToolsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Developer tools are unavailable in production.'**
  String get developerToolsUnavailable;

  /// No description provided for @performanceMonitor.
  ///
  /// In en, this message translates to:
  /// **'Performance monitor'**
  String get performanceMonitor;

  /// No description provided for @cacheHits.
  ///
  /// In en, this message translates to:
  /// **'Cache hits'**
  String get cacheHits;

  /// No description provided for @cacheMisses.
  ///
  /// In en, this message translates to:
  /// **'Cache misses'**
  String get cacheMisses;

  /// No description provided for @memoryUsagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Memory usage placeholder'**
  String get memoryUsagePlaceholder;

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get pendingChanges;

  /// No description provided for @failedChanges.
  ///
  /// In en, this message translates to:
  /// **'Failed changes'**
  String get failedChanges;

  /// No description provided for @connectionState.
  ///
  /// In en, this message translates to:
  /// **'Connection state'**
  String get connectionState;

  /// No description provided for @lastSuccessfulSync.
  ///
  /// In en, this message translates to:
  /// **'Last successful sync'**
  String get lastSuccessfulSync;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @clearCompletedHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear completed history'**
  String get clearCompletedHistory;

  /// No description provided for @noPendingChanges.
  ///
  /// In en, this message translates to:
  /// **'No pending changes'**
  String get noPendingChanges;

  /// No description provided for @viewConflict.
  ///
  /// In en, this message translates to:
  /// **'View conflict'**
  String get viewConflict;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @resolveConflict.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflict'**
  String get resolveConflict;

  /// No description provided for @priceConflictExample.
  ///
  /// In en, this message translates to:
  /// **'Price changed locally and remotely'**
  String get priceConflictExample;

  /// No description provided for @localValue.
  ///
  /// In en, this message translates to:
  /// **'Local value'**
  String get localValue;

  /// No description provided for @remoteValue.
  ///
  /// In en, this message translates to:
  /// **'Remote value'**
  String get remoteValue;

  /// No description provided for @recommendedAction.
  ///
  /// In en, this message translates to:
  /// **'Recommended action'**
  String get recommendedAction;

  /// No description provided for @keepLatestValue.
  ///
  /// In en, this message translates to:
  /// **'Use the latest timestamp'**
  String get keepLatestValue;

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// No description provided for @applyResolution.
  ///
  /// In en, this message translates to:
  /// **'Apply resolution'**
  String get applyResolution;

  /// No description provided for @privacyCenter.
  ///
  /// In en, this message translates to:
  /// **'Privacy center'**
  String get privacyCenter;

  /// No description provided for @privacyIntro.
  ///
  /// In en, this message translates to:
  /// **'Control how ASKODOX uses local mock data. Production practices require privacy and legal review.'**
  String get privacyIntro;

  /// No description provided for @privacyDataCollected.
  ///
  /// In en, this message translates to:
  /// **'Data collected'**
  String get privacyDataCollected;

  /// No description provided for @privacyDataCollectedBody.
  ///
  /// In en, this message translates to:
  /// **'Profile, consent, saved items and activity needed for features.'**
  String get privacyDataCollectedBody;

  /// No description provided for @privacySharing.
  ///
  /// In en, this message translates to:
  /// **'Data sharing'**
  String get privacySharing;

  /// No description provided for @privacySharingBody.
  ///
  /// In en, this message translates to:
  /// **'Sellers receive only request details and approximate, aggregated demand—not buyer contact details.'**
  String get privacySharingBody;

  /// No description provided for @privacyLocation.
  ///
  /// In en, this message translates to:
  /// **'Location usage'**
  String get privacyLocation;

  /// No description provided for @privacyLocationBody.
  ///
  /// In en, this message translates to:
  /// **'Location finds nearby shops. Clear saved locations or disable history at any time.'**
  String get privacyLocationBody;

  /// No description provided for @privacyAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics usage'**
  String get privacyAnalytics;

  /// No description provided for @privacyAnalyticsBody.
  ///
  /// In en, this message translates to:
  /// **'Optional analytics consent is off until you choose it and can be withdrawn.'**
  String get privacyAnalyticsBody;

  /// No description provided for @privacySellerVisibility.
  ///
  /// In en, this message translates to:
  /// **'Seller visibility'**
  String get privacySellerVisibility;

  /// No description provided for @privacySellerVisibilityBody.
  ///
  /// In en, this message translates to:
  /// **'Sellers never receive your phone, exact home address, saved locations, private history or device identifiers.'**
  String get privacySellerVisibilityBody;

  /// No description provided for @privacyRetention.
  ///
  /// In en, this message translates to:
  /// **'Retention summary'**
  String get privacyRetention;

  /// No description provided for @privacyRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Local mock data can be cleared. Production retention rules still require approval.'**
  String get privacyRetentionBody;

  /// No description provided for @consentHistory.
  ///
  /// In en, this message translates to:
  /// **'Consent history'**
  String get consentHistory;

  /// No description provided for @consentHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No consent changes recorded on this device.'**
  String get consentHistoryEmpty;

  /// No description provided for @requestDataDownload.
  ///
  /// In en, this message translates to:
  /// **'Request data download'**
  String get requestDataDownload;

  /// No description provided for @placeholderOnly.
  ///
  /// In en, this message translates to:
  /// **'Placeholder only—no request leaves this device.'**
  String get placeholderOnly;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @accountDeletionWarning.
  ///
  /// In en, this message translates to:
  /// **'Mock workflow. Some data may be retained for legal or fraud-prevention duties in production.'**
  String get accountDeletionWarning;

  /// No description provided for @priceBenchmarkTitle.
  ///
  /// In en, this message translates to:
  /// **'Local vs online price benchmark'**
  String get priceBenchmarkTitle;

  /// No description provided for @localPriceSummary.
  ///
  /// In en, this message translates to:
  /// **'Local price summary'**
  String get localPriceSummary;

  /// No description provided for @onlinePriceSummary.
  ///
  /// In en, this message translates to:
  /// **'Online price summary'**
  String get onlinePriceSummary;

  /// No description provided for @lowestPrice.
  ///
  /// In en, this message translates to:
  /// **'Lowest'**
  String get lowestPrice;

  /// No description provided for @averagePrice.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get averagePrice;

  /// No description provided for @highestPrice.
  ///
  /// In en, this message translates to:
  /// **'Highest'**
  String get highestPrice;

  /// No description provided for @nearbyShops.
  ///
  /// In en, this message translates to:
  /// **'Nearby shops'**
  String get nearbyShops;

  /// No description provided for @nearestShop.
  ///
  /// In en, this message translates to:
  /// **'Nearest shop'**
  String get nearestShop;

  /// No description provided for @updatedToday.
  ///
  /// In en, this message translates to:
  /// **'Updated today'**
  String get updatedToday;

  /// No description provided for @lowestEffectivePrice.
  ///
  /// In en, this message translates to:
  /// **'Lowest effective price'**
  String get lowestEffectivePrice;

  /// No description provided for @sourcesCompared.
  ///
  /// In en, this message translates to:
  /// **'Sources compared'**
  String get sourcesCompared;

  /// No description provided for @deliveryAndFeesIncluded.
  ///
  /// In en, this message translates to:
  /// **'Mock delivery and platform fees included'**
  String get deliveryAndFeesIncluded;

  /// No description provided for @comparisonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price comparison is temporarily unavailable. Try again.'**
  String get comparisonUnavailable;

  /// No description provided for @insufficientObservations.
  ///
  /// In en, this message translates to:
  /// **'Insufficient observations'**
  String get insufficientObservations;

  /// No description provided for @potentialSavings.
  ///
  /// In en, this message translates to:
  /// **'Potential savings'**
  String get potentialSavings;

  /// No description provided for @potentialSavingsDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Potential savings based on recently available prices.'**
  String get potentialSavingsDisclaimer;

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get confidence;

  /// No description provided for @priceStandard.
  ///
  /// In en, this message translates to:
  /// **'Price standard and fair range'**
  String get priceStandard;

  /// No description provided for @observedAverage.
  ///
  /// In en, this message translates to:
  /// **'Overall observed average'**
  String get observedAverage;

  /// No description provided for @medianPrice.
  ///
  /// In en, this message translates to:
  /// **'Median price'**
  String get medianPrice;

  /// No description provided for @observations.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get observations;

  /// No description provided for @fairPriceRange.
  ///
  /// In en, this message translates to:
  /// **'Fair price range'**
  String get fairPriceRange;

  /// No description provided for @volatility.
  ///
  /// In en, this message translates to:
  /// **'Price volatility'**
  String get volatility;

  /// No description provided for @onlineSources.
  ///
  /// In en, this message translates to:
  /// **'Mock online price sources'**
  String get onlineSources;

  /// No description provided for @onlineSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Online source unavailable'**
  String get onlineSourceUnavailable;

  /// No description provided for @minimumOrder.
  ///
  /// In en, this message translates to:
  /// **'Minimum order'**
  String get minimumOrder;

  /// No description provided for @mockPriceHistory.
  ///
  /// In en, this message translates to:
  /// **'Mock price history'**
  String get mockPriceHistory;

  /// No description provided for @mockHistoryDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Demonstration data only; this is not real price history.'**
  String get mockHistoryDisclosure;

  /// No description provided for @priceComparisonDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Prices, stock and fees may change. ASKODOX helps users compare recently available information but does not guarantee the final selling price. Confirm the price directly with the seller or online provider before purchase.'**
  String get priceComparisonDisclosure;

  /// No description provided for @localCheaperInsight.
  ///
  /// In en, this message translates to:
  /// **'Lowest local price is {amount} lower than the effective online price.'**
  String localCheaperInsight(String amount);

  /// No description provided for @onlineCheaperInsight.
  ///
  /// In en, this message translates to:
  /// **'Online effective price is currently {amount} lower.'**
  String onlineCheaperInsight(String amount);

  /// No description provided for @pricesSimilar.
  ///
  /// In en, this message translates to:
  /// **'Local and online prices are nearly the same.'**
  String get pricesSimilar;

  /// No description provided for @stalePriceWarning.
  ///
  /// In en, this message translates to:
  /// **'Price comparison may be outdated. Confirm the final price before purchase.'**
  String get stalePriceWarning;

  /// No description provided for @noOnlinePrice.
  ///
  /// In en, this message translates to:
  /// **'No online price available'**
  String get noOnlinePrice;

  /// No description provided for @noLocalSeller.
  ///
  /// In en, this message translates to:
  /// **'No local seller available'**
  String get noLocalSeller;

  /// No description provided for @productMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Product match failed. Compare pack sizes carefully.'**
  String get productMatchFailed;

  /// No description provided for @confidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get confidenceMedium;

  /// No description provided for @confidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get confidenceLow;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'or', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'or':
      return AppLocalizationsOr();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
