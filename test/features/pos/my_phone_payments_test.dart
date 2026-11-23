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
        case 'correctEvent':
          final a = call.arguments as Map;
          final row = events.firstWhere((e) => e['local_id'] == a['localId']);
          if (a['choice'] == 'none') {
            row['excluded'] = true;
            row['doubt'] = 'not_payment';
          } else {
            row['direction'] = a['choice'];
            row.remove('excluded');
            row.remove('doubt');
          }
          return {'ok': true, 'learned': true};
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

  testWidgets('a row shows the message it was read from; "wrong" fixes it; set-aside rows never count', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final today = DateTime.now().toUtc().toIso8601String();
    events
      ..clear()
      ..addAll([
        // Owner 2026-11-21: the bank SMS said +3,000; the PhonePe row read it as minus -> set aside with ❓.
        {'local_id': 'b1', 'direction': 'in', 'amount_paise': 300000, 'party': 'KOTA SRINIVAS', 'source_label': 'Messages',
         'bank_confirmed': true, 'detected_at': today, 'spoken': 'announced', 'raw_title': 'AX-ICICIT-S',
         'raw_text': 'ICICI Bank Acct XX321 credited with Rs 3,000.00 from KOTA SRINIVAS'},
        {'local_id': 'b2', 'direction': 'out', 'amount_paise': 300000, 'source_label': 'PhonePe', 'detected_at': today,
         'spoken': 'skipped_bank', 'excluded': true, 'doubt': 'bank_opposite', 'raw_text': 'Sent ₹3,000 to your ICICI account'},
        // A bill message is explained (never money): ℹ️ + why it came.
        {'local_id': 'b3', 'direction': 'info', 'info': 'bill', 'excluded': true, 'amount_paise': 308100, 'party': 'AIRTEL',
         'source_label': 'Messages', 'detected_at': today, 'spoken': 'none', 'raw_text': 'Your Airtel bill of Rs 3081 has been generated'},
      ]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('❓'), findsWidgets, reason: 'the set-aside row is marked');
    expect(find.textContaining('పోయింది ₹0').evaluate().isNotEmpty || find.textContaining('out ₹0').evaluate().isNotEmpty, isTrue,
        reason: 'a set-aside debit never counts in the totals');
    expect(find.textContaining('ℹ️'), findsWidgets, reason: 'the bill message is shown as a notice');
    expect(find.textContaining('బిల్ వచ్చింది').evaluate().isNotEmpty || find.textContaining('Bill generated').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining('వచ్చింది ₹3,000').evaluate().isNotEmpty || find.textContaining('in ₹3,000').evaluate().isNotEmpty, isTrue,
        reason: 'only the bank-confirmed +3,000 counts; the bill and the set-aside row do not');
    await tester.tap(find.byKey(const ValueKey('askodoxMineEvent-b2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent ₹3,000 to your ICICI account'), findsOneWidget, reason: 'the message the row was read from');
    await tester.tap(find.byKey(const Key('askodoxMineRowCorrect-in')));
    await tester.pumpAndSettle();
    final call = calls.lastWhere((c) => c.method == 'correctEvent');
    expect((call.arguments as Map)['localId'], 'b2');
    expect((call.arguments as Map)['choice'], 'in');
    expect(events.firstWhere((e) => e['local_id'] == 'b2')['direction'], 'in');
  });

  testWidgets('owner 2026-11-23: a message in new words is ASKED about (came in / went out / not a payment), shape share can be stopped',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final today = DateTime.now().toUtc().toIso8601String();
    events
      ..clear()
      ..add({'local_id': 'u1', 'direction': 'info', 'info': 'unread', 'excluded': true, 'amount_paise': 44800,
        'source_label': 'Messages', 'detected_at': today, 'spoken': 'announced', 'raw_title': 'AD-NEWBNK-S',
        'raw_text': 'INR 448.00 Debit to A/c XX1234 thru UPI ref 532012345678 towards OTHER SHOP', 'sender_key': 'sms:NEWBNK'});
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('❓'), findsWidgets, reason: 'a message the phone could not read is marked, never hidden');
    expect(find.textContaining('అర్థం కాలేదు').evaluate().isNotEmpty || find.textContaining('Could not read').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining('వెళ్ళింది ₹0').evaluate().isNotEmpty || find.textContaining('పోయింది ₹0').evaluate().isNotEmpty ||
        find.textContaining('out ₹0').evaluate().isNotEmpty, isTrue, reason: 'an unread message is never counted as money');
    await tester.tap(find.byKey(const ValueKey('askodoxMineEvent-u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMineRowCorrect-in')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMineRowCorrect-out')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMineRowCorrect-none')), findsOneWidget, reason: 'all three answers are offered');
    expect(find.byKey(const Key('askodoxMineShareShapes')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMineShareShapes')));
    await tester.pumpAndSettle();
    expect(lastConfig['share_shapes'], isFalse, reason: 'the person can stop the shape going to ASKODOX');
    await tester.tap(find.byKey(const Key('askodoxMineRowCorrect-out')));
    await tester.pumpAndSettle();
    final call = calls.lastWhere((c) => c.method == 'correctEvent');
    expect((call.arguments as Map)['localId'], 'u1');
    expect((call.arguments as Map)['choice'], 'out');
  });

  testWidgets('apps can be removed and added; accounts can be named and deleted; debits switch is saved', (tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // The apps / accounts / language settings live under "More settings" (collapsed by default).
    await tester.ensureVisible(find.byKey(const Key('askodoxMineMore')));
    await tester.tap(find.byKey(const Key('askodoxMineMore')));
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
    // name an account (bank, last digits + name), then delete it
    await tester.ensureVisible(find.byKey(const Key('askodoxMineAccountAdd')));
    await tester.tap(find.byKey(const Key('askodoxMineAccountAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxPlaceTail')), '1234');
    await tester.enterText(find.byKey(const Key('askodoxPlaceName')), 'Savings');
    await tester.ensureVisible(find.byKey(const Key('askodoxPlaceSave')));
    await tester.tap(find.byKey(const Key('askodoxPlaceSave')));
    await tester.pumpAndSettle();
    expect(find.text('Savings'), findsWidgets);
    expect(find.textContaining('Savings'), findsWidgets, reason: 'the history shows the account name');
    expect((lastConfig['account_names'] as Map)['1234'], 'Savings', reason: 'the voice can say the account name');
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxMineAccountDelete-bank:1234')));
    await tester.tap(find.byKey(const ValueKey('askodoxMineAccountDelete-bank:1234')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMineConfirmYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMineAccount-bank:1234')), findsNothing);
    // debits are spoken only after the switch
    expect(lastConfig['announce_debits'], false);
    await tester.ensureVisible(find.byKey(const Key('askodoxMineDebits')));
    await tester.tap(find.byKey(const Key('askodoxMineDebits')));
    await tester.pumpAndSettle();
    expect(lastConfig['announce_debits'], true);
  });

  testWidgets('setup checklist opens each Android page; per-app shop / my phone choice when a shop listens too',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
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
    // The apps / accounts / language settings live under "More settings" (collapsed by default).
    await tester.ensureVisible(find.byKey(const Key('askodoxMineMore')));
    await tester.tap(find.byKey(const Key('askodoxMineMore')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMineDest-shop-com.phonepe.app')));
    await tester.pumpAndSettle();
    expect((lastConfig['destinations'] as Map)['com.phonepe.app'], 'shop');
  });

  test('a bill that came with a last date says the date; without one it says "bill generated"', () {
    final dated = askodoxNoticeNote({'info': 'bill', 'due_date': '2026-12-05'})!;
    expect(dated.$1, contains('05-12-2026'));
    expect(dated.$2, contains('05-12-2026'));
    expect(askodoxNoticeNote({'info': 'bill'})!.$1, contains('Bill generated'));
    expect(askodoxNoticeNote({'info': 'bill', 'due_date': 'soon'})!.$1, contains('Bill generated'));
  });
}
