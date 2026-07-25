import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
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
            builder: (context, state) => const PlaceholderScreen(
              title: 'Search',
              icon: 'search',
            ),
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
  ],
);
