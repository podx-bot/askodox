import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/catalog/presentation/product_details_screen.dart';
import '../../features/catalog/presentation/product_not_found_screen.dart';
import '../../features/catalog/presentation/search_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/placeholder_screen.dart';

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
            builder: (context, state) => const PlaceholderScreen(
              title: 'Watchlist',
              icon: 'favorite',
            ),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/profile',
            builder: (context, state) => const PlaceholderScreen(
              title: 'Profile',
              icon: 'person',
            ),
          ),
        ]),
      ],
    ),
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => ProductDetailsScreen(productId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/product-not-found', builder: (context, state) => const ProductNotFoundScreen()),
  ],
);
