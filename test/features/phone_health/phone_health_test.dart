import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/phone_health/phone_health.dart';

void main() {
  Map<String, String> states(Map<String, Object?> status) => {for (final c in askodoxPhoneChecks(status)) c.id: c.state};

  test('only the app\'s own settings are checked; a phone that cannot tell says unknown', () {
    expect(askodoxPhoneChecks({'unavailable': true}), isEmpty, reason: 'not an Android phone');
    expect(
        states({
          'notificationsEnabled': false,
          'batteryUnrestricted': true,
          'autostartPage': true,
          'listenerDeclared': true,
          'listenerAllowed': false,
          'enabled': true,
          'ttsReady': null,
        }),
        {'notifications': 'bad', 'battery': 'ok', 'autostart': 'unknown', 'payment_access': 'bad', 'voice': 'unknown'});
    // payment voice not switched on: its permission is not a problem to show
    expect(states({'notificationsEnabled': true, 'batteryUnrestricted': true, 'listenerDeclared': true, 'ttsReady': true}),
        {'notifications': 'ok', 'battery': 'ok', 'voice': 'ok'});
  });

  test('allowed but cut off by the phone, a missing voice and unsent payments are named', () {
    final out = states({
      'notificationsEnabled': true,
      'batteryUnrestricted': false,
      'listenerDeclared': true,
      'listenerAllowed': true,
      'personalEnabled': true,
      'connectedAt': 1000,
      'disconnectedAt': 2000,
      'ttsReady': true,
      'ttsLanguageOk': false,
      'pending': 3,
    });
    expect(out['payment_access'], 'ok');
    expect(out['payment_alive'], 'bad');
    expect(out['voice_language'], 'bad');
    expect(out['pending_upload'], 'bad');
    expect(out.containsKey('autostart'), isFalse, reason: 'this phone has no autostart page');
  });

  test('every maker gets its own words, an unknown maker gets plain Android (etc. = all phones)', () {
    const makers = {
      'samsung': 'samsung', 'Xiaomi': 'xiaomi', 'Redmi': 'xiaomi', 'POCO': 'xiaomi', 'vivo': 'vivo', 'iQOO': 'vivo',
      'OPPO': 'oppo', 'realme': 'realme', 'OnePlus': 'oneplus', 'motorola': 'motorola', 'Google': 'google',
      'Nothing': 'nothing', 'TECNO': 'transsion', 'Infinix': 'transsion', 'itel': 'transsion', 'HONOR': 'huawei',
      'asus': 'asus', 'HMD Global': 'nokia', 'LAVA': 'lava', 'Fairphone': 'other', '': 'other',
    };
    makers.forEach((maker, family) => expect(askodoxPhoneFamily(maker), family, reason: maker));
    for (final family in {...makers.values}) {
      expect(askodoxBatterySteps.containsKey(family), isTrue, reason: family);
    }
    expect(askodoxPhoneFixSteps('battery', 'samsung', te: false), contains('Sleeping apps'));
    expect(askodoxPhoneFixSteps('battery', 'Redmi', te: true), contains('No restrictions'));
    expect(askodoxPhoneFixSteps('autostart', 'vivo', te: true), contains('Autostart'));
    expect(askodoxPhoneFixSteps('autostart', 'Fairphone', te: false), contains('Auto launch'));
    expect(askodoxPhoneFixSteps('battery', 'Fairphone', te: false), contains('Unrestricted'));
    expect(askodoxPhoneFixSteps('', 'samsung', te: true), '');
    for (final id in ['notifications', 'battery', 'autostart', 'payment_access', 'payment_alive', 'voice', 'voice_language', 'pending_upload']) {
      expect(askodoxPhoneCheckText(id, te: true).$2, isNotEmpty, reason: id);
      expect(askodoxPhoneCheckText(id, te: false).$2, isNotEmpty, reason: id);
    }
  });

  test('a report carries consent, the maker, the build and check states: nothing else', () {
    final report = askodoxPhoneReport(
        const [AskodoxPhoneCheck('battery', 'bad', fix: 'battery'), AskodoxPhoneCheck('voice', 'ok')],
        maker: 'vivo', appBuild: 1705, why: 'payment_voice_missing');
    expect(report, {
      'consent': true,
      'maker': 'vivo',
      'android': '',
      'app_build': '1705',
      'why': 'payment_voice_missing',
      'checks': {'battery': 'bad', 'voice': 'ok'},
    });
  });
}
