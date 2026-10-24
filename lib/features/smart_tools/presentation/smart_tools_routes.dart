import 'package:go_router/go_router.dart';

import 'calculator_screens.dart';
import 'inspection_screen.dart';
import 'load_planner_screen.dart';
import 'sensor_tools_screen.dart';
import 'smart_tools_hub_screen.dart';

/// Smart Tools routes (registered once in app_router). Every route a tool in
/// the registry names must resolve here (guarded by a unit test).
final askodoxSmartToolRoutes = <GoRoute>[
  GoRoute(path: '/tools', builder: (context, state) => const AskodoxSmartToolsHubScreen()),
  GoRoute(path: '/tools/level', builder: (context, state) => const AskodoxLevelScreen()),
  GoRoute(path: '/tools/compass', builder: (context, state) => const AskodoxCompassScreen()),
  GoRoute(
      path: '/tools/inspect',
      builder: (context, state) => AskodoxInspectionScreen(initialDomain: state.uri.queryParameters['domain'])),
  GoRoute(
      path: '/tools/calc/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return id == 'load' ? const AskodoxLoadPlannerScreen() : askodoxCalculatorFor(id);
      }),
];

/// Paths the routes above serve (for the registry consistency test).
const askodoxSmartToolPaths = ['/tools', '/tools/level', '/tools/compass', '/tools/inspect', '/tools/calc/'];
