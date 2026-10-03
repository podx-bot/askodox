import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Android reports about the floating bubble.
class AskodoxBubbleStatus {
  const AskodoxBubbleStatus({this.supported = false, this.canDrawOverlays = false, this.running = false});

  /// Android 8+ only (overlay window type).
  final bool supported;

  /// The user granted "Display over other apps".
  final bool canDrawOverlays;
  final bool running;
}

/// Native side: AskodoxFloatingCompanionService.kt via the device channel.
class AskodoxBubblePlatform {
  const AskodoxBubblePlatform([this._channel = const MethodChannel('com.askodox.app/device')]);

  final MethodChannel _channel;

  Future<AskodoxBubbleStatus> status() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('floatingBubbleStatus');
      return AskodoxBubbleStatus(
        supported: map?['supported'] == true,
        canDrawOverlays: map?['canDrawOverlays'] == true,
        running: map?['running'] == true,
      );
    } catch (_) {
      return const AskodoxBubbleStatus(); // not Android / older app build
    }
  }

  Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<bool>('openOverlaySettings');
    } catch (_) {}
  }

  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('startFloatingBubble') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stopFloatingBubble');
    } catch (_) {}
  }
}

final askodoxBubblePlatformProvider = Provider<AskodoxBubblePlatform>((ref) => const AskodoxBubblePlatform());

/// enabled | needsPermission | unsupported | off
enum AskodoxBubbleState { off, needsPermission, enabled, unsupported }

/// The floating ASKODOX bubble setting. Off by default; turning it on is an
/// explicit choice, needs Android's "Display over other apps" permission and
/// shows a (silent) notification while it runs -- Android requires it. The
/// bubble never listens or looks at the screen: tap = open ASKODOX.
class AskodoxBubbleController extends StateNotifier<AskodoxBubbleState> {
  AskodoxBubbleController(this._platform) : super(AskodoxBubbleState.off) {
    _restore();
  }

  final AskodoxBubblePlatform _platform;
  static const _key = 'askodox.bubble.enabled';

  Future<void> _restore() async {
    try {
      if ((await SharedPreferences.getInstance()).getBool(_key) == true) await sync();
    } catch (_) {}
  }

  Future<void> _save(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }

  /// The user turned the bubble on: ask for the permission if needed.
  Future<AskodoxBubbleState> enable() async {
    await _save(true);
    final status = await _platform.status();
    if (!status.supported) {
      await _save(false);
      return state = AskodoxBubbleState.unsupported;
    }
    if (!status.canDrawOverlays) {
      await _platform.openPermissionSettings();
      return state = AskodoxBubbleState.needsPermission;
    }
    await _platform.start();
    return state = AskodoxBubbleState.enabled;
  }

  Future<void> disable() async {
    await _save(false);
    await _platform.stop();
    state = AskodoxBubbleState.off;
  }

  /// App came to the foreground: (re)start the service while it is allowed
  /// to (Android 12+ forbids starting it from the background), e.g. right
  /// after the user granted the permission in Settings. Turned off from the
  /// notification -> the setting follows.
  Future<void> sync() async {
    bool on;
    try {
      on = (await SharedPreferences.getInstance()).getBool(_key) == true;
    } catch (_) {
      on = false;
    }
    if (!on) {
      if (mounted) state = AskodoxBubbleState.off;
      return;
    }
    final status = await _platform.status();
    if (!mounted) return;
    if (!status.supported) {
      state = AskodoxBubbleState.unsupported;
    } else if (!status.canDrawOverlays) {
      state = AskodoxBubbleState.needsPermission;
    } else {
      if (!status.running) await _platform.start();
      if (mounted) state = AskodoxBubbleState.enabled;
    }
  }
}

final askodoxBubbleProvider = StateNotifierProvider<AskodoxBubbleController, AskodoxBubbleState>(
  (ref) => AskodoxBubbleController(ref.watch(askodoxBubblePlatformProvider)),
);
