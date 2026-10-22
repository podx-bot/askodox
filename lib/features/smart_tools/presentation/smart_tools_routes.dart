import 'package:go_router/go_router.dart';

import '../../devices/presentation/device_screens.dart';
import '../../devices/presentation/ptt_screens.dart';
import '../../intelligence/presentation/intelligence_screens.dart';

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
  // Round 2: money & safety (backend /api/intel/*).
  GoRoute(path: '/intel/tax', builder: (context, state) => const AskodoxIncomeTaxScreen()),
  GoRoute(path: '/intel/gst', builder: (context, state) => const AskodoxGstScreen()),
  GoRoute(path: '/intel/fraud', builder: (context, state) => const AskodoxFraudListScreen()),
  GoRoute(
      path: '/intel/fraud/:id',
      builder: (context, state) => AskodoxFraudDetailScreen(schemeId: state.pathParameters['id'] ?? '')),
  GoRoute(
      path: '/intel/tricks',
      builder: (context, state) => AskodoxSmartTricksScreen(initial: state.uri.queryParameters['calc'])),
  // Round 3: connectivity, pairing, push-to-talk.
  GoRoute(path: '/devices', builder: (context, state) => const AskodoxDevicesScreen()),
  GoRoute(path: '/devices/add', builder: (context, state) => const AskodoxAddDeviceScreen()),
  GoRoute(path: '/devices/compatibility', builder: (context, state) => const AskodoxDeviceCompatibilityScreen()),
  GoRoute(
      path: '/devices/live',
      builder: (context, state) => AskodoxDeviceLiveScreen(
            localId: state.uri.queryParameters['id'] ?? '',
            name: state.uri.queryParameters['name'] ?? '',
            deviceId: state.uri.queryParameters['device'],
          )),
  GoRoute(path: '/ptt', builder: (context, state) => const AskodoxPttHomeScreen()),
  GoRoute(
      path: '/ptt/:id',
      builder: (context, state) => AskodoxPttChannelScreen(
            channelId: state.pathParameters['id'] ?? '',
            name: state.uri.queryParameters['name'] ?? '',
            code: state.uri.queryParameters['code'] ?? '',
          )),
];

/// Paths the routes above serve (for the registry consistency test).
const askodoxSmartToolPaths = [
  '/tools', '/tools/level', '/tools/compass', '/tools/inspect', '/tools/calc/',
  '/intel/tax', '/intel/gst', '/intel/fraud', '/intel/fraud/', '/intel/tricks',
  '/devices', '/devices/add', '/devices/compatibility', '/devices/live', '/ptt', '/ptt/',
];
