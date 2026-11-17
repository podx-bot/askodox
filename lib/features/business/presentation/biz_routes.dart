import 'package:go_router/go_router.dart';

import 'biz_hub.dart';
import 'biz_menu.dart';

/// The business hub's pages (owner 2026-11-18): `/biz/:id` is the hub, `/biz/:id/:group` a group page.
final askodoxBizRoutes = <GoRoute>[
  GoRoute(path: '/biz/:id', builder: (c, s) => AskodoxBizHubScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/menu', builder: (c, s) => AskodoxBizMenuScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/menu/sort', builder: (c, s) => AskodoxBizMenuSortScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/menu/section/:name',
      builder: (c, s) =>
          AskodoxBizSectionScreen(businessId: s.pathParameters['id']!, section: s.pathParameters['name']!)),
  GoRoute(
      path: '/biz/:id/menu/item/:pid',
      builder: (c, s) => AskodoxBizItemScreen(businessId: s.pathParameters['id']!, productId: s.pathParameters['pid']!)),
  GoRoute(
      path: '/biz/:id/:group',
      builder: (c, s) => AskodoxBizGroupScreen(businessId: s.pathParameters['id']!, groupId: s.pathParameters['group']!)),
];
