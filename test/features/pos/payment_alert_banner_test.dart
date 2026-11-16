import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/payment_alert_banner.dart';

void main() {
  Map<String, Object?> st({bool declared = true, bool allowed = true, bool shop = false, bool? tts}) =>
      {'listenerDeclared': declared, 'listenerAllowed': allowed, 'enabled': shop, if (tts != null) 'ttsReady': tts};

  test('not a phone / old native side: no warning', () {
    expect(askodoxAlertHealthOf({'unavailable': true}, mineEnabled: false, mineApps: 0), AskodoxAlertHealth.unknown);
  });
  test('never turned on is "off"', () {
    expect(askodoxAlertHealthOf(st(), mineEnabled: false, mineApps: 5), AskodoxAlertHealth.off);
  });
  test('shop-only phone counts as on', () {
    expect(askodoxAlertHealthOf(st(shop: true), mineEnabled: false, mineApps: 0), AskodoxAlertHealth.ok);
  });
  test('each missing part is named', () {
    expect(askodoxAlertHealthOf(st(declared: false), mineEnabled: true, mineApps: 3), AskodoxAlertHealth.noListener);
    expect(askodoxAlertHealthOf(st(allowed: false), mineEnabled: true, mineApps: 3), AskodoxAlertHealth.needsAccess);
    expect(askodoxAlertHealthOf(st(), mineEnabled: true, mineApps: 0), AskodoxAlertHealth.noApps);
    expect(askodoxAlertHealthOf(st(tts: false), mineEnabled: true, mineApps: 3), AskodoxAlertHealth.noVoice);
    expect(askodoxAlertHealthOf(st(), mineEnabled: true, mineApps: 3), AskodoxAlertHealth.ok);
  });
  test('a broken setup comes back sooner than the first nudge', () {
    expect(askodoxAlertSnooze(AskodoxAlertHealth.off) > askodoxAlertSnooze(AskodoxAlertHealth.needsAccess), isTrue);
    expect(askodoxAlertHealthText(AskodoxAlertHealth.needsAccess, true).isNotEmpty, isTrue);
  });
}
