import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/plans/presentation/ai_credits_screen.dart';

Widget _app(Map<String, Object?> data) => ProviderScope(
      overrides: [askodoxAiCreditsProvider.overrideWith((ref) async => AskodoxAiCreditsState(data))],
      child: const MaterialApp(home: AskodoxAiCreditsScreen()),
    );

void main() {
  test('rupee formatting is exact', () {
    expect(askodoxRupees(10000), '₹100');
    expect(askodoxRupees(2550), '₹25.50');
    expect(askodoxRupees(-50), '-₹0.50');
  });

  testWidgets('a server without AI Credits does not say "sign in"', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxAiCreditsProvider.overrideWith((ref) async => throw const AskodoxAiCreditsLoadError(404))],
      child: const MaterialApp(home: AskodoxAiCreditsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('not available right now'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
  });

  testWidgets('free AI: balance, honest note, packs not on sale have no Pay button', (tester) async {
    await tester.pumpWidget(_app({
      'balance_paise': {'live': 0, 'test': 0},
      'charging': false,
      'packs': [
        {'plan_code': 'ai_credits_100', 'price': 100, 'credits_paise': 10000, 'payable': false},
      ],
      'history': [],
    }));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAiCreditsBalance')), findsOneWidget);
    expect(find.textContaining('nothing is deducted'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAiPackPay-ai_credits_100')), findsNothing);
    // 2026-11-04: no "Not on sale yet" list at all until a pack is on sale.
    expect(find.byKey(const ValueKey('askodoxAiPack-ai_credits_100')), findsNothing);
    expect(find.textContaining('Not on sale yet'), findsNothing);
    expect(find.byKey(const Key('askodoxAiCreditsTest')), findsNothing);
    expect(find.textContaining('never used to pay a seller'), findsOneWidget);
  });

  testWidgets('charging on: rates, TEST balance labelled, payable pack shows Pay, history rows', (tester) async {
    await tester.pumpWidget(_app({
      'balance_paise': {'live': 9950, 'test': 12000},
      'charging': true,
      'rates_paise': {'chat': 50},
      'free_per_day': {'chat': 5},
      'used_today': {'chat': 2},
      'packs': [
        {'plan_code': 'ai_credits_100', 'price': 100, 'credits_paise': 10000, 'payable': true},
      ],
      'history': [
        {'kind': 'usage', 'feature': 'chat', 'delta_paise': -50, 'mode': 'live', 'created_at': '2026-10-27T06:00:00'},
        {'kind': 'topup', 'feature': '', 'delta_paise': 10000, 'mode': 'live', 'created_at': '2026-10-27T05:00:00'},
      ],
    }));
    await tester.pumpAndSettle();
    expect(find.text('₹99.50'), findsOneWidget);
    expect(find.textContaining('TEST credits'), findsOneWidget);
    expect(find.textContaining('₹0.50 per use'), findsOneWidget);
    expect(find.textContaining('5 free a day'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAiPackPay-ai_credits_100')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recharge').last, 200);
    expect(find.text('-₹0.50'), findsOneWidget);
  });

  testWidgets('trial meter: my use today / month shown, free while testing, no cost or margin', (tester) async {
    await tester.pumpWidget(_app({
      'balance_paise': {'live': 0, 'test': 0},
      'charging': false,
      'packs': [],
      'history': [],
      'usage': {
        'free_now': true,
        'today': {
          'value_paise': 1250,
          'uses': 5,
          'by_feature': {
            'chat': {'uses': 4, 'value_paise': 450},
            'voice': {'uses': 1, 'value_paise': 800},
          },
        },
        'month': {
          'value_paise': 9050,
          'uses': 30,
          'by_feature': {
            'chat': {'uses': 25, 'value_paise': 3050},
            'voice': {'uses': 5, 'value_paise': 6000},
            'image': {'uses': 0, 'value_paise': 0},
          },
        },
      },
    }));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAiCreditsUsage')), findsOneWidget);
    expect(find.text('~₹12.50'), findsOneWidget);
    expect(find.text('~₹90.50'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAiCreditsUsage-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAiCreditsUsage-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAiCreditsUsage-image')), findsNothing, reason: 'no use -> no row');
    expect(find.textContaining('nothing is deducted'), findsWidgets);
    expect(find.textContaining('margin'), findsNothing);
  });

  testWidgets('no usage block from an older server: no trial card', (tester) async {
    await tester.pumpWidget(_app({'balance_paise': {'live': 0, 'test': 0}, 'charging': false, 'packs': [], 'history': []}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAiCreditsUsage')), findsNothing);
  });
}
