/// ASKODOX Smart Toolbox registry: ONE list of tools with what each needs
/// and how ready it honestly is. The hub, the chat router and the tests all
/// read this list -- a tool is never shown as working unless it is.
library;

/// What a tool needs to work.
enum AskodoxToolNeed {
  phoneSensor, // built-in accelerometer / magnetometer / light sensor
  camera,
  cameraAi, // camera + cloud vision model
  arCore, // Google ARCore + a supported phone
  externalSensor,
  bluetoothDevice,
  usbAdapter,
  cloudApi,
  manualInput,
}

/// How ready a tool is in this build.
enum AskodoxToolReadiness {
  /// Pure calculation on the phone; tested by unit tests.
  ready,

  /// Uses the phone's sensors or camera; built, but not yet verified on a
  /// real phone (labelled so in the hub).
  hardwareUnverified,

  /// Needs a device ASKODOX cannot pair with yet.
  needsExternalDevice,

  /// Planned; not built.
  comingSoon,
}

enum AskodoxToolGroup { measure, construction, inspect, sensors, devices }

class AskodoxSmartTool {
  const AskodoxSmartTool({
    required this.id,
    required this.nameEn,
    required this.nameTe,
    required this.group,
    required this.needs,
    required this.readiness,
    this.route,
    this.safetyNote,
  });

  final String id;
  final String nameEn;
  final String nameTe;
  final AskodoxToolGroup group;
  final Set<AskodoxToolNeed> needs;
  final AskodoxToolReadiness readiness;

  /// In-app route; null while the tool is not built.
  final String? route;

  /// Shown on the tool and in the hub (e.g. "not a certified instrument").
  final String? safetyNote;

  bool get opens => route != null &&
      (readiness == AskodoxToolReadiness.ready || readiness == AskodoxToolReadiness.hardwareUnverified);

  String name(bool te) => te ? nameTe : nameEn;
}

const _notCertified = 'Approximate. Not a certified measuring instrument.';
const _electricalNote = 'Never replaces a certified electrical tester or an electrician.';

