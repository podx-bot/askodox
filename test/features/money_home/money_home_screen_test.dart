import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/shopping_mode.dart';
import 'package:podx/features/money_home/money_home_screen.dart';
import 'package:podx/features/money_home/money_home_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {bool seller = false}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp phone
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(askodoxSellerModeProvider.notifier).state = seller;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: AskodoxMoneyHomeScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Buyer Money: own money card + pages and folders like a phone', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('askodoxMoneyHome')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMoneyHomeCard')), findsOneWidget);
    expect(find.text('My money · this month'), findsOneWidget);
    for (final id in ['b.qr', 'b.voice', 'b.bills', 'b.dues', 'b.ordercode', 'b.updates', 'f:shops', 'f:mine']) {
      expect(find.byKey(ValueKey('askodoxMoneyTile-$id')), findsOneWidget, reason: id);
    }
    // Registry keys stay findable on their pages.
    expect(find.byKey(const ValueKey('askodoxShoppingOrderCode')), findsOneWidget);
    // A folder opens its pages.
    await tester.tap(find.byKey(const ValueKey('askodoxMoneyTile-f:shops')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMoneyFolder-shops')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMoneyFolderPage-b.following')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxShoppingFollowing')), findsNothing,
        reason: 'the key is on the tile, the folder holds it');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('press and hold = arrange; "−" hides (never deletes), Hidden brings back, saved per side', (tester) async {
    await _pump(tester);
    await tester.longPress(find.byKey(const ValueKey('askodoxMoneyTile-b.bills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMoneyHomeEditBar')), findsOneWidget);
    // A press-and-release only starts arranging: the page stays where it was.
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
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-bill-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-out-off')), findsOneWidget, reason: 'money sent: off by default');
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-fake-on')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxVoiceKind-bill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-bill-off')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxVoiceKind-fake')), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('askodoxVoiceKind-fake')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxVoiceKindDot-fake-on')), findsOneWidget, reason: 'never switched off');
  });

  testWidgets('Seller Money signed out: asks to sign in (the shop money never shows the personal account)', (tester) async {
    await _pump(tester, seller: true);
    expect(find.byKey(const Key('askodoxMoneyHomeSignIn')), findsOneWidget);
    expect(find.text('My money · this month'), findsNothing);
  });
}
