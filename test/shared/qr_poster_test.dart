import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/qr_poster.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('poster carries brand, title, instruction, site and a scannable QR', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AskodoxQrPoster(
            data: 'ASKODOX-SHOP:123456',
            te: false,
            title: 'Test Biryani House',
            label: 'Table 4',
            instructionEn: 'Scan with ASKODOX',
            instructionTe: 'ASKODOX తో స్కాన్ చేయండి',
            qrKey: Key('testQr'),
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('askodoxQrPosterBrand')), findsOneWidget);
    expect(find.text('Test Biryani House'), findsOneWidget);
    expect(find.text('Table 4'), findsOneWidget);
    expect(find.text('Scan with ASKODOX'), findsOneWidget);
    expect(find.text('askodox.com'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('askodoxQrPosterSave')), findsOneWidget);
    expect(find.byKey(const Key('askodoxQrPosterShare')), findsOneWidget);
  });

  testWidgets('Telugu text, and no buttons when actions are off', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AskodoxQrPoster(
            data: 'upi://pay?pa=a@b',
            te: true,
            instructionEn: 'Scan',
            instructionTe: 'స్కాన్ చేయండి',
            actions: false,
          ),
        ),
      ),
    ));
    expect(find.text('స్కాన్ చేయండి'), findsOneWidget);
    expect(find.byKey(const Key('askodoxQrPosterSave')), findsNothing);
  });
}
