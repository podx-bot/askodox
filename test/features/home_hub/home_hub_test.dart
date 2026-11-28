import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/home_hub/home_hub_screen.dart';
import 'package:podx/features/kitchen/kitchen_logic.dart';
import 'package:podx/features/vault/vault_logic.dart';
import 'package:podx/features/vault/vault_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final today = DateTime(2026, 11, 28);
  const mixer = AskodoxVaultPaper(id: 'a', item: 'Mixer', warrantyUntil: '2026-12-23');
  const off = AskodoxVaultPaper(id: 'b', item: 'Fan', warrantyUntil: '2026-12-10', remind: false);
  const far = AskodoxVaultPaper(id: 'c', item: 'TV', warrantyUntil: '2028-01-01');
  const dal = AskodoxKitchenItem(id: '1', name: 'Dal', milli: 500, lowMilli: 1000);
  const rice = AskodoxKitchenItem(id: '2', name: 'Rice', milli: 12000, lowMilli: 2000);

  test('reminders: ending warranties the person left on, then low kitchen items', () {
    final out = askodoxHomeReminders([far, off, mixer], [rice, dal], today, false);
    expect(out.map((r) => r.text), ['Mixer warranty', 'Dal is low']);
    expect(out.first.urgent, isTrue);
    expect(out.first.route, '/me/vault');
    expect(out.last.route, '/me/kitchen');
    expect(askodoxHomeReminders(const [], const [], today, true), isEmpty);
  });

  test('at most the number asked for', () {
    final many = [for (var i = 0; i < 9; i++) AskodoxKitchenItem(id: '$i', name: 'Item $i', milli: 0, finished: true)];
    expect(askodoxHomeReminders(const [], many, today, false, max: 6).length, 6);
  });

  testWidgets('the page shows its tiles, the privacy line and the note; empty = nothing is ending', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxVaultClockProvider.overrideWithValue(() => today)],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxHomeHubScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    for (final k in ['askodoxHomeHub', 'askodoxHomeHubPhoto', 'askodoxHomeHubKitchen', 'askodoxHomeHubVault', 'askodoxHomeHubSpend',
      'askodoxHomeHubFamily', 'askodoxHomeHubNothing', 'askodoxHomeHubPrivacy']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
  });
}
