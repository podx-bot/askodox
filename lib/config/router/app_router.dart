import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/route_guard.dart';
import '../../core/providers/backend_providers.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/catalog/presentation/product_details_screen.dart';
import '../../features/catalog/presentation/product_not_found_screen.dart';
import '../../features/catalog/presentation/search_screen.dart';
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
import '../../features/location/presentation/location_setup_screen.dart';
import '../../features/location/presentation/nearby_shops_screen.dart';
import '../../features/location/presentation/shop_details_screen.dart';
import '../../features/location/presentation/seller_location_screen.dart';
import '../../features/auth/presentation/auth_status_screens.dart';
import '../../features/developer/presentation/developer_settings_screen.dart';
import '../../features/developer/presentation/sync_status_screen.dart';
import '../../features/monetization/presentation/monetization_screens.dart';
import '../../features/monetization/presentation/admin_monetization_screen.dart';
import '../../features/communication/domain/communication_models.dart';
import '../../features/communication/presentation/communication_screens.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  return GoRouter(
  redirect: (context, state) => const RouteGuard().redirect(session, state.matchedLocation),
  initialLocation: '/',
  routes: [
    GoRoute(path: '/auth/login', builder: (context, state) => const AuthMessageScreen(title: 'Sign in required', message: 'Choose a demo role in Developer settings to continue.')),
    GoRoute(path: '/auth/session-expired', builder: (context, state) => const AuthMessageScreen(title: 'Session expired', message: 'Your session expired. Sign in again to continue.')),
    GoRoute(path: '/account-status', builder: (context, state) => const AuthMessageScreen(title: 'Account suspended', message: 'This account is suspended. Contact support for help.')),
    GoRoute(path: '/forbidden', builder: (context, state) => const AuthMessageScreen(title: 'Access denied', message: 'Your current role cannot access this area.')),
    GoRoute(path: '/developer', builder: (context, state) => const DeveloperSettingsScreen()),
    GoRoute(path: '/sync-status', builder: (context, state) => const SyncStatusScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/watchlist',
            builder: (context, state) => const WatchlistScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/alerts',
            builder: (context, state) => const AlertsScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ]),
      ],
    ),
    GoRoute(path: '/location', builder: (context, state) => const LocationSetupScreen()),
    GoRoute(path: '/nearby', builder: (context, state) => const NearbyShopsScreen()),
    GoRoute(path: '/shop/:id', builder: (context, state) => ShopDetailsScreen(shopId: state.pathParameters['id']!)),
    GoRoute(path: '/map/shop/:id', redirect: (context, state) => '/nearby'),
    GoRoute(path: '/nearby/product/:id', redirect: (context, state) => '/nearby'),
    GoRoute(path: '/alert/:id/map', redirect: (context, state) => '/nearby'),
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => ProductDetailsScreen(productId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/product-not-found', builder: (context, state) => const ProductNotFoundScreen()),
    GoRoute(path: '/notification-preferences', builder: (context, state) => const NotificationPreferencesScreen()),
    GoRoute(path: '/communications', builder: (context, state) => const CommunicationHubScreen()),
    GoRoute(path: '/communications/notifications', builder: (context, state) => const NotificationCenterScreen()),
    GoRoute(path: '/communications/requests', builder: (context, state) => const BuyerRequestsScreen()),
    GoRoute(path: '/communications/following', builder: (context, state) => const FollowedShopsScreen()),
    GoRoute(path: '/communications/preferences', builder: (context, state) => const CommunicationPreferencesScreen()),
    GoRoute(path: '/alert-simulator', builder: (context, state) => const AlertSimulatorScreen()),
    GoRoute(path: '/seller/login', builder: (context, state) => const SellerLoginScreen()),
    GoRoute(path: '/seller/register', builder: (context, state) => const SellerRegistrationScreen()),
    ShellRoute(
      builder: (context, state, child) => SellerShell(child: child),
      routes: [
        GoRoute(path: '/seller/dashboard', builder: (context, state) => const SellerDashboardScreen()),
        GoRoute(
          path: '/seller/products',
          builder: (context, state) => const SellerProductsScreen(),
          routes: [
            GoRoute(path: 'add', builder: (context, state) => const AddSellerProductScreen()),
            GoRoute(path: 'request', builder: (context, state) => const RequestNewProductScreen()),
          ],
        ),
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
        GoRoute(path: '/seller/notifications', builder: (context, state) => const NotificationCenterScreen(audience: Audience.seller)),
      ],
    ),
    GoRoute(path: '/admin/subscriptions', builder: (context, state) => const AdminMonetizationScreen()),
    GoRoute(path: '/admin/login', builder: (context, state) => const AdminLoginScreen()),
    GoRoute(path: '/admin/announcements', builder: (context, state) => const AnnouncementScreen()),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        for (final section in AdminSection.values)
          GoRoute(path: '/admin/${section.name}', builder: (context, state) => AdminSectionScreen(section: section)),
      ],
    ),
  ],
);
});
