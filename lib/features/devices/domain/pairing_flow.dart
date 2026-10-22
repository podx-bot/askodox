/// The ONE Add-Device flow as a pure state machine (unit-tested): capability
/// check -> permission (only now) -> scan -> choose -> connect -> discover
/// supported capabilities -> saved / failed. The UI renders the state; the
/// BLE gateway drives the events.
library;

enum AskodoxPairingStep {
  idle,
  checking, // is Bluetooth LE supported and on?
  unsupported, // this phone has no BLE
  bluetoothOff,
  scanning,
  choose, // results listed, waiting for the user
  connecting,
  discovering,
  ready, // connected; supported profiles known (may be empty)
  saved, // registered in the user's device dashboard
  failed,
}

enum AskodoxPairingEvent {
  start,
  bleUnsupported,
  bleOff,
  bleOn,
  permissionDenied,
  scanDone,
  select,
  connected,
  discovered,
  saved,
  error,
  reset,
}

class AskodoxPairingState {
  const AskodoxPairingState(this.step, {this.reason});
  final AskodoxPairingStep step;

  /// permission_denied | connect_failed | discover_failed | save_failed | scan_failed
  final String? reason;

  bool get busy => const {
        AskodoxPairingStep.checking,
        AskodoxPairingStep.scanning,
        AskodoxPairingStep.connecting,
        AskodoxPairingStep.discovering,
      }.contains(step);
}

/// Allowed transitions; anything else leaves the state unchanged (so a late
/// callback from a cancelled scan can never jump the flow forward).
AskodoxPairingState askodoxPairingNext(AskodoxPairingState state, AskodoxPairingEvent event, {String? reason}) {
  final s = state.step;
  AskodoxPairingState to(AskodoxPairingStep step, [String? why]) => AskodoxPairingState(step, reason: why);
  switch (event) {
    case AskodoxPairingEvent.reset:
      return to(AskodoxPairingStep.idle);
    case AskodoxPairingEvent.start:
      return const {AskodoxPairingStep.idle, AskodoxPairingStep.failed, AskodoxPairingStep.bluetoothOff,
            AskodoxPairingStep.choose, AskodoxPairingStep.saved}.contains(s)
          ? to(AskodoxPairingStep.checking)
          : state;
    case AskodoxPairingEvent.bleUnsupported:
      return s == AskodoxPairingStep.checking ? to(AskodoxPairingStep.unsupported) : state;
    case AskodoxPairingEvent.bleOff:
      return s == AskodoxPairingStep.checking || s == AskodoxPairingStep.scanning ? to(AskodoxPairingStep.bluetoothOff) : state;
    case AskodoxPairingEvent.bleOn:
      return s == AskodoxPairingStep.checking ? to(AskodoxPairingStep.scanning) : state;
    case AskodoxPairingEvent.permissionDenied:
      return s == AskodoxPairingStep.checking || s == AskodoxPairingStep.scanning || s == AskodoxPairingStep.connecting
          ? to(AskodoxPairingStep.failed, 'permission_denied')
          : state;
    case AskodoxPairingEvent.scanDone:
      return s == AskodoxPairingStep.scanning ? to(AskodoxPairingStep.choose) : state;
    case AskodoxPairingEvent.select:
      return s == AskodoxPairingStep.choose ? to(AskodoxPairingStep.connecting) : state;
    case AskodoxPairingEvent.connected:
      return s == AskodoxPairingStep.connecting ? to(AskodoxPairingStep.discovering) : state;
    case AskodoxPairingEvent.discovered:
      return s == AskodoxPairingStep.discovering ? to(AskodoxPairingStep.ready) : state;
    case AskodoxPairingEvent.saved:
      return s == AskodoxPairingStep.ready ? to(AskodoxPairingStep.saved) : state;
    case AskodoxPairingEvent.error:
      return s == AskodoxPairingStep.idle ? state : to(AskodoxPairingStep.failed, reason ?? 'error');
  }
}