const askodoxSmartTools = <AskodoxSmartTool>[
  AskodoxSmartTool(
      id: 'level', nameEn: 'Bubble / spirit level', nameTe: 'బబుల్ లెవెల్', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/level', safetyNote: _notCertified),
  AskodoxSmartTool(
      id: 'inclinometer', nameEn: 'Inclinometer', nameTe: 'వాలు కొలత', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/level', safetyNote: _notCertified),
  AskodoxSmartTool(
      id: 'angle', nameEn: 'Angle finder', nameTe: 'కోణం కొలత', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/level', safetyNote: _notCertified),
  AskodoxSmartTool(
      id: 'protractor', nameEn: 'Protractor', nameTe: 'ప్రొట్రాక్టర్', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.camera}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'plumb', nameEn: 'Plumb-line assistant', nameTe: 'ప్లంబ్ లైన్', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/level', safetyNote: _notCertified),
  AskodoxSmartTool(
      id: 'ar_tape', nameEn: 'AR measuring tape', nameTe: 'AR కొలత టేప్', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.arCore, AskodoxToolNeed.camera}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'distance', nameEn: 'Distance meter', nameTe: 'దూరం కొలత', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.arCore}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'height', nameEn: 'Height meter', nameTe: 'ఎత్తు కొలత', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.arCore}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'area', nameEn: 'Area & perimeter', nameTe: 'వైశాల్యం & చుట్టుకొలత', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/area'),
  AskodoxSmartTool(
      id: 'volume', nameEn: 'Volume', nameTe: 'ఘనపరిమాణం', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/volume'),
  AskodoxSmartTool(
      id: 'compass', nameEn: 'Digital compass', nameTe: 'దిక్సూచి', group: AskodoxToolGroup.sensors,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/compass', safetyNote: 'Metal and electronics nearby disturb the reading.'),
  AskodoxSmartTool(
      id: 'magnifier', nameEn: 'Magnifier', nameTe: 'మాగ్నిఫైయర్', group: AskodoxToolGroup.inspect,
      needs: {AskodoxToolNeed.camera}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'colour', nameEn: 'Colour picker', nameTe: 'రంగు గుర్తింపు', group: AskodoxToolGroup.inspect,
      needs: {AskodoxToolNeed.camera}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'light', nameEn: 'Light meter', nameTe: 'వెలుతురు కొలత', group: AskodoxToolGroup.sensors,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'sound', nameEn: 'Sound-level estimator', nameTe: 'శబ్ద స్థాయి', group: AskodoxToolGroup.sensors,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'vibration', nameEn: 'Vibration monitor', nameTe: 'కంపనాల పరిశీలన', group: AskodoxToolGroup.sensors,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'rpm', nameEn: 'RPM estimator', nameTe: 'RPM అంచనా', group: AskodoxToolGroup.sensors,
      needs: {AskodoxToolNeed.phoneSensor}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'counter', nameEn: 'Object counter', nameTe: 'వస్తువుల లెక్క', group: AskodoxToolGroup.inspect,
      needs: {AskodoxToolNeed.cameraAi}, readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'inspect', nameEn: 'AI photo inspection', nameTe: 'AI ఫోటో పరిశీలన', group: AskodoxToolGroup.inspect,
      needs: {AskodoxToolNeed.camera, AskodoxToolNeed.cloudApi}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/inspect',
      safetyNote: 'A photo cannot certify food safety, roadworthiness, health or structural safety.'),
  AskodoxSmartTool(
      id: 'crack', nameEn: 'Crack inspector', nameTe: 'పగుళ్ల పరిశీలన', group: AskodoxToolGroup.inspect,
      needs: {AskodoxToolNeed.camera, AskodoxToolNeed.cloudApi}, readiness: AskodoxToolReadiness.hardwareUnverified,
      route: '/tools/inspect?domain=construction',
      safetyNote: 'Structural safety needs a structural engineer.'),
  AskodoxSmartTool(
      id: 'brick', nameEn: 'Brick / block calculator', nameTe: 'ఇటుకల లెక్క', group: AskodoxToolGroup.construction,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/brick'),
  AskodoxSmartTool(
      id: 'cement', nameEn: 'Concrete & plaster (cement, sand)', nameTe: 'సిమెంట్ & ఇసుక లెక్క',
      group: AskodoxToolGroup.construction, needs: {AskodoxToolNeed.manualInput},
      readiness: AskodoxToolReadiness.ready, route: '/tools/calc/cement'),
  AskodoxSmartTool(
      id: 'tile', nameEn: 'Tile & flooring calculator', nameTe: 'టైల్స్ లెక్క', group: AskodoxToolGroup.construction,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/tile'),
  AskodoxSmartTool(
      id: 'paint', nameEn: 'Paint calculator', nameTe: 'పెయింట్ లెక్క', group: AskodoxToolGroup.construction,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/paint'),
  AskodoxSmartTool(
      id: 'load', nameEn: 'Load & space planner', nameTe: 'లోడ్ & స్థలం ప్లానర్', group: AskodoxToolGroup.measure,
      needs: {AskodoxToolNeed.manualInput}, readiness: AskodoxToolReadiness.ready, route: '/tools/calc/load',
      safetyNote: 'Always respect the vehicle payload and axle limits and secure the load.'),
  AskodoxSmartTool(
      id: 'animal_weight', nameEn: 'Animal weight (experimental)', nameTe: 'జంతువు బరువు (ప్రయోగాత్మకం)',
      group: AskodoxToolGroup.inspect, needs: {AskodoxToolNeed.camera, AskodoxToolNeed.cloudApi},
      readiness: AskodoxToolReadiness.hardwareUnverified, route: '/tools/inspect?domain=livestock',
      safetyNote: 'Experimental range only; confirm on a weighing scale.'),
  AskodoxSmartTool(
      id: 'bt_scale', nameEn: 'Bluetooth weighing scale', nameTe: 'బ్లూటూత్ తూకం యంత్రం', group: AskodoxToolGroup.devices,
      needs: {AskodoxToolNeed.bluetoothDevice}, readiness: AskodoxToolReadiness.needsExternalDevice),
  AskodoxSmartTool(
      id: 'moisture', nameEn: 'Moisture sensor', nameTe: 'తేమ సెన్సార్', group: AskodoxToolGroup.devices,
      needs: {AskodoxToolNeed.externalSensor, AskodoxToolNeed.bluetoothDevice},
      readiness: AskodoxToolReadiness.needsExternalDevice),
  AskodoxSmartTool(
      id: 'temperature', nameEn: 'Temperature sensor', nameTe: 'ఉష్ణోగ్రత సెన్సార్', group: AskodoxToolGroup.devices,
      needs: {AskodoxToolNeed.externalSensor, AskodoxToolNeed.bluetoothDevice},
      readiness: AskodoxToolReadiness.needsExternalDevice),
  AskodoxSmartTool(
      id: 'electrical', nameEn: 'Electrical tester', nameTe: 'ఎలక్ట్రికల్ టెస్టర్', group: AskodoxToolGroup.devices,
      needs: {AskodoxToolNeed.externalSensor, AskodoxToolNeed.bluetoothDevice},
      readiness: AskodoxToolReadiness.needsExternalDevice, safetyNote: _electricalNote),
  AskodoxSmartTool(
      id: 'pairing', nameEn: 'Add device / smart home', nameTe: 'డివైస్ జత చేయడం / స్మార్ట్ హోమ్',
      group: AskodoxToolGroup.devices, needs: {AskodoxToolNeed.bluetoothDevice},
      readiness: AskodoxToolReadiness.comingSoon),
  AskodoxSmartTool(
      id: 'laser', nameEn: 'Laser distance meter', nameTe: 'లేజర్ దూరం మీటర్', group: AskodoxToolGroup.devices,
      needs: {AskodoxToolNeed.bluetoothDevice}, readiness: AskodoxToolReadiness.needsExternalDevice),
];

AskodoxSmartTool? askodoxToolById(String id) {
  for (final tool in askodoxSmartTools) {
    if (tool.id == id) return tool;
  }
  return null;
}
