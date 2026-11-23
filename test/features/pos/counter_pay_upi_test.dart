import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_repository.dart' show AskodoxJson;
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';

// Owner 2026-11-24 (counter bill pay sheet): "UPI select చేస్తే select అవ్వట్లేదు" -- Cash ₹230 was already added (left ₹0),
// so picking UPI changed nothing. UPI must take over, and the shop's own QR shows right there for the customer to scan.
Future<void> _open(WidgetTester tester, Future<(String, String)?> Function()? upi) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<List<AskodoxJson>>(
            context: context,
            isScrollControlled: true,
            builder: (_) => AskodoxPosPaymentSheet(total: 23000, allowCredit: false, te: false, shopUpi: upi),
          ),
          child: const Text('PAY'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('PAY'));
  await tester.pumpAndSettle();
}

void main() {
  test('the default UPI is the one marked default, else the first; bank accounts never', () {
    expect(askodoxDefaultUpi(const []), isNull);
    expect(askodoxDefaultUpi(const [{'kind': 'bank', 'upi_id': ''}]), isNull);
    expect(askodoxDefaultUpi(const [
      {'kind': 'upi', 'upi_id': 'a@ok', 'payee_name': 'A'},
      {'kind': 'upi', 'upi_id': 'b@ok', 'payee_name': 'B', 'is_default': true},
    ]), ('b@ok', 'B'));
  });

  testWidgets('UPI after an added cash payment moves it to UPI and shows the shop QR', (tester) async {
    var asked = 0;
    await _open(tester, () async {
      asked++;
      return ('shop@okaxis', 'Ravi Biryani');
    });
    expect(find.byKey(const Key('askodoxPosPayQr')), findsNothing, reason: 'no QR before UPI is chosen');
    expect(asked, 0, reason: 'nothing fetched for a cash bill');
    await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
    await tester.pumpAndSettle();
    expect(find.text('Cash ₹230.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosPayWay-upi')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('askodoxPosPayWay-upi'))).selected, isTrue);
    expect(find.text('UPI ₹230.00'), findsOneWidget, reason: 'the one payment follows the way picked');
    expect(find.text('Cash ₹230.00'), findsNothing);
    expect(find.byKey(const Key('askodoxPosPayQr')), findsOneWidget);
    expect(asked, 1);
  });

  testWidgets('a wrong payment can be taken off, and no UPI saved offers to add one', (tester) async {
    await _open(tester, () async => null);
    await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosPayment-0')), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosPayment-0')), findsNothing);
    expect(find.textContaining('left ₹230.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosPayWay-upi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosPayQr')), findsNothing);
    expect(find.byKey(const Key('askodoxPosPayAddUpi')), findsOneWidget);
  });
}
