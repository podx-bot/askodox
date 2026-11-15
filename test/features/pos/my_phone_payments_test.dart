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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    lastConfig = {};
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
          return {'listenerAllowed': true};
        case 'status':
          return {'listenerAllowed': true};
        case 'events':
          return jsonEncode(events);
        case 'deleteEvents':
          final ids = (call.arguments as Map)['localIds'] as List?;
          events.removeWhere((e) => ids == null || ids.contains(e['local_id']));
          return 1;
        case 'installedApps':
          return [
            {'package': 'com.example.bank', 'label': 'Example Bank'}
          ];
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
    expect((lastConfig['apps'] as Map).containsKey('com.google.android.apps.messaging'), isTrue, reason: 'bank SMS app is read by default');
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
    await tester.tap(find.byKey(const ValueKey('askodoxMineAppDelete-in.org.npci.upiapp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMineConfirmYes')));
    await tester.pumpAndSettle();
    expect((lastConfig['apps'] as Map).containsKey('in.org.npci.upiapp'), isFalse);
    // add an installed app
    await tester.ensureVisible(find.byKey(const Key('askodoxMineAppAdd')));
    await tester.tap(find.byKey(const Key('askodoxMineAppAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMinePick-com.example.bank')));
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
}
