import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';

// Owner 2026-11-24 (counter bill pay sheet): "UPI select చేస్తే select అవ్వట్లేదు" -- Cash ₹230 was already added (left ₹0),
// so picking UPI changed nothing. UPI must take over, and the shop's own QR shows right there for the customer to scan.
// Then: "బాకీ కూడా ఉండాలి -- కొంతమంది క్యాష్, సగం అప్పు; కొంతమంది UPI" -- a Due way, mixed with cash / UPI.
class _Sheet {
  AskodoxPosPayResult? result;
}

Future<_Sheet> _open(WidgetTester tester, {Future<(String, String)?> Function()? upi, bool customer = false}) async {
  final sheet = _Sheet();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => sheet.result = await showModalBottomSheet<AskodoxPosPayResult>(
            context: context,
            isScrollControlled: true,
            builder: (_) => AskodoxPosPaymentSheet(total: 23000, allowCredit: customer, te: false, shopUpi: upi),
          ),
          child: const Text('PAY'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('PAY'));
  await tester.pumpAndSettle();
  return sheet;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
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
    final sheet = await _open(tester, upi: () async {
      asked++;
      return ('shop@okaxis', 'Ravi Biryani');
    });
    expect(find.byKey(const Key('askodoxPosPayQr')), findsNothing, reason: 'no QR before UPI is chosen');
    expect(asked, 0, reason: 'nothing fetched for a cash bill');
    await _tap(tester, find.byKey(const Key('askodoxPosAddPayment')));
    expect(find.text('Cash ₹230.00'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('askodoxPosPayWay-upi')));
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('askodoxPosPayWay-upi'))).selected, isTrue);
    expect(find.text('UPI ₹230.00'), findsOneWidget, reason: 'the one payment follows the way picked');
    expect(find.text('Cash ₹230.00'), findsNothing);
    expect(find.byKey(const Key('askodoxPosPayQr')), findsOneWidget);
    expect(asked, 1);
    await _tap(tester, find.byKey(const Key('askodoxPosIssue')));
    expect(sheet.result!.payments.single['method'], 'upi');
    expect(sheet.result!.dueDate, '');
  });

  testWidgets('a wrong payment can be taken off, and no UPI saved offers to add one', (tester) async {
    await _open(tester, upi: () async => null);
    await _tap(tester, find.byKey(const Key('askodoxPosAddPayment')));
    expect(find.byKey(const ValueKey('askodoxPosPayment-0')), findsOneWidget);
    await _tap(tester, find.byTooltip('Remove'));
    expect(find.byKey(const ValueKey('askodoxPosPayment-0')), findsNothing);
    expect(find.textContaining('left ₹230.00'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('askodoxPosPayWay-upi')));
    expect(find.byKey(const Key('askodoxPosPayQr')), findsNothing);
    expect(find.byKey(const Key('askodoxPosPayAddUpi')), findsOneWidget);
  });

  testWidgets('half cash, the rest a due: the person is typed right in the sheet', (tester) async {
    final sheet = await _open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '100');
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('askodoxPosAddPayment')));
    await _tap(tester, find.byKey(const ValueKey('askodoxPosPayWay-due')));
    expect(find.text('₹130.00 stays as a due'), findsOneWidget);
    final issue = find.byKey(const Key('askodoxPosIssue'));
    expect(tester.widget<FilledButton>(issue).onPressed, isNull, reason: 'a due needs a name or number');
    await tester.enterText(find.descendant(of: find.byKey(const Key('askodoxPosDuePhone')), matching: find.byType(TextField)), '98765 43210');
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('askodoxPosDueWhen-Tomorrow')));
    expect(find.text('Issue bill — ₹130.00 due'), findsOneWidget);
    await _tap(tester, issue);
    final r = sheet.result!;
    expect([for (final p in r.payments) (p['method'], p['amount_paise'])], [('cash', 10000)]);
    expect(r.duePhone, '9876543210');
    expect(r.newDuePerson, isTrue);
    expect(r.dueDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('a chosen customer needs no name for a due; the whole bill can be a due', (tester) async {
    final sheet = await _open(tester, customer: true);
    await _tap(tester, find.byKey(const ValueKey('askodoxPosPayWay-due')));
    expect(find.byKey(const Key('askodoxPosDueName')), findsNothing);
    await _tap(tester, find.byKey(const Key('askodoxPosIssue')));
    expect(sheet.result!.payments, isEmpty);
    expect(sheet.result!.newDuePerson, isFalse);
    expect(sheet.result!.dueDate, isNotEmpty);
  });
}
