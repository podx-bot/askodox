import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/native_video/video_commerce.dart' show askodoxShareTextProvider;
import 'package:podx/features/vault/vault_logic.dart';
import 'package:podx/features/vault/vault_screen.dart';
import 'package:podx/features/vault/vault_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryFiles implements AskodoxVaultFiles {
  final Map<String, Uint8List> kept = {};
  @override
  Future<String> save(String id, Uint8List bytes) async {
    kept['$id.jpg'] = bytes;
    return '$id.jpg';
  }

  @override
  Future<Uint8List?> read(String name) async => kept[name];

  @override
  Future<void> remove(String name) async => kept.remove(name);
}

void main() {
  final today = DateTime(2026, 11, 28);
  AskodoxVaultPaper paper(String id, String item, {String until = '', String shop = '', bool remind = true, String at = ''}) =>
      AskodoxVaultPaper(id: id, item: item, shop: shop, warrantyUntil: until, remind: remind, addedAt: at);

  group('vault rules', () {
    test('state: none / over / ending / on', () {
      expect(askodoxVaultState(paper('a', 'x'), today), 'none');
      expect(askodoxVaultState(paper('a', 'x', until: '2026-11-27'), today), 'over');
      expect(askodoxVaultState(paper('a', 'x', until: '2026-11-28'), today), 'ending');
      expect(askodoxVaultState(paper('a', 'x', until: '2026-12-28'), today), 'ending');
      expect(askodoxVaultState(paper('a', 'x', until: '2026-12-29'), today), 'on');
    });

    test('list: search by item or shop, ending first, filters', () {
      final all = [
        paper('1', 'Mixer', until: '2027-06-01', shop: 'Sri Stores', at: '2026-01-01'),
        paper('2', 'Fan', until: '2026-12-10', shop: 'Lakshmi', at: '2026-02-01'),
        paper('3', 'Receipt', at: '2026-03-01'),
      ];
      expect(askodoxVaultShow(all, today).map((p) => p.id), ['2', '1', '3']);
      expect(askodoxVaultShow(all, today, filter: 'warranty').map((p) => p.id), ['2', '1']);
      expect(askodoxVaultShow(all, today, filter: 'ending').map((p) => p.id), ['2']);
      expect(askodoxVaultShow(all, today, query: 'sri').map((p) => p.id), ['1']);
    });

    test('reminders only for ending papers the person left on', () {
      final all = [paper('1', 'Fan', until: '2026-12-10'), paper('2', 'TV', until: '2026-12-11', remind: false)];
      expect(askodoxVaultEnding(all, today).map((p) => p.id), ['1']);
    });

    test('service text holds only item, shop, dates and serial', () {
      final p = AskodoxVaultPaper(
          id: 'a', item: 'Mixer', shop: 'Sri Stores', boughtOn: '2026-01-05', warrantyUntil: '2027-01-05', serial: 'SN123',
          servicePhone: '9000000000', amountPaise: 250000);
      final t = askodoxVaultServiceText(p, false);
      expect(t, contains('Mixer'));
      expect(t, contains('05-01-2026'));
      expect(t, contains('SN123'));
      expect(t, isNot(contains('2500')));
    });

    test('encode / decode round trip', () {
      final list = [paper('1', 'Fan', until: '2026-12-10', shop: 'Lakshmi')];
      final back = askodoxVaultDecode(askodoxVaultEncode(list));
      expect(back.single.item, 'Fan');
      expect(back.single.warrantyUntil, '2026-12-10');
      expect(askodoxVaultDecode('not json'), isEmpty);
    });
  });

  testWidgets('type a paper, it is listed with its state, search finds it, share and remove', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final files = _MemoryFiles();
    final shared = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxVaultClockProvider.overrideWithValue(() => DateTime(2026, 11, 28, 9)),
        askodoxVaultFilesProvider.overrideWithValue(files),
        askodoxShareTextProvider.overrideWithValue((text, {subject = ''}) async {
          shared.add(text);
          return true;
        }),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxVaultScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('askodoxVaultEmpty')), findsOneWidget);
    expect(find.byKey(const Key('askodoxVaultPrivacy')), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxVaultType')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('askodoxVaultItem')), 'Table fan');
    await tester.enterText(find.byKey(const Key('askodoxVaultShop')), 'Lakshmi Electricals');
    await tester.enterText(find.byKey(const Key('askodoxVaultSerial')), 'SN-100');
    await tester.tap(find.byKey(const Key('askodoxVaultMonths-6')));
    await tester.pump();
    // Bought-on is empty, so six months count from today: 28 Nov 2026 -> 28 May 2027.
    expect(tester.widget<Text>(find.byKey(const Key('askodoxVaultUntilValue'))).data, '28-05-2027');
    await tester.tap(find.byKey(const Key('askodoxVaultSave')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Table fan'), findsOneWidget);
    expect(find.textContaining('In warranty'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('askodoxVaultSearch')), 'zzz');
    await tester.pump();
    expect(find.text('Table fan'), findsNothing);
    await tester.enterText(find.byKey(const Key('askodoxVaultSearch')), 'lakshmi');
    await tester.pump();
    expect(find.text('Table fan'), findsOneWidget);

    await tester.tap(find.text('Table fan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxVaultShare')));
    await tester.pump();
    expect(shared.single, contains('SN-100'));

    await tester.tap(find.byKey(const Key('askodoxVaultRemove')));
    await tester.pumpAndSettle();
    expect(find.text('Table fan'), findsNothing);
    expect(find.byKey(const Key('askodoxVaultEmpty')), findsOneWidget);
  });
}
