import 'package:go_router/go_router.dart';

import '../../devices/presentation/device_screens.dart';
import '../../devices/presentation/ptt_screens.dart';
import '../../intelligence/presentation/intelligence_screens.dart';
import '../../intelligence/presentation/personal_finance_screen.dart';

import 'calculator_screens.dart';
import 'extra_tools_screens.dart';
import 'inspection_screen.dart';
import 'load_planner_screen.dart';
import 'photo_measure_screen.dart';
import 'sensor_tools_screen.dart';
import 'smart_tools_hub_screen.dart';

/// Smart Tools routes (registered once in app_router). Every route a tool in
/// the registry names must resolve here (guarded by a unit test).
final askodoxSmartToolRoutes = <GoRoute>[
  GoRoute(path: '/tools', builder: (context, state) => const AskodoxSmartToolsHubScreen()),
  GoRoute(path: '/tools/level', builder: (context, state) => const AskodoxLevelScreen()),
  GoRoute(path: '/tools/compass', builder: (context, state) => const AskodoxCompassScreen()),
  GoRoute(path: '/tools/measure-photo', builder: (context, state) => const AskodoxPhotoMeasureScreen()),
  GoRoute(path: '/tools/protractor', builder: (context, state) => const AskodoxProtractorScreen()),
  GoRoute(path: '/tools/magnifier', builder: (context, state) => const AskodoxMagnifierScreen()),
  GoRoute(path: '/tools/light', builder: (context, state) => const AskodoxLightMeterScreen()),
  GoRoute(path: '/tools/sound', builder: (context, state) => const AskodoxSoundMeterScreen()),
  GoRoute(path: '/tools/vehicle-report', builder: (context, state) => const AskodoxVehicleReportScreen()),
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
  // Profile -> Personal Finance (Personal Tax Assistant home; opens the /intel/* screens below).
  GoRoute(path: '/me/finance', builder: (context, state) => const AskodoxPersonalFinanceScreen()),
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
  '/tools', '/tools/level', '/tools/compass', '/tools/inspect', '/tools/calc/', '/tools/measure-photo',
  '/tools/protractor', '/tools/magnifier', '/tools/light', '/tools/sound', '/tools/vehicle-report',
  '/intel/tax', '/intel/gst', '/intel/fraud', '/intel/fraud/', '/intel/tricks',
  '/devices', '/devices/add', '/devices/compatibility', '/devices/live', '/ptt', '/ptt/',
];
