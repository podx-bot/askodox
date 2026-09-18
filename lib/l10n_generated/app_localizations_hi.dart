// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'ASKODOX';

  @override
  String get greeting => 'Good morning';

  @override
  String get discover => 'Discover near you';

  @override
  String get searchHint => 'Search products, shops and sellers';

  @override
  String get categories => 'Categories';

  @override
  String get seeAll => 'See all';

  @override
  String get featured => 'Featured near you';

  @override
  String get home => 'Home';

  @override
  String get search => 'Search';

  @override
  String get watchlist => 'Watchlist';

  @override
  String get profile => 'Profile';

  @override
  String get notifications => 'Notifications';

  @override
  String get retry => 'Retry';

  @override
  String get sellerDashboard => 'Seller dashboard';

  @override
  String get sellerProducts => 'Products';

  @override
  String get sellerRequests => 'Requests';

  @override
  String get sellerInsights => 'Insights';

  @override
  String get sellerProfile => 'Seller profile';

  @override
  String get inStock => 'In stock';

  @override
  String get lowStock => 'Low stock';

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get verificationPending => 'Verification pending';

  @override
  String get adminDashboard => 'Admin dashboard';

  @override
  String get sellerVerification => 'Seller verification';

  @override
  String get productRequests => 'Product requests';

  @override
  String get moderation => 'Moderation';

  @override
  String get support => 'Support';

  @override
  String get auditLog => 'Audit log';

  @override
  String get billing => 'Billing';

  @override
  String get sellerPlans => 'Seller plans';

  @override
  String get comparePlans => 'Compare plans';

  @override
  String get demoPricing => 'Demo pricing only';

  @override
  String get noRealBilling =>
      'Mock and local data only. No real billing or buyer charges.';

  @override
  String get monthly => 'Monthly';

  @override
  String get annual => 'Annual';

  @override
  String get currentPlan => 'Current plan';

  @override
  String get month => 'month';

  @override
  String get year => 'year';

  @override
  String saveAmount(String amount) {
    return 'Save $amount';
  }

  @override
  String productLimit(int count) {
    return '$count active product listings';
  }

  @override
  String get shopVisibility => 'Shop visibility';

  @override
  String get upgradePlan => 'Upgrade plan';

  @override
  String get downgrade => 'Downgrade';

  @override
  String get reactivate => 'Reactivate';

  @override
  String get cancelPlan => 'Cancel plan';

  @override
  String startFreeTrial(int days) {
    return 'Start $days-day free trial';
  }

  @override
  String get feature => 'Feature';

  @override
  String get productListings => 'Product listing limit';

  @override
  String get buyerRequestAccess => 'Buyer request access';

  @override
  String get demandAnalytics => 'Demand analytics';

  @override
  String get days => 'days';

  @override
  String get priceAlerts => 'Price alerts';

  @override
  String get basic => 'Basic';

  @override
  String get included => 'Included';

  @override
  String get promotionalOffers => 'Promotional offers';

  @override
  String get featuredPlacement => 'Featured placement';

  @override
  String get supportLevel => 'Support level';

  @override
  String get multiShop => 'Multi-shop access placeholder';

  @override
  String get sellerUsage => 'Seller usage';

  @override
  String get activeListings => 'Active product listings used';

  @override
  String get offers => 'Offers used';

  @override
  String get requestResponses => 'Buyer request responses used';

  @override
  String get shopCount => 'Shop count';

  @override
  String get analyticsAccess => 'Analytics access level';

  @override
  String historyDays(int days) {
    return '$days-day history';
  }

  @override
  String get storageUsage => 'Storage usage';

  @override
  String get placeholder => 'Placeholder only';

  @override
  String get limitReached => 'Plan limit reached';

  @override
  String limitExplanation(int used, int limit) {
    return 'You are using $used of $limit. Upgrade to continue without silently blocking your work.';
  }

  @override
  String get currentSubscription => 'Current subscription';

  @override
  String get billingCycle => 'Billing cycle';

  @override
  String get subscriptionStatus => 'Subscription status';

  @override
  String get startDate => 'Start date';

  @override
  String get renewalDate => 'Renewal date';

  @override
  String get trialStatus => 'Trial status';

  @override
  String get autoRenew => 'Auto-renew status';

  @override
  String get paymentMethod => 'Payment method placeholder';

  @override
  String get downgradeScheduled => 'Downgrade scheduled';

  @override
  String get nextRenewal => 'Effective at next renewal';

  @override
  String get invoiceHistory => 'Invoice history';

  @override
  String get restorePurchase => 'Restore purchase placeholder';

  @override
  String get planUnavailable => 'Plan unavailable';

  @override
  String get reviewOrder => 'Review demo order';

  @override
  String get promoCode => 'Promo code';

  @override
  String get promoApplied => 'Demo promo applied';

  @override
  String get promoInvalid =>
      'Promo code invalid, expired, or usage limit reached';

  @override
  String get continueToDemoPayment => 'Continue to demo payment';

  @override
  String get demoPayment => 'Demo payment';

  @override
  String get demoPaymentOnly => 'Demo payment only';

  @override
  String get noPaymentDetails =>
      'Do not enter real card, UPI, wallet, or bank details.';

  @override
  String get upi => 'UPI placeholder';

  @override
  String get card => 'Credit or debit card placeholder';

  @override
  String get netBanking => 'Net banking placeholder';

  @override
  String get wallet => 'Wallet placeholder';

  @override
  String get confirmDemoPayment => 'Confirm mock payment';

  @override
  String get simulateFailure => 'Simulate payment failure';

  @override
  String get paymentSuccessful => 'Mock payment successful';

  @override
  String get entitlementsRefreshed =>
      'Subscription activated and entitlements refreshed. Production confirmation must happen on the backend.';

  @override
  String get done => 'Done';

  @override
  String get paymentFailed => 'Payment failed';

  @override
  String get paymentFailureHelp =>
      'Retry, change the demo method, contact support, or continue on the free plan.';

  @override
  String get retryPayment => 'Retry payment';

  @override
  String get continueFree => 'Continue on free plan';

  @override
  String get noInvoices => 'No invoices';

  @override
  String get gstPlaceholder => 'GST fields are placeholders';

  @override
  String get notTaxCompliant =>
      'Demo invoice only. GST calculations are not tax compliant.';

  @override
  String get taxPlaceholder => 'Tax placeholder';

  @override
  String get downloadPlaceholder => 'Download invoice placeholder';

  @override
  String get subscriptionManagement => 'Subscription management';

  @override
  String get mrr => 'Monthly recurring revenue';

  @override
  String get arr => 'Annual recurring revenue';

  @override
  String get activePaidSellers => 'Active paid sellers';

  @override
  String get trialSellers => 'Trial sellers';

  @override
  String get conversionRate => 'Conversion rate';

  @override
  String get failedPayments => 'Failed payments';

  @override
  String get cancelledSubscriptions => 'Cancelled subscriptions';

  @override
  String get demoRevenueData => 'Demo revenue data';

  @override
  String get revenueByPlan => 'Revenue by plan';

  @override
  String get revenueTrend => 'Revenue trend (mock)';

  @override
  String get filterStatus => 'Filter by subscription status';

  @override
  String get allStatuses => 'All statuses';

  @override
  String get paymentStatus => 'Payment status';

  @override
  String get noPaymentAttempt => 'No payment attempt';

  @override
  String get changePlan => 'Change plan';

  @override
  String get grantTrial => 'Grant trial';

  @override
  String get extendTrial => 'Extend trial';

  @override
  String get manualDiscount => 'Apply manual discount';

  @override
  String get markPaymentReceived => 'Mark payment received placeholder';

  @override
  String get mockRefund => 'Mock refund action';

  @override
  String get paymentFailures => 'Payment failures';

  @override
  String get noPaymentFailures => 'No payment failures';

  @override
  String get trialUnavailable => 'Trial is unavailable';

  @override
  String get demoActionRecorded => 'Demo admin action recorded';

  @override
  String get adminReasonRequired => 'Admin reason required';

  @override
  String get adminReason => 'Internal reason';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get communicationCenter => 'Communication center';

  @override
  String get productRequestsNew => 'Product requests';

  @override
  String get followedShops => 'Followed shops';

  @override
  String get notificationPreferencesNew => 'Notification preferences';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get archive => 'Archive';

  @override
  String get delete => 'Delete';

  @override
  String get requestProduct => 'Request product';

  @override
  String get customerEngagement => 'Customer engagement';

  @override
  String get campaigns => 'Campaigns';

  @override
  String get followers => 'Followers';

  @override
  String get announcements => 'Announcements';

  @override
  String get smartSearch => 'Smart search';

  @override
  String get barcodeSearch => 'Barcode search';

  @override
  String get ocrProductMatching => 'OCR product matching';

  @override
  String get imageSearch => 'Image search';

  @override
  String get voiceSearch => 'Voice search';

  @override
  String get mockDataOnly => 'Demo only • local data • no external APIs';

  @override
  String get analyticsToday => 'Today';

  @override
  String get analytics7Days => 'Last 7 days';

  @override
  String get analytics30Days => 'Last 30 days';

  @override
  String get analytics90Days => 'Last 90 days';

  @override
  String get analyticsCustom => 'Custom range';

  @override
  String get buyerInsights => 'Buyer insights';

  @override
  String get sellerAnalytics => 'Seller analytics';

  @override
  String get privacySafeDemo =>
      'Privacy-safe local demo data. Your individual activity is never shown to sellers.';

  @override
  String get activitySummary =>
      'Activity peaked this week; summaries remain understandable without the chart.';

  @override
  String get aggregatedDemoData =>
      'Aggregated demo data only · no individual buyer information';

  @override
  String get engagementTrendSummary =>
      'Engagement is increasing compared with the previous period.';

  @override
  String get productPerformance => 'Product performance';

  @override
  String get sortBy => 'Sort by';

  @override
  String get noProductPerformance => 'No product performance data';

  @override
  String get marketAnalytics => 'Market analytics';

  @override
  String get priceCompetitiveness => 'Price competitiveness';

  @override
  String get areaAnalytics => 'Area analytics';

  @override
  String get campaignAnalytics => 'Campaign analytics';

  @override
  String get businessIntelligence => 'Analytics and business intelligence';

  @override
  String get overview => 'Overview';

  @override
  String get funnels => 'Funnels';

  @override
  String get retention => 'Retention';

  @override
  String get searchIntelligence => 'Search intelligence';

  @override
  String get dataQuality => 'Data quality';

  @override
  String get reportBuilder => 'Report builder';

  @override
  String get analyticsPrivacy => 'Analytics privacy';

  @override
  String get analyticsPrivacyExplanation =>
      'Analytics stays on this device, uses aggregated demo data, and never records phone numbers, addresses, OTPs, tokens, documents, identities, or exact locations.';

  @override
  String get basicUsageAnalytics => 'Allow basic usage analytics';

  @override
  String get basicUsageExplanation =>
      'Records privacy-safe event categories to improve the demo experience.';

  @override
  String get recommendationAnalytics =>
      'Allow product recommendation analytics';

  @override
  String get businessPerformanceAnalytics =>
      'Allow business performance analytics';

  @override
  String get marketComparisonAnalytics => 'Allow aggregated market comparisons';

  @override
  String get collectedCategories => 'View collected event categories';

  @override
  String get clearLocalAnalytics => 'Clear local analytics history';

  @override
  String get localAnalyticsCleared => 'Local analytics history cleared.';

  @override
  String get offlineCopy => 'Offline copy';

  @override
  String get connectionLimited => 'Connection is limited';

  @override
  String get syncStatus => 'Sync status';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get cachedProducts => 'Cached products';

  @override
  String get cachedShopData => 'Cached shop data';

  @override
  String get searchHistorySize => 'Search history size';

  @override
  String get imageCacheSize => 'Image cache size';

  @override
  String get analyticsCacheSize => 'Analytics cache size';

  @override
  String get pendingSyncSize => 'Pending sync size';

  @override
  String get totalLocalStorage => 'Total local storage used';

  @override
  String get clearSearchHistory => 'Clear search history';

  @override
  String get clearStaleData => 'Clear stale data';

  @override
  String get clearAnalyticsCache => 'Clear analytics cache';

  @override
  String get clearAllLocalData => 'Clear all local data';

  @override
  String get clearLocalDataConfirmation =>
      'Clear caches and queued changes? Authentication and preferences are kept.';

  @override
  String get clear => 'Clear';

  @override
  String get developerToolsUnavailable =>
      'Developer tools are unavailable in production.';

  @override
  String get performanceMonitor => 'Performance monitor';

  @override
  String get cacheHits => 'Cache hits';

  @override
  String get cacheMisses => 'Cache misses';

  @override
  String get memoryUsagePlaceholder => 'Memory usage placeholder';

  @override
  String get pendingChanges => 'Pending changes';

  @override
  String get failedChanges => 'Failed changes';

  @override
  String get connectionState => 'Connection state';

  @override
  String get lastSuccessfulSync => 'Last successful sync';

  @override
  String get never => 'Never';

  @override
  String get syncNow => 'Sync now';

  @override
  String get clearCompletedHistory => 'Clear completed history';

  @override
  String get noPendingChanges => 'No pending changes';

  @override
  String get viewConflict => 'View conflict';

  @override
  String get remove => 'Remove';

  @override
  String get resolveConflict => 'Resolve conflict';

  @override
  String get priceConflictExample => 'Price changed locally and remotely';

  @override
  String get localValue => 'Local value';

  @override
  String get remoteValue => 'Remote value';

  @override
  String get recommendedAction => 'Recommended action';

  @override
  String get keepLatestValue => 'Use the latest timestamp';

  @override
  String get resolution => 'Resolution';

  @override
  String get applyResolution => 'Apply resolution';

  @override
  String get privacyCenter => 'Privacy center';

  @override
  String get privacyIntro =>
      'Control how ASKODOX uses local mock data. Production practices require privacy and legal review.';

  @override
  String get privacyDataCollected => 'Data collected';

  @override
  String get privacyDataCollectedBody =>
      'Profile, consent, saved items and activity needed for features.';

  @override
  String get privacySharing => 'Data sharing';

  @override
  String get privacySharingBody =>
      'Sellers receive only request details and approximate, aggregated demand—not buyer contact details.';

  @override
  String get privacyLocation => 'Location usage';

  @override
  String get privacyLocationBody =>
      'Location finds nearby shops. Clear saved locations or disable history at any time.';

  @override
  String get privacyAnalytics => 'Analytics usage';

  @override
  String get privacyAnalyticsBody =>
      'Optional analytics consent is off until you choose it and can be withdrawn.';

  @override
  String get privacySellerVisibility => 'Seller visibility';

  @override
  String get privacySellerVisibilityBody =>
      'Sellers never receive your phone, exact home address, saved locations, private history or device identifiers.';

  @override
  String get privacyRetention => 'Retention summary';

  @override
  String get privacyRetentionBody =>
      'Local mock data can be cleared. Production retention rules still require approval.';

  @override
  String get consentHistory => 'Consent history';

  @override
  String get consentHistoryEmpty =>
      'No consent changes recorded on this device.';

  @override
  String get requestDataDownload => 'Request data download';

  @override
  String get placeholderOnly =>
      'Placeholder only—no request leaves this device.';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get accountDeletionWarning =>
      'Mock workflow. Some data may be retained for legal or fraud-prevention duties in production.';

  @override
  String get priceBenchmarkTitle => 'Local vs online price benchmark';

  @override
  String get localPriceSummary => 'Local price summary';

  @override
  String get onlinePriceSummary => 'Online price summary';

  @override
  String get lowestPrice => 'Lowest';

  @override
  String get averagePrice => 'Average';

  @override
  String get highestPrice => 'Highest';

  @override
  String get nearbyShops => 'Nearby shops';

  @override
  String get nearestShop => 'Nearest shop';

  @override
  String get updatedToday => 'Updated today';

  @override
  String get lowestEffectivePrice => 'Lowest effective price';

  @override
  String get sourcesCompared => 'Sources compared';

  @override
  String get deliveryAndFeesIncluded =>
      'Mock delivery and platform fees included';

  @override
  String get comparisonUnavailable =>
      'Price comparison is temporarily unavailable. Try again.';

  @override
  String get insufficientObservations => 'Insufficient observations';

  @override
  String get potentialSavings => 'Potential savings';

  @override
  String get potentialSavingsDisclaimer =>
      'Potential savings based on recently available prices.';

  @override
  String get confidence => 'Confidence';

  @override
  String get priceStandard => 'Price standard and fair range';

  @override
  String get observedAverage => 'Overall observed average';

  @override
  String get medianPrice => 'Median price';

  @override
  String get observations => 'Observations';

  @override
  String get fairPriceRange => 'Fair price range';

  @override
  String get volatility => 'Price volatility';

  @override
  String get onlineSources => 'Mock online price sources';

  @override
  String get onlineSourceUnavailable => 'Online source unavailable';

  @override
  String get minimumOrder => 'Minimum order';

  @override
  String get mockPriceHistory => 'Mock price history';

  @override
  String get mockHistoryDisclosure =>
      'Demonstration data only; this is not real price history.';

  @override
  String get priceComparisonDisclosure =>
      'Prices, stock and fees may change. ASKODOX helps users compare recently available information but does not guarantee the final selling price. Confirm the price directly with the seller or online provider before purchase.';

  @override
  String localCheaperInsight(String amount) {
    return 'Lowest local price is $amount lower than the effective online price.';
  }

  @override
  String onlineCheaperInsight(String amount) {
    return 'Online effective price is currently $amount lower.';
  }

  @override
  String get pricesSimilar => 'Local and online prices are nearly the same.';

  @override
  String get stalePriceWarning =>
      'Price comparison may be outdated. Confirm the final price before purchase.';

  @override
  String get noOnlinePrice => 'No online price available';

  @override
  String get noLocalSeller => 'No local seller available';

  @override
  String get productMatchFailed =>
      'Product match failed. Compare pack sizes carefully.';

  @override
  String get confidenceHigh => 'High';

  @override
  String get confidenceMedium => 'Medium';

  @override
  String get confidenceLow => 'Low';
}
