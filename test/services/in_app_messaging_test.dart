import 'package:flutter_test/flutter_test.dart';
import 'package:podx/services/in_app_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fiam implements AskodoxInAppMessagingBackend {
  final calls = <String>[];

  @override
  Future<bool> init() async => true;
  @override
  Future<void> setSuppressed(bool suppressed) async => calls.add('suppressed=$suppressed');
  @override
  Future<void> setDataCollection(bool enabled) async => calls.add('collect=$enabled');
  @override
  Future<void> trigger(String event) async => calls.add('trigger=$event');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('off until the person opts in: suppressed and nothing collected', () async {
    final fiam = _Fiam();
    final messaging = AskodoxInAppMessaging(fiam, configured: true);
    expect(await messaging.optedIn(), isFalse);
    expect(await messaging.onAppOpen(), isFalse);
    expect(fiam.calls, ['collect=false', 'suppressed=true']);
  });

  test('opted in: at most one trigger per 20 hours', () async {
    final fiam = _Fiam();
    var now = DateTime(2026, 10, 16, 9);
    final messaging = AskodoxInAppMessaging(fiam, configured: true, now: () => now);
    await messaging.setOptIn(true);
    expect(fiam.calls, ['collect=true', 'suppressed=false']);
    expect(await messaging.onAppOpen(), isTrue);
    now = now.add(const Duration(hours: 5));
    expect(await messaging.onAppOpen(), isFalse, reason: 'frequency limit');
    now = now.add(const Duration(hours: 16));
    expect(await messaging.onAppOpen(), isTrue);
    expect(fiam.calls.where((c) => c.startsWith('trigger=')).length, 2);
    await messaging.setOptIn(false);
    expect(fiam.calls.sublist(fiam.calls.length - 2), ['collect=false', 'suppressed=true']);
    now = now.add(const Duration(days: 2));
    expect(await messaging.onAppOpen(), isFalse);
  });

  test('a build without Firebase values never touches Firebase', () async {
    final fiam = _Fiam();
    final messaging = AskodoxInAppMessaging(fiam, configured: false);
    await messaging.setOptIn(true);
    expect(await messaging.onAppOpen(), isFalse);
    expect(fiam.calls, isEmpty);
  });
}
