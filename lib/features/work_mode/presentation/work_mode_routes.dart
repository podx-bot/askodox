import 'package:go_router/go_router.dart';

import '../../workout/workout_screen.dart';
import 'work_mode_screens.dart';

/// Work Mode routes (registered once in app_router). Opened from the game
/// button beside the ASKODOX wordmark in the header.
final askodoxWorkModeRoutes = <GoRoute>[
  GoRoute(path: '/work', builder: (context, state) => const AskodoxWorkModeScreen()),
  GoRoute(path: '/work/seva', builder: (context, state) => const AskodoxSevaScreen()),
  // Owner 2026-11-27 (phase 4): the workout tracker -- sets, rest timer, personal records. On the phone only.
  GoRoute(path: '/work/workout', builder: (context, state) => const AskodoxWorkoutScreen()),
];
