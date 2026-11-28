import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/explainers/explainer_cards.dart';
import 'package:podx/features/money_home/money_home_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('cards fit the person\'s own words, best first; nothing fits -> empty', () {
    expect(askodoxExplainersFor('స్టాక్ లెక్క సరిపోవట్లేదు, చికెన్ లీక్').first.id, 'stock_leak');
    expect(askodoxExplainersFor('my customers have pending credit').first.id, 'money_stuck');
    expect(askodoxExplainersFor('xyz'), isEmpty);
    expect(askodoxExplainersFor(''), isEmpty);
  });

  test('a step with :id needs a shop; a plain page does not', () {
    expect(askodoxExplainerRoute('/pos/:id/yield', 's1'), '/pos/s1/yield');
    expect(askodoxExplainerRoute('/pos/:id/yield', null), isNull);
    expect(askodoxExplainerRoute('/me/vault', null), '/me/vault');
  });

  test('every card holds steps, words, and no figures or the banned word', () {
    for (final e in askodoxExplainers) {
      expect(e.steps, isNotEmpty, reason: e.id);
      expect(e.words, isNotEmpty, reason: e.id);
      for (final t in [e.titleTe, e.problemTe, for (final s in e.steps) s.te]) {
        expect(t.contains('లేదు'), isFalse, reason: e.id);
        expect(RegExp(r'\d').hasMatch(t), isFalse, reason: '${e.id}: no figures');
      }
    }
  });

  testWidgets('the page lists the cards and opens one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxMyShopsProvider.overrideWith((ref) async => const [])],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxExplainersScreen(only: 'bills_mixed')),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxExplainer-stock_leak')), findsOneWidget);
    expect(find.byKey(const Key('askodoxExplainerStep-bills_mixed-0')), findsOneWidget);
    expect(find.text('Set up your shop first'), findsWidgets);
  });

  test('every card sits under a known filter group', () {
    final known = {for (final g in askodoxExplainerGroups) g.$1}..remove('all');
    for (final e in askodoxExplainers) {
      expect(known.contains(e.group), isTrue, reason: e.id);
    }
  });
}
