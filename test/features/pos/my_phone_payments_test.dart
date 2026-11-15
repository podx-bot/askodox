import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/features/pos/data/pos_payment_alerts.dart';
import 'package:podx/features/pos/presentation/my_phone_payments_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.askodox.app/payment_alerts');
  late List<Map<String, Object?>> events;
  late List<MethodCall> calls;
  late Map<String, Object?> lastConfig;
  late Map<String, Object?> status;
  late List<Map<String, Object?>> installed;
  String? lastScope;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    lastConfig = {};
    lastScope = null;
    status = {'listenerAllowed': true};
    installed = [
      {'package': 'com.example.bank', 'label': 'Example Bank'},
      {'package': 'com.phonepe.app', 'label': 'PhonePe'},
      {'package': 'com.google.android.apps.messaging', 'label': 'Messages'},
      {'package': 'com.example.game', 'label': 'Fun Game'},
    ];
    events = [
      {'local_id': 'a1', 'direction': 'in', 'amount_paise': 15000, 'party': 'Ravi', 'source_label': 'PhonePe', 'account': '1234',
       'detected_at': '2026-11-15T10:00:00Z', 'spoken': 'announced'},
      {'local_id': 'a2', 'direction': 'out', 'amount_paise': 2000, 'party': 'Chai Shop', 'source_label': 'Messages',
       'detected_at': '2026-11-15T11:00:00Z', 'spoken': 'seen'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'configure':
          lastConfig = jsonDecode('${(call.arguments as Map)['config']}') as Map<String, Object?>;
          lastScope = (call.arguments as Map)['scope'] as String?;
          return status;
        case 'status':
          return status;
        case 'paymentApps':
          return [
            for (final p in ((call.arguments as Map)['packages'] as List))
              {'package': p, 'installed': installed.any((a) => a['package'] == p), 'batteryUnrestricted': false, 'lastSeenAt': 0}
          ];
        case 'events':
          return jsonEncode(events);
        case 'deleteEvents':
          final ids = (call.arguments as Map)['localIds'] as List?;
          events.removeWhere((e) => ids == null || ids.contains(e['local_id']));
          return 1;
        case 'installedApps':
          return installed;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Widget app() => ProviderScope(
        overrides: [askodoxPaymentAlertsBridgeProvider.overrideWithValue(AskodoxPaymentAlertsBridge(channel))],
        child: const MaterialApp(home: AskodoxMyPhonePaymentsScreen()),
      );

  testWidgets('personal mode: no shop id, credits and debits listed, any row can be deleted', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(lastConfig['business_id'], '', reason: 'no shop = personal mode on the phone');
    expect(lastScope, 'personal', reason: 'My phone keeps its own settings, apart from the shop');
    final apps = lastConfig['apps'] as Map;
    expect(apps.containsKey('com.google.android.apps.messaging'), isTrue, reason: 'the SMS app on this phone is read');
    expect(apps.containsKey('com.example.bank'), isTrue, reason: 'a bank app found on the phone is chosen by itself');
    expect(apps.containsKey('com.phonepe.app'), isTrue);
    expect(apps.containsKey('com.example.game'), isFalse, reason: 'never a non-money app');
    expect(apps.containsKey('net.one97.paytm'), isFalse, reason: 'an app not on this phone is not listed');
    expect((lastConfig['kinds'] as Map)['com.google.android.apps.messaging'], 'sms');
    expect((lastConfig['kinds'] as Map)['com.example.bank'], 'bank');
    expect(find.byKey(const ValueKey('askodoxMineEvent-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMineEvent-a2')), findsOneWidget);
    expect(find.textContaining('+₹150'), findsOneWidget);
    expect(find.textContaining('−₹20'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxMineEventDelete-a2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMineEvent-a2')), findsNothing);
    expect(events.length, 1);
  });

  testWidgets('apps can be removed and added; accounts can be named and deleted; debits switch is saved', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // remove an app
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxMineAppDelete-com.example.bank')));
    await tester.tap(find.byKey(const ValueKey('askodoxMineAppDelete-com.example.bank')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMineConfirmYes')));
    await tester.pumpAndSettle();
    expect((lastConfig['apps'] as Map).containsKey('com.example.bank'), isFalse);
    // ... it is offered again under "found on this phone", never re-added by itself
    expect(find.byKey(const ValueKey('askodoxMineFound-com.example.bank')), findsOneWidget);
    // add an installed app
    await tester.ensureVisible(find.byKey(const Key('askodoxMineAppAdd')));
    await tester.tap(find.byKey(const Key('askodoxMineAppAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMinePick-com.example.bank')).last);
    await tester.pumpAndSettle();
    expect((lastConfig['apps'] as Map)['com.example.bank'], 'Example Bank');
    // name an account, then delete it
    await tester.ensureVisible(find.byKey(const Key('askodoxMineAccountAdd')));
    await tester.tap(find.byKey(const Key('askodoxMineAccountAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxMineAskField')), '1234');
    await tester.tap(find.byKey(const Key('askodoxMineAskSave')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxMineAskField')), 'Savings');
    await tester.tap(find.byKey(const Key('askodoxMineAskSave')));
    await tester.pumpAndSettle();
    expect(find.text('Savings'), findsWidgets);
    expect(find.textContaining('Savings'), findsWidgets, reason: 'the history shows the account name');
    await tester.tap(find.byKey(const ValueKey('askodoxMineAccountDelete-1234')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMineConfirmYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMineAccount-1234')), findsNothing);
    // debits are spoken only after the switch
    expect(lastConfig['announce_debits'], false);
    await tester.ensureVisible(find.byKey(const Key('askodoxMineDebits')));
    await tester.tap(find.byKey(const Key('askodoxMineDebits')));
    await tester.pumpAndSettle();
    expect(lastConfig['announce_debits'], true);
  });

  testWidgets('setup checklist opens each Android page; per-app shop / my phone choice when a shop listens too',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    status = {
      'listenerAllowed': false,
      'batteryUnrestricted': false,
      'enabled': true, // this phone also listens for a shop
      'autostartPage': true,
      'smsApp': 'com.google.android.apps.messaging',
      'maker': 'xiaomi',
    };
    installed = [
      ...installed,
      {'package': 'com.phonepe.app.business', 'label': 'PhonePe Business'},
    ];
    SharedPreferences.setMockInitialValues({'askodox.mine.payalert.v1': jsonEncode({'enabled': true, 'apps': {}, 'setup_done': true})});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMineSetup')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMineStep-access')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMineStep-autostart')), findsOneWidget);
    expect(find.textContaining('No restrictions'), findsWidgets, reason: 'Xiaomi wording for the battery page');
    await tester.tap(find.byKey(const ValueKey('askodoxMineStepGo-access')));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'openListenerSettings'), isTrue);
    await tester.tap(find.byKey(const ValueKey('askodoxMineStepGo-autostart')));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'openAutostartSettings'), isTrue);
    // the SMS app is not chosen yet: the step adds it
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxMineStepGo-sms')));
    await tester.tap(find.byKey(const ValueKey('askodoxMineStepGo-sms')));
    await tester.pumpAndSettle();
    expect((lastConfig['apps'] as Map).containsKey('com.google.android.apps.messaging'), isTrue);
    // found apps: add all
    await tester.ensureVisible(find.byKey(const Key('askodoxMineFoundAll')));
    await tester.tap(find.byKey(const Key('askodoxMineFoundAll')));
    await tester.pumpAndSettle();
    final apps = lastConfig['apps'] as Map;
    expect(apps.containsKey('com.phonepe.app.business'), isTrue);
    expect(apps.containsKey('com.example.bank'), isTrue);
    // business app -> shop by default; the person can move PhonePe to the shop too
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('askodoxMineDest-shop-com.phonepe.app.business'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('askodoxMineDest-mine-com.phonepe.app'))).selected, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxMineDest-shop-com.phonepe.app')));
    await tester.tap(find.byKey(const ValueKey('askodoxMineDest-shop-com.phonepe.app')));
    await tester.pumpAndSettle();
    expect((lastConfig['destinations'] as Map)['com.phonepe.app'], 'shop');
  });
}
