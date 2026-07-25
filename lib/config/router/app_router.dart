import 'package:go_router/go_router.dart';

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

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
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
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => ProductDetailsScreen(productId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/product-not-found', builder: (context, state) => const ProductNotFoundScreen()),
    GoRoute(path: '/notification-preferences', builder: (context, state) => const NotificationPreferencesScreen()),
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
      ],
    ),
  ],
);
