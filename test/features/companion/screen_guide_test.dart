import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podx/features/companion/screen_guide.dart';

class _FakeNative extends ScreenGuideNative {
  _FakeNative({this.enabled = true, this.startOk = true, this.declared = true});
  bool enabled;
  bool declared;
  bool startOk;
  final calls = <String>[];
  Map<String, Object?>? startArgs;
  String nativeState = 'IDLE';

  @override
  Future<Map<String, Object?>> status() async =>
      {'supported': true, 'declared': declared, 'accessibilityEnabled': enabled, 'state': nativeState};
  @override
  Future<bool> start(Map<String, Object?> args) async {
    calls.add('start');
    startArgs = args;
    return startOk;
  }
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop(String outcome) async => calls.add('stop:$outcome');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScreenGuideApi api(List<String> seen, {int startStatus = 200}) => ScreenGuideApi(
        baseUrl: 'https://staging.example',
        client: MockClient((req) async {
          seen.add(req.url.path);
          if (req.url.path.endsWith('/status')) {
            return http.Response(jsonEncode({'enabled': true}), 200);
          }
          if (req.url.path.endsWith('/start')) {
            return http.Response(jsonEncode({'session_id': 'sg_1', 'state': 'ACTIVE'}), startStatus);
          }
          return http.Response(jsonEncode({'state': 'ENDED'}), 200);
        }),
      );

  test('a goal with a code, PIN or password is refused before anything starts', () {
    expect(screenGuideGoalProblem('turn on wifi'), isNull);
    expect(screenGuideGoalProblem('my OTP is 482913'), isNotNull);
    expect(screenGuideGoalProblem('enter UPI PIN'), isNotNull);
    expect(screenGuideGoalProblem('పాస్‌వర్డ్ మార్చు'), isNotNull);
  });

  test('start -> active; explicit resume; End Guide clears phone and server session', () async {
    final seen = <String>[];
    final native = _FakeNative();
    final c = ScreenGuideController(native, api(seen), () => 'tok', consented: () async => true);
    await c.start('turn on Wi-Fi');
    expect(c.state.phase, ScreenGuidePhase.active);
    expect(native.startArgs!['baseUrl'], 'https://staging.example');
    c.markPaused();
    expect(c.state.phase, ScreenGuidePhase.privacyPaused);
    expect(c.state.message, screenGuidePauseMessage);
    await c.resume();
    expect(c.state.phase, ScreenGuidePhase.active);
    expect(native.calls, contains('resume'));
    await c.end(outcome: 'success');
    expect(c.state.phase, ScreenGuidePhase.ended);
    expect(c.state.sessionId, isNull);
    expect(native.calls.last, 'stop:success');
    expect(seen, containsAllInOrder(['/api/companion/guide/start', '/api/companion/guide/resume',
                                     '/api/companion/guide/end']));
  });

  test('needs the accessibility switch, sign-in, and the server flag', () async {
    final seen = <String>[];
    final c1 = ScreenGuideController(_FakeNative(enabled: false), api(seen), () => 'tok', consented: () async => true);
    await c1.start('open settings');
    expect(c1.state.phase, ScreenGuidePhase.needsAccessibility);
    final c2 = ScreenGuideController(_FakeNative(), api(seen), () => null, consented: () async => true);
    await c2.start('open settings');
    expect(c2.state.phase, ScreenGuidePhase.error);
    final c3 = ScreenGuideController(_FakeNative(), api(seen, startStatus: 503), () => 'tok', consented: () async => true);
    await c3.start('open settings');
    expect(c3.state.phase, ScreenGuidePhase.disabled);
    expect(seen.where((p) => p.endsWith('/start')).length, 1, reason: 'no server call without sign-in / switch');
  });

  test('if the phone service is not connected, the server session is ended again', () async {
    final seen = <String>[];
    final c = ScreenGuideController(_FakeNative(startOk: false), api(seen), () => 'tok', consented: () async => true);
    await c.start('open settings');
    expect(c.state.phase, ScreenGuidePhase.needsAccessibility);
    expect(seen.last, '/api/companion/guide/end');
  });

  test('refresh mirrors the phone state (paused on the phone -> paused here)', () async {
    final native = _FakeNative()..nativeState = 'PRIVACY_PAUSED';
    final c = ScreenGuideController(native, api([]), () => 'tok', consented: () async => true);
    await c.refresh();
    expect(c.state.phase, ScreenGuidePhase.privacyPaused);
    // Unknown platform (method channel missing) -> unavailable, never a crash.
    const channel = ScreenGuideNative(MethodChannel('askodox.test/none'));
    expect(await channel.status(), isEmpty);
  });

  test('no consent -> nothing starts and no server call; declined consent is recorded as not given', () async {
    final seen = <String>[];
    final c = ScreenGuideController(_FakeNative(), api(seen), () => 'tok', consented: () async => false);
    await c.start('turn on Wi-Fi');
    expect(c.state.phase, ScreenGuidePhase.needsConsent);
    expect(seen, isEmpty);
  });

  test('build without the accessibility service -> clear fallback, never a start', () async {
    final seen = <String>[];
    final c = ScreenGuideController(_FakeNative(declared: false), api(seen), () => 'tok', consented: () async => true);
    await c.refresh();
    expect(c.state.phase, ScreenGuidePhase.notIncluded);
    await c.start('turn on Wi-Fi');
    expect(c.state.phase, ScreenGuidePhase.notIncluded);
    expect(seen.where((p) => p.endsWith('/start')), isEmpty);
  });

  test('the disclosure covers what, why, data, local processing, never-collected, control', () {
    final text = screenGuideDisclosure.join(' ').toLowerCase();
    for (final must in ['never taps', 'accessibility', 'only while a guide is running', 'sent to askodox servers',
                        'privacy shield', 'never collected', 'end guide', 'turn the permission off']) {
      expect(text, contains(must));
    }
  });
}
