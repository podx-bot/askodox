import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/route_guard.dart';
import '../../core/providers/backend_providers.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/catalog/presentation/product_details_screen.dart';
import '../../features/catalog/presentation/product_not_found_screen.dart';
import '../../features/catalog/presentation/search_screen.dart';
import '../../features/search/domain/search_models.dart';
import '../../features/search/presentation/product_discovery_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/seller/presentation/add_seller_product_screen.dart';
import '../../features/seller/presentation/request_new_product_screen.dart';
import '../../features/seller/presentation/seller_dashboard_screen.dart';
import '../../features/seller/presentation/seller_login_screen.dart';
import '../../features/seller/presentation/seller_insights_screen.dart';
import '../../features/seller/presentation/seller_profile_screen.dart';
import '../../features/seller/presentation/seller_products_screen.dart';
import '../../features/seller/presentation/seller_registration_screen.dart';
import '../../features/seller/presentation/seller_requests_screen.dart';
import '../../features/seller/presentation/seller_shell.dart';
import '../../shared/widgets/app_shell.dart';
import '../../features/watchlist/presentation/alerts_screen.dart';
import '../../features/watchlist/presentation/alert_simulator_screen.dart';
import '../../features/watchlist/presentation/preferences_screen.dart';
import '../../features/watchlist/presentation/watchlist_screen.dart';
import '../../features/admin/application/admin_controller.dart';
import '../../features/admin/presentation/admin_screens.dart';
import '../../features/admin/presentation/localized_admin_entry.dart';
import '../../features/location/presentation/location_setup_screen.dart';
import '../../features/location/presentation/nearby_shops_screen.dart';
import '../../features/location/presentation/shop_details_screen.dart';
import '../../features/location/presentation/seller_location_screen.dart';
import '../../features/auth/presentation/auth_status_screens.dart';
import '../../features/developer/presentation/developer_settings_screen.dart';
import '../../features/developer/presentation/sync_status_screen.dart';
import '../../features/developer/presentation/storage_usage_screen.dart';
import '../../features/developer/presentation/performance_monitor_screen.dart';
import '../../features/monetization/presentation/monetization_screens.dart';
import '../../features/monetization/presentation/admin_monetization_screen.dart';
import '../../features/communication/domain/communication_models.dart';
import '../../features/communication/presentation/communication_screens.dart';
import '../../features/communication/presentation/localized_communication_screens.dart';
import '../../features/deals/presentation/deal_screens.dart';
import '../../features/analytics/presentation/analytics_screens.dart';
import '../../features/privacy/presentation/privacy_center_screen.dart';
import '../../features/feedback/presentation/beta_feedback_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  return GoRouter(
  errorBuilder: (context, state) => AuthMessageScreen(title: 'Page not found', message: 'This link is unavailable or no longer exists. (${state.uri.path})'),
  redirect: (context, state) => const RouteGuard().redirect(session, state.matchedLocation),
  initialLocation: '/',
  routes: [
    GoRoute(path: '/auth/login', builder: (context, state) => const AuthMessageScreen(title: 'Sign in required', message: 'Choose a demo role in Developer settings to continue.')),
    GoRoute(path: '/auth/session-expired', builder: (context, state) => const AuthMessageScreen(title: 'Session expired', message: 'Your session expired. Sign in again to continue.')),
    GoRoute(path: '/account-status', builder: (context, state) => const AuthMessageScreen(title: 'Account suspended', message: 'This account is suspended. Contact support for help.')),
    GoRoute(path: '/forbidden', builder: (context, state) => const AuthMessageScreen(title: 'Access denied', message: 'Your current role cannot access this area.')),
    if (kDebugMode) ...[
      GoRoute(path: '/developer', builder: (context, state) => const DeveloperSettingsScreen()),
      GoRoute(path: '/sync-status', builder: (context, state) => const SyncStatusScreen()),
      GoRoute(path: '/conflict/:id', builder: (context, state) => ConflictResolutionScreen(itemId: state.pathParameters['id']!)),
      GoRoute(path: '/storage-usage', builder: (context, state) => const StorageUsageScreen()),
      GoRoute(path: '/performance-monitor', builder: (context, state) => const PerformanceMonitorScreen()),
    ],
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/search', builder: (context, state) => const SearchScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/watchlist', builder: (context, state) => const WatchlistScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen())]),
      ],
    ),
    GoRoute(path: '/location', builder: (context, state) => const LocationSetupScreen()),
    GoRoute(path: '/nearby', builder: (context, state) => const NearbyShopsScreen()),
    GoRoute(path: '/shop/:id', builder: (context, state) => ShopDetailsScreen(shopId: state.pathParameters['id']!)),
    GoRoute(path: '/map/shop/:id', redirect: (context, state) => '/nearby'),
    GoRoute(path: '/nearby/product/:id', redirect: (context, state) => '/nearby'),
    GoRoute(path: '/alert/:id/map', redirect: (context, state) => '/nearby'),
    GoRoute(path: '/product/:id', builder: (context, state) => ProductDetailsScreen(productId: state.pathParameters['id']!)),
    GoRoute(path: '/product-not-found', builder: (context, state) => const ProductNotFoundScreen()),
    GoRoute(path: '/discover/barcode', builder: (context, state) => const ProductDiscoveryScreen(mode: SearchIntentType.barcode)),
    GoRoute(path: '/discover/ocr', builder: (context, state) => const ProductDiscoveryScreen(mode: SearchIntentType.ocr)),
    GoRoute(path: '/discover/image', builder: (context, state) => const ProductDiscoveryScreen(mode: SearchIntentType.image)),
    GoRoute(path: '/discover/voice', builder: (context, state) => const ProductDiscoveryScreen(mode: SearchIntentType.voice)),
    GoRoute(path: '/notification-preferences', builder: (context, state) => const NotificationPreferencesScreen()),
    GoRoute(path: '/communications', builder: (context, state) => const LocalizedCommunicationHubScreen()),
    GoRoute(path: '/communications/notifications', builder: (context, state) => const LocalizedNotificationCenterScreen()),
    GoRoute(path: '/communications/requests', builder: (context, state) => const LocalizedBuyerRequestsScreen()),
    GoRoute(path: '/communications/following', builder: (context, state) => const LocalizedFollowedShopsScreen()),
    GoRoute(path: '/communications/preferences', builder: (context, state) => const LocalizedCommunicationPreferencesScreen()),
    GoRoute(path: '/deals', builder: (context, state) => const DealInboxScreen()),
    GoRoute(path: '/deal/:requestId', builder: (context, state) => DealThreadScreen(requestId: int.tryParse(state.pathParameters['requestId'] ?? '') ?? 0, userId: state.uri.queryParameters['user'] ?? '', otherUserId: state.uri.queryParameters['other'] ?? '')),
    GoRoute(path: '/alert-simulator', builder: (context, state) => const AlertSimulatorScreen()),
    GoRoute(path: '/analytics/buyer', builder: (context, state) => const BuyerInsightsScreen()),
    GoRoute(path: '/analytics/privacy', builder: (context, state) => const AnalyticsPrivacyScreen()),
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyCenterScreen()),
    GoRoute(path: '/beta-feedback', builder: (context, state) => const BetaFeedbackScreen()),
    if (kDebugMode) GoRoute(path: '/developer/feedback', builder: (context, state) => const SubmittedFeedbackScreen()),
    GoRoute(path: '/seller/login', builder: (context, state) => const SellerLoginScreen()),
    GoRoute(path: '/seller/register', builder: (context, state) => const SellerRegistrationScreen()),
    ShellRoute(
      builder: (context, state, child) => SellerShell(child: child),
      routes: [
        GoRoute(path: '/seller/dashboard', builder: (context, state) => const SellerDashboardScreen()),
        GoRoute(path: '/seller/products', builder: (context, state) => const SellerProductsScreen(), routes: [
          GoRoute(path: 'add', builder: (context, state) => const AddSellerProductScreen()),
          GoRoute(path: 'request', builder: (context, state) => const RequestNewProductScreen()),
        ]),
        GoRoute(path: '/seller/requests', builder: (context, state) => const SellerRequestsScreen()),
        GoRoute(path: '/seller/insights', builder: (context, state) => const SellerInsightsScreen()),
        GoRoute(path: '/seller/profile', builder: (context, state) => const SellerProfileScreen()),
        GoRoute(path: '/seller/location', builder: (context, state) => const SellerLocationScreen()),
        GoRoute(path: '/seller/usage', builder: (context, state) => const UsageScreen()),
        GoRoute(path: '/seller/plans', builder: (context, state) => const PricingScreen(), routes: [
          GoRoute(path: 'compare', builder: (context, state) => const PlanComparisonScreen()),
          GoRoute(path: 'review', builder: (context, state) => const OrderReviewScreen()),
          GoRoute(path: 'payment', builder: (context, state) => const PaymentScreen()),
        ]),
        GoRoute(path: '/seller/subscription', builder: (context, state) => const SubscriptionScreen()),
        GoRoute(path: '/seller/invoices', builder: (context, state) => const InvoiceHistoryScreen()),
        GoRoute(path: '/seller/engagement', builder: (context, state) => const SellerEngagementScreen()),
        GoRoute(path: '/seller/analytics', builder: (context, state) => const SellerAnalyticsScreen()),
        GoRoute(path: '/seller/analytics/products', builder: (context, state) => const ProductPerformanceScreen()),
        GoRoute(path: '/seller/analytics/market', builder: (context, state) => const SellerMarketAnalyticsScreen()),
        GoRoute(path: '/seller/analytics/privacy', builder: (context, state) => const AnalyticsPrivacyScreen(seller:true)),
        GoRoute(path: '/seller/notifications', builder: (context, state) => const NotificationCenterScreen(audience: Audience.seller)),
      ],
    ),
    GoRoute(path: '/admin/subscriptions', builder: (context, state) => const AdminMonetizationScreen()),
    GoRoute(path: '/admin/login', builder: (context, state) => const LocalizedAdminLoginScreen()),
    GoRoute(path: '/admin/announcements', builder: (context, state) => const AnnouncementScreen()),
    GoRoute(path: '/admin/analytics', builder: (context, state) => const AdminBusinessIntelligenceScreen()),
    GoRoute(path: '/admin/reports', builder: (context, state) => const ReportBuilderScreen()),
    ShellRoute(
      builder: (context, state, child) => LocalizedAdminShell(child: child),
      routes: [
        for (final section in AdminSection.values)
          GoRoute(path: '/admin/${section.name}', builder: (context, state) => AdminSectionScreen(section: section)),
      ],
    ),
  ],
);
});
