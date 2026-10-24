
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_printer.dart';
import 'package:podx/features/pos/presentation/pos_records_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Native extends AskodoxNativePrinters {
  _Native();
  final sent = <String>[];

  @override
  Future<List<AskodoxNativePrinter>> paired() async =>
      const [AskodoxNativePrinter(id: 'classic:66:22:AA:01:02:03', name: 'MTP-II', kind: 'classic', hint: true)];

  @override
  Future<List<AskodoxNativePrinter>> usb() async => const [];

  @override
  Future<void> send(String id, Uint8List bytes) async => sent.add(id);
}

class _Ble implements AskodoxPrinterTransport {
  final sent = <String>[];
  @override
  Future<void> write(String deviceId, Uint8List bytes) async => sent.add(deviceId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the saved id picks the link: classic / usb native, anything else BLE', () async {
    final native = _Native();
    final ble = _Ble();
    final t = AskodoxRoutingPrinterTransport(native, ble);
    final bytes = Uint8List.fromList([0x1B, 0x40]);
    await t.write('classic:66:22:AA:01:02:03', bytes);
    await t.write('usb:/dev/bus/usb/001/002', bytes);
    await t.write('C0:FF:EE:00:11:22', bytes);
    expect(native.sent, ['classic:66:22:AA:01:02:03', 'usb:/dev/bus/usb/001/002']);
    expect(ble.sent, ['C0:FF:EE:00:11:22']);
    expect(askodoxPrinterLink('classic:x'), 'classic');
    expect(askodoxPrinterLink('usb:x'), 'usb');
    expect(askodoxPrinterLink('AA:BB'), 'ble');
  });

  test('native errors are named, never reported as printed', () async {
    const channel = MethodChannel('askodox.test/hardware');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'sendClassic') throw PlatformException(code: 'send_failed', message: 'read failed, socket might closed');
      if (call.method == 'sendUsb') throw PlatformException(code: 'permission_requested');
      if (call.method == 'bondedPrinters') throw PlatformException(code: 'bluetooth_off');
      return null;
    });
    const native = AskodoxNativePrinters(channel);
    final bytes = Uint8List.fromList([1]);
    await expectLater(native.send('classic:AA', bytes),
        throwsA(isA<AskodoxPrinterException>().having((e) => e.code, 'code', 'connect_failed')));
    await expectLater(native.send('usb:/dev/x', bytes),
        throwsA(isA<AskodoxPrinterException>().having((e) => e.code, 'code', 'permission_requested')));
    await expectLater(native.paired(), throwsA(isA<AskodoxPrinterException>().having((e) => e.code, 'code', 'bluetooth_off')));
  });

  testWidgets('printer screen: pick a paired Classic printer and test-print through it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final native = _Native();
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxNativePrintersProvider.overrideWithValue(native)],
      child: const MaterialApp(home: AskodoxPosPrinterScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxPosPrinterPaired')));
    await tester.pumpAndSettle();
    expect(find.text('MTP-II'), findsOneWidget);
    expect(find.text('Looks like a printer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosPrinterNative-classic:66:22:AA:01:02:03')));
    await tester.pumpAndSettle();
    expect(find.text('58 mm · Classic Bluetooth'), findsOneWidget);
    await tester.tap(find.text('Test print'));
    await tester.pumpAndSettle();
    expect(native.sent, ['classic:66:22:AA:01:02:03']);
    expect(find.text('Sent — check that it printed.'), findsOneWidget);
  });
}
