import 'package:go_router/go_router.dart';

import '../../business/presentation/biz_work.dart' show AskodoxShopBookScreen, AskodoxMyWorkScreen;
import '../../finance/finance_item_screen.dart';
import '../../pos/presentation/shop_rating_screens.dart';
import '../../steps/presentation/bill_steps_screen.dart';
import '../../try_on/try_on_screen.dart';
import 'my_business_screens.dart';
import 'shop_follow_screens.dart';
import 'shop_post_screens.dart';
import '../../memberships/memberships_screens.dart';
import '../../business_story/business_story.dart';
import '../../home_hub/home_hub_screen.dart';
import '../../kitchen/kitchen_screen.dart';
import '../../vault/vault_screen.dart';

/// Shop follows and shop updates (any signed-in person). `/shop/:id` is a legacy redirect in app_router,
/// so the shop screen uses `/shops/:id`.
final askodoxShopFollowRoutes = <GoRoute>[
  GoRoute(path: '/me/following', builder: (context, state) => const AskodoxFollowingShopsScreen()),
  GoRoute(
      path: '/shops/:id',
      builder: (context, state) => AskodoxShopPageScreen(businessId: state.pathParameters['id']!)),
  // Business Kit (owner 2026-11-24): a customer books; their own bookings, job cards and monthly plans.
  GoRoute(path: '/shops/:id/book', builder: (context, state) => AskodoxShopBookScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/me/bookings', builder: (context, state) => const AskodoxMyWorkScreen(kind: 'bookings')),
  GoRoute(path: '/me/jobs', builder: (context, state) => const AskodoxMyWorkScreen(kind: 'jobs')),
  GoRoute(path: '/me/monthly', builder: (context, state) => const AskodoxMyWorkScreen(kind: 'monthly')),
  GoRoute(path: '/me/memberships', builder: (context, state) => const AskodoxMyMembershipsScreen()),
  // Owner 2026-11-27 (phase 6): bills & warranty papers, kept on the person's own phone.
  GoRoute(path: '/me/vault', builder: (context, state) => AskodoxVaultScreen(startPhoto: state.uri.queryParameters['photo'] ?? '')),
  // Owner 2026-11-27 (phase 6): "My home" reads the kitchen stock and the papers kept on this phone.
  // Owner 2026-11-27 (phase 6): three spoken questions about the business; the answers stay on this phone.
  GoRoute(path: '/me/tell-business', builder: (context, state) => const AskodoxBusinessStoryScreen()),
  GoRoute(path: '/me/home', builder: (context, state) => const AskodoxHomeHubScreen()),
  // Owner 2026-11-27 (phase 6): the home kitchen stock, on the person's own phone.
  GoRoute(path: '/me/kitchen', builder: (context, state) => const AskodoxKitchenScreen()),
  // Finance item: answers from the company's document + a call back on the customer's yes.
  GoRoute(path: '/finance/:id', builder: (context, state) => AskodoxFinanceItemScreen(itemId: state.pathParameters['id']!)),
  // Photo try-on: ?image=<item photo url>&name=<item>&mode=on_me|in_home (from a result card, or empty).
  GoRoute(
      path: '/try-on',
      builder: (context, state) => AskodoxTryOnScreen(
          imageUrl: state.uri.queryParameters['image'] ?? '',
          itemName: state.uri.queryParameters['name'] ?? '',
          mode: state.uri.queryParameters['mode'] ?? 'on_me')),
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
