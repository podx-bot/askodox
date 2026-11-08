import 'package:go_router/go_router.dart';

import 'work_mode_screens.dart';

/// Work Mode routes (registered once in app_router). Opened from the game
/// button beside the ASKODOX wordmark in the header.
final askodoxWorkModeRoutes = <GoRoute>[
  GoRoute(path: '/work', builder: (context, state) => const AskodoxWorkModeScreen()),
  GoRoute(path: '/work/seva', builder: (context, state) => const AskodoxSevaScreen()),
];
