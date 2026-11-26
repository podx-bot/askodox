import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/shopping_mode.dart';
import 'package:podx/features/money_home/money_home_screen.dart';
import 'package:podx/features/money_home/money_home_store.dart';
import 'package:podx/shared/widgets/chat_pins.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {bool seller = false, String section = 'money'}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp phone
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(askodoxSellerModeProvider.notifier).state = seller;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: AskodoxMoneyHomeScreen(section: section))),
  ));
  await tester.pumpAndSettle();
  return container;
}


/// The Payment voice sheet shows four lines first; the rest (and the ASKODOX lines) sit under "More".
Future<void> _openVoiceMore(WidgetTester tester) async {
  final more = find.byKey(const Key('askodoxVoiceMoreKinds'));
  await tester.scrollUntilVisible(more, 100, scrollable: find.byType(Scrollable).last);
  await tester.tap(more);
  await tester.pumpAndSettle();
}

/// Scroll the sheet until the row is really on screen, then tap it (rows below the fold missed the tap).
Future<void> _tapVoice(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

const _channel = MethodChannel('com.askodox.app/payment_alerts');

/// What the phone was asked (method + its arguments).
final _calls = <MethodCall>[];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      _calls.add(call);
      return switch (call.method) {
        'events' => '[]',
        'voiceKinds' => '{}',
        'setVoiceKinds' => '{}',
        _ => null,
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  testWidgets('Buyer Money: own money card + every page on its own (nothing grouped by the app)', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('askodoxMoneyHome')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMoneyHomeCard')), findsOneWidget);
    expect(find.text('My money · this month'), findsOneWidget);
    // Owner 2026-11-23: Money holds money only ("Account names" is inside My QR / accounts now).
    for (final id in ['b.qr', 'b.voice', 'b.bills', 'b.dues', 'b.apps', 'b.language']) {
      expect(find.byKey(ValueKey('askodoxMoneyTile-$id')), findsOneWidget, reason: id);
    }
    for (final id in ['b.ordercode', 'b.updates', 'b.following', 'b.shopfeed', 'b.accounts']) {
      expect(find.byKey(ValueKey('askodoxMoneyTile-$id')), findsNothing, reason: '$id is not money');
    }
    expect(find.byKey(const ValueKey('askodoxMoneyTile-f:shops')), findsNothing, reason: 'owner 2026-11-22: no app folders');
  });

  testWidgets('owner 2026-11-23: the కొను page holds the buyer pages; its search finds any page of the side', (tester) async {
    await _pump(tester, section: 'side');
    expect(find.byKey(const Key('askodoxSidePage')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBuyPageCard')), findsOneWidget);
    for (final id in ['b.ordercode', 'b.updates', 'b.following', 'b.shopfeed']) {
      expect(find.byKey(ValueKey('askodoxMoneyTile-$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsNothing, reason: 'money stays in Money');
    // Registry keys stay findable on their pages.
    expect(find.byKey(const ValueKey('askodoxShoppingOrderCode')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxShoppingFollowing')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxSidePageSearch')), 'bill');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxSidePageHit-b.bills')), findsOneWidget, reason: 'a Money page is found too');
    expect(find.text('in Money'), findsWidgets);
  });

  testWidgets('folders an earlier version made by itself come apart; the person\'s own folders stay', (tester) async {
    SharedPreferences.setMockInitialValues({
      askodoxMoneyLayoutKey(false): jsonEncode({
        'v': 1,
        'entries': [
          {'folder': 'shops', 'name': '', 'children': ['b.bills', 'b.dues']},
          {'folder': 'u1', 'name': 'Mine', 'children': ['b.apps', 'b.language']},
        ],
        'hidden': [],
      }),
    });
    await _pump(tester);
    expect(find.byKey(const ValueKey('askodoxMoneyTile-f:shops')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMoneyTile-f:u1')), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
  });

  testWidgets('a page in a folder is dragged OUT onto the screen (phone style)', (tester) async {
    SharedPreferences.setMockInitialValues({
      askodoxMoneyLayoutKey(false): jsonEncode({
        'v': 1,
        'entries': [
          {'folder': 'u1', 'name': 'Two', 'children': ['b.apps', 'b.language']},
        ],
        'hidden': [],
      }),
    });
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTile-f:u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyFolder-u1')), findsOneWidget);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('askodoxMoneyFolderPage-b.apps'))));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.moveTo(const Offset(180, 700));
    await tester.pump();
    await g.moveTo(const Offset(184, 706));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyFolder-u1')), findsNothing, reason: 'the folder closed');
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.apps')), findsOneWidget, reason: 'now on the screen');
    expect(find.byKey(const ValueKey('askodoxMoneyTile-f:u1')), findsNothing, reason: 'one page left = no folder');
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.language')), findsOneWidget);
    final saved = (await SharedPreferences.getInstance()).getString(askodoxMoneyLayoutKey(false))!;
    expect(saved, isNot(contains('"folder"')));
  });

  testWidgets('owner 2026-11-23: a page dropped ON another page takes that place -- it never becomes a folder', (tester) async {
    await _pump(tester);
    final first = find.byKey(const ValueKey('askodoxMoneyTile-b.qr'));
    final last = find.byKey(const ValueKey('askodoxMoneyTile-b.language'));
    final g = await tester.startGesture(tester.getCenter(last));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0, 150)); // away from its own place: arranging starts
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final place = tester.getCenter(first);
    await g.moveTo(place + const Offset(-2, -2));
    await tester.pump();
    await g.moveTo(place); // the very middle of the other page: this used to make a folder
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(const ValueKey('askodoxMoneyTile-b.language'))), place, reason: 'it sits there');
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.qr')), findsOneWidget, reason: 'the other page only shifted');
    final saved = (await SharedPreferences.getInstance()).getString(askodoxMoneyLayoutKey(false))!;
    expect(saved, isNot(contains('"folder"')));
  });

  testWidgets('a folder is the person\'s own choice: page menu -> "Put in a folder" -> with which page', (tester) async {
    await _pump(tester);
    await tester.longPress(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyMenu-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyFolderPick-b.dues')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.dues')), findsNothing);
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString(askodoxMoneyLayoutKey(false))!) as Map;
    final folder = (saved['entries'] as List).whereType<Map>().firstWhere((e) => e['folder'] != null);
    expect(folder['children'], ['b.dues', 'b.bills']);
  });

  testWidgets('press, hold and let go = the page\'s menu: put it above the Home chat (the five shortcuts)', (tester) async {
    final container = await _pump(tester);
    await tester.longPress(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyMenu-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMoneyMenu-arrange')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMoneyHomeEditBar')), findsNothing, reason: 'letting go does not start arranging');
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyMenu-pin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxChatPinAdd')));
    await tester.pumpAndSettle();
    final pin = container.read(askodoxChatPinsProvider).pins.single;
    expect(pin.id, 'money:me:b.bills');
    expect(pin.route, '/me/bills');
  });

  testWidgets('menu "Move" = arrange; "−" hides (never deletes), Hidden brings back, saved per side', (tester) async {
    await _pump(tester);
    await tester.longPress(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyMenu-arrange')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMoneyHomeEditBar')), findsOneWidget);
    // A press-and-release never moves the page.
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTileHide-b.bills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsNothing);
    expect(find.text('Hidden (1)'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(askodoxMoneyLayoutKey(false)), contains('b.bills'));
    expect(prefs.getString(askodoxMoneyLayoutKey(true)), isNull, reason: 'the Seller screens are separate');
    await tester.tap(find.byKey(const Key('askodoxMoneyHomeHidden')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyRestore-b.bills')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMoneyHomeDone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMoneyHomeEditBar')), findsNothing);
  });

  testWidgets('Payment voice folder: 11 kinds on my phone, tap = on / off, fake warning locked on', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTile-b.voice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPaymentVoiceSheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxVoiceKind-bill')), findsNothing, reason: 'four lines first, the rest under More');
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-in-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxVoiceKindLocked-fake')), findsOneWidget, reason: 'the lock says why it cannot change');
    await _openVoiceMore(tester);
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-bill-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-out-off')), findsOneWidget, reason: 'money sent: off by default');
    await _tapVoice(tester, const ValueKey('askodoxVoiceKind-bill'));
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-bill-off')), findsOneWidget);
    final saved = _calls.lastWhere((c) => c.method == 'setVoiceKinds').arguments as Map;
    expect(saved['scope'], 'personal');
    expect(jsonDecode('${saved['kinds']}')['bill'], isFalse);
    expect((jsonDecode('${saved['kinds']}') as Map).containsKey('fake'), isFalse, reason: 'the warning is never switched off');
    // ▶ plays the real words of that kind on the phone.
    await _tapVoice(tester, const ValueKey('askodoxVoiceKindPlay-refund'));
    expect(_calls.where((c) => c.method == 'speakKind').single.arguments, containsPair('kind', 'refund'));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxVoiceKind-fake')), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('askodoxVoiceKind-fake')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-fake-on')), findsOneWidget, reason: 'never switched off');
  });

  testWidgets('Payment voice folder: a refused save puts the switch back and says so (pilot finding 2026-11-26)', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTile-b.voice')));
    await tester.pumpAndSettle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      _calls.add(call);
      if (call.method == 'setVoiceKinds') throw PlatformException(code: 'save_failed');
      return call.method == 'events' ? '[]' : '{}';
    });
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-in-on')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxVoiceKind-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-in-on')), findsOneWidget, reason: 'not kept -> still on');
    expect(find.byKey(const Key('askodoxVoiceSaveFailed')), findsOneWidget);
  });

  testWidgets('Payment voice folder: ASKODOX lines are all on by default and each can be switched off', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTile-b.voice')));
    await tester.pumpAndSettle();
    await _openVoiceMore(tester);
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxVoiceKind-customer')), 100, scrollable: list);
    expect(find.byKey(const Key('askodoxPaymentVoiceBrand')), findsOneWidget);
    for (final id in ['tune', 'hello', 'night', 'customer']) {
      expect(find.byKey(ValueKey('askodoxVoiceKindDot-$id-on')), findsOneWidget, reason: '$id: owner 2026-11-23, all ON');
    }
    await _tapVoice(tester, const ValueKey('askodoxVoiceKind-customer'));
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-customer-off')), findsOneWidget);
    final saved = jsonDecode('${(_calls.lastWhere((c) => c.method == 'setVoiceKinds').arguments as Map)['kinds']}') as Map;
    expect(saved['customer'], isFalse);
    expect(saved['night'], isTrue);
    // ▶ plays the same words the phone says at night.
    await _tapVoice(tester, const ValueKey('askodoxVoiceKindPlay-night'));
    expect(_calls.where((c) => c.method == 'speakKind').single.arguments, containsPair('kind', 'night'));
  });

  testWidgets('Seller Money signed out: asks to sign in (the shop money never shows the personal account)', (tester) async {
    await _pump(tester, seller: true);
    expect(find.byKey(const Key('askodoxMoneyHomeSignIn')), findsOneWidget);
    expect(find.text('My money · this month'), findsNothing);
  });
}
