import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_payment_alerts.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/domain/payment_alert_setup.dart';
import 'package:podx/features/pos/presentation/pos_payment_alerts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls.add('$method $path');
    bodies['$method $path'] = body;
    final out = reply(method, path, body);
    if (out is ApiFailure) return ApiError<T>(out);
    return ApiSuccess(out as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

const _channel = MethodChannel('com.askodox.app/payment_alerts');

Map<String, Object?> _settings({bool enabled = true}) => {
      'enabled': enabled,
      'feature_on': true,
      'can_edit': true,
      'language': 'te',
      'voice': 'female',
      'rate_pct': 100,
      'volume_pct': 100,
      'quiet_start': '',
      'quiet_end': '',
      'roles': ['manager', 'cashier'],
      'all_roles': ['manager', 'cashier', 'accountant', 'waiter', 'kitchen'],
      'apps': {'com.phonepe.app.business': 'PhonePe Business'},
    };

Map<String, Object?> _event(String id, {bool mine = true, int amount = 50000, String status = 'notification_unverified'}) => {
      'id': id,
      'amount_paise': amount,
      'source_label': 'PhonePe Business',
      'reference_tail': '7890',
      'status': status,
      'verification': 'notification_only',
      'detected_at': '2026-10-26T04:51:00Z',
      'receiving_device': 'Counter phone',
      'reported_by_me': mine,
      'test': false,
      'duplicates': 0,
      'delivery_pending': 1,
      'acks': mine
          ? [
              {'device': 'Counter phone', 'mine': true, 'state': 'announced'}
            ]
          : <Object?>[],
      'announcement': {'te': '500 రూపాయల పేమెంట్ నోటిఫికేషన్ వచ్చింది. బ్యాంకులో నిర్ధారించుకోండి.', 'en': 'x', 'hi': 'x'},
    };

Widget _app(_Api api, Widget home) => ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: MaterialApp(home: home),
    );

