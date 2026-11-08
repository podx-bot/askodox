import 'package:go_router/go_router.dart';

import 'talk_screens.dart';

/// ASKODOX Talk routes (registered once in app_router). Opened from the Talk
/// button beside the logo in the header.
final askodoxTalkRoutes = <GoRoute>[
  GoRoute(path: '/talk', builder: (context, state) => const AskodoxTalkScreen()),
  GoRoute(
    path: '/talk/:id',
    builder: (context, state) => AskodoxTalkRoomScreen(
      roomId: state.pathParameters['id'] ?? '',
      topic: state.uri.queryParameters['topic'] ?? '',
    ),
  ),
];
