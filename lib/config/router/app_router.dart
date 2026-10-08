import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/route_guard.dart';
import '../../core/providers/backend_providers.dart';
import '../../features/home/presentation/chat_first_home_host.dart';
import '../../features/catalog/presentation/product_details_screen.dart';
import '../../features/catalog/presentation/product_not_found_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../features/selling/presentation/my_listings_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/notifications/presentation/updates_screen.dart';
import '../../features/business/presentation/business_center_screen.dart';
import '../../features/profile/presentation/profile_memory_screen.dart';
import '../../features/profile/presentation/my_roles_screen.dart';
import '../../features/business/presentation/business_promotions_screen.dart';
import '../../features/business/presentation/business_automation_screen.dart';
import '../../features/opportunities/presentation/seller_opportunities_screen.dart';
import '../../features/watchlist/presentation/alert_simulator_screen.dart';
import '../../features/watchlist/presentation/watchlist_screen.dart';
import '../../features/admin/application/admin_controller.dart';
import '../../features/admin/command_center/command_center_screen.dart';
import '../../features/admin/presentation/admin_screens.dart';
import '../../features/admin/presentation/localized_admin_entry.dart';
import '../../features/admin/presentation/localized_admin_sections.dart';
import '../../features/location/presentation/location_setup_screen.dart';
import '../../features/auth/presentation/auth_status_screens.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/developer/presentation/developer_settings_screen.dart';
import '../../features/developer/presentation/sync_status_screen.dart';
import '../../features/developer/presentation/storage_usage_screen.dart';
import '../../features/developer/presentation/performance_monitor_screen.dart';
import '../../features/monetization/presentation/admin_monetization_screen.dart';
import '../../features/deals/presentation/deal_screens.dart';
import '../../features/orders/presentation/order_screens.dart';
import '../../features/analytics/presentation/analytics_screens.dart';
import '../../features/privacy/presentation/privacy_center_screen.dart';
import '../../features/feedback/presentation/beta_feedback_screen.dart';
import '../../features/mobility/presentation/mobility_screen.dart';
import '../../features/native_video/native_video.dart';
import '../../features/companion/companion_performance_panel.dart';
import '../../features/companion/companion_vrm_engine.dart';
import '../../features/companion/screen_guide.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  return GoRouter(
    errorBuilder: (context, state) => AuthMessageScreen(
        title: 'Page not found',
        message:
            'This link is unavailable or no longer exists. (${state.uri.path})'),
    redirect: (context, state) {
      // The old mock seller area (mock OTP, mock plans/payments, demo
      // analytics) is gone: sellers manage their REAL listings in one place.
      final path = state.uri.path;
      if (path == '/seller' || path.startsWith('/seller/')) return '/listings/mine';
      return const RouteGuard().redirect(session, state.matchedLocation);
    },
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
          path: '/onboarding',
          builder: (context, state) =>
              OnboardingScreen(signIn: state.uri.queryParameters['signin'] == '1')),
      // Real sign-in is phone + OTP (never a developer/demo role screen).
      GoRoute(path: '/auth/login', redirect: (context, state) => '/onboarding?signin=1'),
      GoRoute(
          path: '/auth/session-expired',
          builder: (context, state) => const AuthMessageScreen(
              title: 'Session expired',
              message: 'Your session expired. Sign in again to continue.')),
      GoRoute(
          path: '/account-status',
          builder: (context, state) => const AuthMessageScreen(
              title: 'Account suspended',
              message: 'This account is suspended. Contact support for help.')),
      GoRoute(
          path: '/forbidden',
          builder: (context, state) => const AuthMessageScreen(
              title: 'Access denied',
              message: 'Your current role cannot access this area.')),
      if (kDebugMode) ...[
        GoRoute(
            path: '/developer',
            builder: (context, state) => const DeveloperSettingsScreen()),
        GoRoute(
            path: '/sync-status',
            builder: (context, state) => const SyncStatusScreen()),
        GoRoute(
            path: '/conflict/:id',
            builder: (context, state) =>
                ConflictResolutionScreen(itemId: state.pathParameters['id']!)),
        GoRoute(
            path: '/storage-usage',
            builder: (context, state) => const StorageUsageScreen()),
        GoRoute(
            path: '/performance-monitor',
            builder: (context, state) => const PerformanceMonitorScreen()),
      ],
      StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/',
                  builder: (context, state) => const ChatFirstHomeHost())
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/search', redirect: (context, state) => '/')
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/watchlist',
                  builder: (context, state) => const WatchlistScreen())
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/updates',
                  builder: (context, state) => const UpdatesScreen())
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/profile',
                  builder: (context, state) => const ProfileScreen())
            ]),
          ]),
      // One place per function: the old mock alerts / communication centre
      // / preferences screens are merged into Updates + Notifications.
      GoRoute(path: '/alerts', redirect: (context, state) => '/updates'),
      GoRoute(path: '/explore', redirect: (context, state) => '/'),
      GoRoute(
          path: '/location',
          builder: (context, state) => const LocationSetupScreen()),
      // Nearby results appear in the chat for the chosen location; there is
      // no separate (empty) "Nearby shops" page to navigate through.
      GoRoute(path: '/nearby', redirect: (context, state) => '/'),
      // The old mock shop page (buttons that did nothing) is retired: shops
      // appear as result cards in Main Chat.
      GoRoute(path: '/shop/:id', redirect: (context, state) => '/'),
      GoRoute(path: '/map/shop/:id', redirect: (context, state) => '/'),
      GoRoute(path: '/nearby/product/:id', redirect: (context, state) => '/'),
      GoRoute(path: '/alert/:id/map', redirect: (context, state) => '/updates'),
      GoRoute(
          path: '/product/:id',
          builder: (context, state) =>
              ProductDetailsScreen(productId: state.pathParameters['id']!)),
      // The old barcode/OCR/image/voice discovery screen (system recognizer,
      // mock catalog) is gone: Main Chat does all of it (+ camera, voice).
      GoRoute(path: '/discover/:mode', redirect: (context, state) => '/'),
      GoRoute(
          path: '/product-not-found',
          builder: (context, state) => const ProductNotFoundScreen()),
      GoRoute(
          path: '/settings/notifications',
          builder: (context, state) => const NotificationSettingsScreen()),
      GoRoute(path: '/companion/screen-guide', builder: (context, state) => const ScreenGuideScreen()),
      GoRoute(
          path: '/notification-preferences',
          redirect: (context, state) => '/settings/notifications'),
      GoRoute(
          path: '/communications',
          redirect: (context, state) => '/updates',
          routes: [
            GoRoute(path: 'notifications', redirect: (context, state) => '/updates'),
            GoRoute(path: 'requests', redirect: (context, state) => '/updates'),
            GoRoute(path: 'following', redirect: (context, state) => '/updates'),
            GoRoute(path: 'preferences', redirect: (context, state) => '/settings/notifications'),
          ]),
      GoRoute(
          path: '/deals', builder: (context, state) => const DealInboxScreen()),
      GoRoute(
          path: '/listings/mine',
          builder: (context, state) => const MyListingsScreen()),
      GoRoute(
          path: '/orders/mine',
          builder: (context, state) => const MyOrdersScreen()),
      GoRoute(
          path: '/orders/incoming',
          builder: (context, state) => const IncomingOrdersScreen()),
      GoRoute(
          path: '/opportunities',
          builder: (context, state) => const SellerOpportunitiesScreen()),
      GoRoute(
          path: '/business',
          builder: (context, state) => const BusinessCenterScreen()),
      GoRoute(path: '/profile/memory', builder: (context, state) => const ProfileMemoryScreen()),
      GoRoute(path: '/profile/roles', builder: (context, state) => const MyRolesScreen()),
      GoRoute(path: '/business/promotions', builder: (context, state) => const BusinessPromotionsScreen()),
      GoRoute(
          path: '/business/automation',
          builder: (context, state) => BusinessAutomationScreen(section: state.uri.queryParameters['section'])),
      GoRoute(
          path: '/deal/:requestId',
          builder: (context, state) => DealThreadScreen(
              requestId:
                  int.tryParse(state.pathParameters['requestId'] ?? '') ?? 0,
              userId: state.uri.queryParameters['user'] ?? '',
              otherUserId: state.uri.queryParameters['other'] ?? '')),
      if (kDebugMode)
        GoRoute(
            path: '/alert-simulator',
            builder: (context, state) => const AlertSimulatorScreen()),
      // Demo buyer "insights" (sample charts) are not a customer feature.
      GoRoute(path: '/analytics/buyer', redirect: (context, state) => '/'),
      GoRoute(path: '/analytics/privacy', redirect: (context, state) => '/privacy'),
      // Profile > Companion: real-device performance + the Human HD engine lab.
      GoRoute(path: '/companion-performance', builder: (context, state) => const AskodoxCompanionPerformancePanel()),
      GoRoute(path: '/companion-lab', builder: (context, state) => const AskodoxCompanionEngineLab()),
      GoRoute(
          path: '/privacy',
          builder: (context, state) => const PrivacyCenterScreen()),
      GoRoute(
          path: '/beta-feedback',
          builder: (context, state) => const BetaFeedbackScreen()),
      GoRoute(path: '/videos/native', builder: (context, state) => const NativeVideoScreen()),
      GoRoute(
          path: '/mobility',
          builder: (context, state) =>
              MobilityScreen(
                  initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
                  initialKind: state.uri.queryParameters['kind'],
                  initialFrom: state.uri.queryParameters['from'],
                  initialTo: state.uri.queryParameters['to'])),
      if (kDebugMode)
        GoRoute(
            path: '/developer/feedback',
            builder: (context, state) => const SubmittedFeedbackScreen()),
      GoRoute(
          path: '/admin/subscriptions',
          builder: (context, state) => const AdminMonetizationScreen()),
      // The live Command Center is the admin entry point (real data, server-
      // side permissions); the legacy mock admin login now leads there.
      GoRoute(
          path: '/admin/login',
          redirect: (context, state) => '/admin/command-center'),
      GoRoute(
          path: '/admin/command-center',
          builder: (context, state) => const CommandCenterScreen()),
      GoRoute(
          path: '/admin/announcements',
          builder: (context, state) => const AnnouncementScreen()),
      GoRoute(
          path: '/admin/analytics',
          builder: (context, state) => const AdminBusinessIntelligenceScreen()),
      GoRoute(
          path: '/admin/reports',
          builder: (context, state) => const ReportBuilderScreen()),
      ShellRoute(
          builder: (context, state, child) => LocalizedAdminShell(child: child),
          routes: [
            for (final section in AdminSection.values)
              GoRoute(
                  path: '/admin/${section.name}',
                  builder: (context, state) =>
                      LocalizedAdminSectionScreen(section: section)),
          ]),
    ],
  );
});