void main() {
  late List<MethodCall> native;
  late List<Map<String, Object?>> localEvents;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    native = [];
    localEvents = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'status' || 'configure' => {
            'listenerAllowed': false,
            'ttsLanguageOk': true,
            'audio': {'output': 'bluetooth', 'bluetoothName': 'JBL Go', 'mediaVolumePct': 80},
          },
        'events' => jsonEncode(localEvents),
        'speakTest' || 'audioRoute' => {'output': 'bluetooth', 'bluetoothName': 'JBL Go', 'mediaVolumePct': 80},
        'speakRemote' => 'spoken',
        _ => true,
      };
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  test('rupees use Indian grouping and statuses never say money was received', () {
    expect(askodoxRupees(12345050), '₹1,23,450.50');
    expect(askodoxRupees(50000), '₹500');
    expect(askodoxRupees(null), '₹—');
    expect(askodoxPaymentStatusLabel({'status': 'notification_unverified'}).$1, 'Notification detected — unverified');
    expect(askodoxPaymentStatusLabel({'status': 'ambiguous'}).$1, contains('Ambiguous'));
    expect(askodoxPaymentStatusLabel({'status': 'notification_unverified', 'test': true}).$1, 'Test alert');
    final csv = askodoxPaymentAlertsCsv([_event('e1')]);
    expect(csv, contains('500.00'));
    expect(csv, contains('Not bank-verified'));
    expect(csv, isNot(contains('Counter phone')), reason: 'no device / person data in the export');
  });

  test('pending phone detections are sent once and marked; refusals are kept with the code', () async {
    localEvents = [
      {'local_id': 'l1', 'client_event_id': 'pkg|k1|500|1', 'source_app': 'com.phonepe.app.business', 'amount_paise': 50000,
        'detected_at': '2026-10-26T04:51:00Z', 'spoken': 'announced'},
      {'local_id': 'l2', 'client_event_id': 'pkg|k2', 'source_app': 'x', 'server_id': 'done'},
      {'local_id': 'l3', 'client_event_id': 'sim', 'source_app': 'askodox.test', 'test': true},
    ];
    final api = _Api((m, p, b) => {'id': 'ppe_1'});
    final sent = await askodoxSyncPaymentAlerts(AskodoxPosRepository(api, authToken: 't'), AskodoxPaymentAlertsBridge(), 'b1', 'pad_1');
    expect(sent, 1);
    final body = api.bodies['POST /api/pos/businesses/b1/payment-alerts/events'] as Map;
    expect(body['amount_paise'], 50000);
    expect(body['device_id'], 'pad_1');
    expect(body['spoken'], 'announced');
    expect(body.containsKey('status'), isFalse, reason: 'the app never sends a verification claim');
    final mark = native.firstWhere((c) => c.method == 'markUploaded');
    expect((mark.arguments as Map)['serverId'], 'ppe_1');
  });

  testWidgets('screen shows status, unverified history and asks consent before opening Android settings', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/settings')) return m == 'PUT' ? {..._settings(), ...(b as Map).cast<String, Object?>()} : _settings();
      if (p.endsWith('/payment-alerts/devices')) {
        return {'device_id': 'pad_1', 'devices': [
          {'id': 'pad_1', 'label': 'Phone abcd', 'mine': true, 'role': 'owner', 'listener_on': false, 'revoked': false}
        ]};
      }
      if (p.endsWith('/payment-alerts/events')) {
        return {'events': [_event('e1')], 'last_24h': {'count': 1, 'notified_total_paise': 50000}};
      }
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('askodoxPayAlertStatus')), findsOneWidget);
    expect(find.textContaining('Bluetooth speaker: JBL Go'), findsOneWidget);
    expect(find.textContaining('Notification access off'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPayAlertEvent-e1')), findsOneWidget);
    expect(find.text('₹500 · PhonePe Business'), findsOneWidget);
    expect(find.text('Notification detected — unverified'), findsOneWidget);
    expect(find.textContaining('Voice: Spoken'), findsOneWidget);
    expect(find.textContaining('(unverified)'), findsOneWidget);
    final configure = native.lastWhere((c) => c.method == 'configure');
    final cfg = jsonDecode('${(configure.arguments as Map)['config']}') as Map;
    expect(cfg['enabled'], isTrue);
    expect(cfg['business_id'], 'b1');
    expect(cfg['device_id'], 'pad_1');
    expect((cfg['apps'] as Map).keys, contains('com.phonepe.app.business'));

    await tester.tap(find.byKey(const Key('askodoxPayAlertGrant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertConsent')), findsOneWidget);
    expect(native.where((c) => c.method == 'openListenerSettings'), isEmpty, reason: 'never opened without consent');
    await tester.tap(find.byKey(const Key('askodoxPayAlertConsentYes')));
    await tester.pumpAndSettle();
    expect(native.where((c) => c.method == 'openListenerSettings'), hasLength(1));

    await tester.tap(find.byKey(const Key('askodoxPayAlertSpeakerTest')));
    await tester.pumpAndSettle();
    expect(native.where((c) => c.method == 'speakTest'), hasLength(1));

    await tester.tap(find.byKey(const Key('askodoxPayAlertEnable')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/settings'], {'enabled': false});
  });

  testWidgets('a staff phone speaks an alert another phone detected and acknowledges it', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var round = 0;
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/settings')) return {..._settings(), 'can_edit': false};
      if (p.endsWith('/payment-alerts/devices')) {
        return {'device_id': 'pad_2', 'devices': [
          {'id': 'pad_2', 'label': 'Cashier', 'mine': true, 'role': 'cashier', 'speaks_remote': true, 'revoked': false}
        ]};
      }
      if (p.endsWith('/payment-alerts/events') && m == 'GET') {
        round++;
        return {'events': round == 1 ? <Object?>[] : [_event('e9', mine: false)], 'last_24h': {'count': 1, 'notified_total_paise': 50000}};
      }
      if (p.endsWith('/ack')) return _event('e9', mine: false);
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration(seconds: 1))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertSettings')), findsNothing, reason: 'staff cannot change settings');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final spoke = native.where((c) => c.method == 'speakRemote').toList();
    expect(spoke, hasLength(1));
    expect((spoke.first.arguments as Map)['text'], contains('బ్యాంకులో నిర్ధారించుకోండి'));
    expect(api.bodies['POST /api/pos/businesses/b1/payment-alerts/events/e9/ack'], {'device_id': 'pad_2', 'state': 'announced'});
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(native.where((c) => c.method == 'speakRemote'), hasLength(1), reason: 'never announced twice');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('server not updated yet: phone-only mode still listens and speaks on this phone', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    localEvents = [
      {'local_id': 'l1', 'source_label': 'PhonePe Business', 'amount_paise': 20000, 'status': 'notification_unverified',
        'detected_at': '2026-10-26T04:51:00Z', 'spoken': 'announced'},
    ];
    final api = _Api((m, p, b) => const ApiFailure(ApiFailureType.notFound, statusCode: 404, message: 'Not Found'));
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertPhoneOnly')), findsOneWidget);
    expect(find.text('₹200 · PhonePe Business'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPayAlertStaffTest')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxPayAlertEnable')));
    await tester.pumpAndSettle();
    final cfg = jsonDecode('${(native.lastWhere((c) => c.method == 'configure').arguments as Map)['config']}') as Map;
    expect(cfg['enabled'], isTrue);
    expect(cfg['token'], '', reason: 'phone-only never uploads');
    expect((cfg['apps'] as Map).keys, contains('com.phonepe.app.business'));
  });

  testWidgets('a downloaded APK without the listener says so instead of offering access', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'status' || 'configure' => {'listenerDeclared': false, 'listenerAllowed': false, 'audio': {'output': 'phone', 'mediaVolumePct': 60}},
        'events' => '[]',
        _ => true,
      };
    });
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/settings')) return _settings();
      if (p.endsWith('/payment-alerts/devices')) return {'device_id': 'pad_1', 'devices': <Object?>[]};
      if (p.endsWith('/payment-alerts/events')) return {'events': <Object?>[], 'last_24h': {'count': 0, 'notified_total_paise': 0}};
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertNeedsPlayBuild')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPayAlertGrant')), findsNothing);
    expect(find.byKey(const Key('askodoxPayAlertSpeakerTest')), findsOneWidget);
  });

  testWidgets('owner connects their own Razorpay; the webhook URL is shown, secrets are never shown back', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/provider') && m == 'PUT') {
        return {'connected': true, 'mode': 'test', 'key_id_tail': 'F123', 'webhook_url': 'https://x/api/pos/payment-webhooks/razorpay/b1'};
      }
      if (p.endsWith('/payment-alerts/provider')) return {'connected': false, 'secrets_ready': true};
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const Scaffold(body: SingleChildScrollView(child: AskodoxPosProviderCard(businessId: 'b1')))));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'rzp_test_ABCDEF123');
    await tester.enterText(fields.at(1), 'secret-good-123');
    await tester.enterText(fields.at(2), 'whsec-test-12345');
    await tester.tap(find.byKey(const Key('askodoxPayAlertConnect')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/provider'],
        {'key_id': 'rzp_test_ABCDEF123', 'key_secret': 'secret-good-123', 'webhook_secret': 'whsec-test-12345'});
    expect(find.byKey(const Key('askodoxPayAlertProviderOn')), findsOneWidget);
    expect(find.text('https://x/api/pos/payment-webhooks/razorpay/b1'), findsOneWidget);
    expect(find.textContaining('secret-good-123'), findsNothing);
  });

  test('timeline shows where the seconds went (paid -> server -> phone -> voice)', () {
    final e = {
      'status': 'provider_verified',
      'detected_at': '2026-10-27T01:31:05Z',
      'received_at': '2026-10-27T01:31:48Z',
      'acks': [
        {'mine': true, 'state': 'delivered', 'at': '2026-10-27T01:31:49Z'},
      ],
    };
    final line = askodoxPayAlertTimeline(e, false);
    expect(line, startsWith('Paid '));
    expect(line, contains(' → Server '));
    expect(line, contains(' → Phone got '));
    expect(askodoxPayAlertClock('2026-10-27T01:31:05Z'), matches(RegExp(r'^\d{1,2}:\d{2}:05 (AM|PM)$')));
    expect(askodoxPayAlertTimeline({'detected_at': '2026-10-27T01:31:05Z'}, false), isEmpty);
  });

  test('setup steps: only what this phone can do, in order, re-checked from the phone', () {
    const phonepe = 'com.phonepe.app.business';
    final apps = [
      {'package': phonepe, 'installed': true, 'batteryUnrestricted': false, 'lastSeenAt': 0},
      {'package': 'net.one97.paytm', 'installed': false},
    ];
    final steps = askodoxPayAlertSetupSteps(
        status: {'listenerAllowed': false, 'batteryUnrestricted': false}, settings: _settings(enabled: false), apps: apps, confirmed: {});
    expect(steps.map((s) => s.id), ['shop_on', 'access', 'battery', 'app_notifications:$phonepe', 'app_battery:$phonepe', 'sound']);
    expect(steps.where((s) => s.done), isEmpty);
    expect(askodoxPayAlertNextStep(steps, {'shop_on'})!.id, 'access', reason: '"Not now" moves to the next question');

    final later = askodoxPayAlertSetupSteps(
        status: {'listenerAllowed': true},
        settings: _settings(),
        apps: [
          {'package': phonepe, 'installed': true, 'batteryUnrestricted': true, 'lastSeenAt': 1762900000000}
        ],
        confirmed: {'sound'});
    expect(later.every((s) => s.done), isTrue, reason: 'a notification already seen from the app proves it reaches the phone');
    expect(askodoxPayAlertNextStep(later, {}), isNull);

    final sideloaded = askodoxPayAlertSetupSteps(
        status: {'listenerDeclared': false}, settings: _settings(), apps: apps, confirmed: {});
    expect(sideloaded.map((s) => s.kind), ['shop_on', 'battery', 'sound'], reason: 'no reading steps without the listener');
    expect(askodoxPayAlertSetupSteps(status: {'unavailable': true}, settings: _settings(), apps: apps, confirmed: {}), isEmpty);
    final staff = askodoxPayAlertSetupSteps(
        status: {}, settings: {..._settings(enabled: false), 'can_edit': false}, apps: const [], confirmed: {});
    expect(staff.first.ownerOnly, isTrue);
    final (q, how) = askodoxPayAlertStepText(steps[4], te: false, maker: 'samsung');
    expect(q, contains('PhonePe Business'));
    expect(how, contains('Manage app if unused'));
  });

  testWidgets('setup asks one thing at a time and opens exactly that Android page', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const phonepe = 'com.phonepe.app.business';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'status' || 'configure' => {
            'listenerAllowed': true,
            'batteryUnrestricted': false,
            'maker': 'samsung',
            'audio': {'output': 'phone', 'mediaVolumePct': 70},
          },
        'paymentApps' => [
            {'package': phonepe, 'installed': true, 'batteryUnrestricted': false, 'lastSeenAt': 0}
          ],
        'events' => '[]',
        'speakTest' || 'audioRoute' => {'output': 'phone', 'mediaVolumePct': 70},
        _ => true,
      };
    });
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/settings')) {
        return {..._settings(), 'razorpay_signup_url': 'https://razorpay.com/partners/signup/?ref=askodox'};
      }
      if (p.endsWith('/payment-alerts/devices')) return {'device_id': 'pad_1', 'devices': <Object?>[]};
      if (p.endsWith('/payment-alerts/events')) return {'events': <Object?>[], 'last_24h': {'count': 0, 'notified_total_paise': 0}};
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('askodoxPayAlertRazorpaySignup')), findsOneWidget, reason: 'owner sees ASKODOX partner sign-up');
    expect(find.text('Stop the phone from putting ASKODOX to sleep'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupOk')));
    await tester.pumpAndSettle();
    final own = native.lastWhere((c) => c.method == 'openAppDetails');
    expect((own.arguments as Map).containsKey('package'), isFalse, reason: 'Samsung: ASKODOX own app page');

    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupLater')));
    await tester.pumpAndSettle();
    expect(find.text('Keep PhonePe Business notifications on'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupOk')));
    await tester.pumpAndSettle();
    expect((native.lastWhere((c) => c.method == 'openAppNotificationSettings').arguments as Map)['package'], phonepe);

    expect(find.text('Stop the phone from putting PhonePe Business to sleep'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupOk')));
    await tester.pumpAndSettle();
    expect((native.lastWhere((c) => c.method == 'openAppDetails').arguments as Map)['package'], phonepe);

    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupLater')));
    await tester.pumpAndSettle();
    expect(find.text('Sound test'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupOk')));
    await tester.pumpAndSettle();
    expect(native.where((c) => c.method == 'speakTest'), hasLength(1));
    await tester.tap(find.byKey(const Key('askodoxPayAlertSetupHeardYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertSetupDone')), findsOneWidget);
    expect(find.textContaining('Setup 4/6'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(askodoxPayAlertSetupConfirmedKey), ['app_notifications:$phonepe', 'sound']);
  });

  testWidgets('each person picks who hears their payments; a listener mutes / pauses on their own phone', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var share = <String, Object?>{'mode': 'all', 'listeners': <Object?>[]};
    final people = [
      {'ref': 'me1', 'name': '', 'role': 'owner', 'me': true},
      {'ref': 'r2', 'name': 'Ravi', 'role': 'cashier', 'me': false},
    ];
    final api = _Api((m, p, b) {
      if (p.endsWith('/payment-alerts/share')) share = (b as Map).cast<String, Object?>();
      if (p.endsWith('/payment-alerts/settings') || p.endsWith('/payment-alerts/share') || p.endsWith('/payment-alerts/listening')) {
        return {..._settings(), 'people': people, 'my_share': share, 'my_listening': <String, Object?>{}};
      }
      if (p.endsWith('/payment-alerts/devices')) return {'device_id': 'pad_1', 'devices': <Object?>[]};
      if (p.endsWith('/payment-alerts/events')) return {'events': <Object?>[], 'last_24h': {'count': 0, 'notified_total_paise': 0}};
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosPaymentAlertsScreen(businessId: 'b1', pollEvery: Duration.zero)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('askodoxPayAlertSharing')), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPayAlertShare-none')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/share'], {'mode': 'none', 'listeners': <Object?>[]});

    await tester.tap(find.byKey(const ValueKey('askodoxPayAlertShare-some')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPayAlertShareTo-r2')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/share'], {'mode': 'some', 'listeners': ['r2']});

    await tester.tap(find.byKey(const ValueKey('askodoxPayAlertHear-r2')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/listening'], {'source': 'r2', 'muted': true});
    await tester.tap(find.byKey(const ValueKey('askodoxPayAlertPause-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 hour').last);
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/payment-alerts/listening'], {'source': 'r2', 'pause_minutes': 60});
  });
}
