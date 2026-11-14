import 'package:go_router/go_router.dart';

import 'shop_follow_screens.dart';
import 'shop_post_screens.dart';

/// Shop follows and shop updates (any signed-in person). `/shop/:id` is a legacy redirect in app_router,
/// so the shop screen uses `/shops/:id`.
final askodoxShopFollowRoutes = <GoRoute>[
  GoRoute(path: '/me/following', builder: (context, state) => const AskodoxFollowingShopsScreen()),
  GoRoute(
      path: '/shops/:id',
      builder: (context, state) => AskodoxShopFollowScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/shops/:id/post',
      builder: (context, state) => AskodoxShopPostScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/me/shop-feed', builder: (context, state) => const AskodoxShopFeedScreen()),
];
