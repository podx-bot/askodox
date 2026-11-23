import 'package:go_router/go_router.dart';

import '../../pos/presentation/shop_rating_screens.dart';
import '../../steps/presentation/bill_steps_screen.dart';
import 'my_business_screens.dart';
import 'shop_follow_screens.dart';
import 'shop_post_screens.dart';

/// Shop follows and shop updates (any signed-in person). `/shop/:id` is a legacy redirect in app_router,
/// so the shop screen uses `/shops/:id`.
final askodoxShopFollowRoutes = <GoRoute>[
  GoRoute(path: '/me/following', builder: (context, state) => const AskodoxFollowingShopsScreen()),
  GoRoute(
      path: '/shops/:id',
      builder: (context, state) => AskodoxShopPageScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/shops/:id/post',
      builder: (context, state) => AskodoxShopPostScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/me/shop-feed', builder: (context, state) => const AskodoxShopFeedScreen()),
  // My business (Phase 1): the simple desk -- details, calculator bill + QR, today's post.
  GoRoute(path: '/me/business', builder: (context, state) => const AskodoxMyBusinessScreen()),
  GoRoute(
      path: '/me/business/:id/profile',
      // ?qa=1 (owner push "A customer asked"): the customer questions open at once.
      builder: (context, state) => AskodoxBusinessProfileScreen(
          businessId: state.pathParameters['id']!, openQuestions: state.uri.queryParameters['qa'] == '1')),
  GoRoute(
      path: '/me/business/:id/bill',
      // Owner 2026-11-22: the 3-step bill (items -> how paid -> done); the full page (GST, advance, edit) at ?full=1.
      builder: (context, state) => state.uri.queryParameters['full'] == '1'
          ? AskodoxQuickBillScreen(businessId: state.pathParameters['id']!)
          : AskodoxBillStepsScreen(businessId: state.pathParameters['id']!)),
];
