import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/askodox_tile_grid.dart';

/// Profile -> Personal Finance: the ONE home of the Personal Tax Assistant and the
/// person's own money records. It only opens the existing screens (income tax / GST
/// estimates from `tax_intelligence.py` via /api/intel/*, Smart Tricks, scam checks,
/// shop advances, payment methods, AI Credits) -- no new engine, nothing computed here.
class AskodoxPersonalFinanceScreen extends StatelessWidget {
  const AskodoxPersonalFinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t('Personal Finance', 'Personal Finance (నా డబ్బు)'))),
      body: ListView(
        key: const Key('askodoxPersonalFinance'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          head(t('Personal Tax Assistant', 'Personal Tax Assistant')),
          AskodoxTileGrid(keyPrefix: 'askodoxFinance', tiles: [
            AskodoxTile(
                id: 'income_tax',
                icon: Icons.account_balance_outlined,
                title: t('Income tax estimate (new vs old regime)', 'Income tax అంచనా (new vs old regime)'),
                onTap: () => context.push('/intel/tax')),
            AskodoxTile(
                id: 'gst',
                icon: Icons.receipt_long_outlined,
                title: t('GST: registration, composition & amount', 'GST: registration, composition, మొత్తం'),
                onTap: () => context.push('/intel/gst')),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              t('Estimates from the published rules only. Confirm with a chartered accountant or the official portal before filing.',
                  'Published rules నుండి అంచనా మాత్రమే. File చేసే ముందు CA తో లేదా official portal లో confirm చేసుకోండి.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
          head(t('Money decisions & safety', 'డబ్బు నిర్ణయాలు & జాగ్రత్త')),
          AskodoxTileGrid(keyPrefix: 'askodoxFinance', tiles: [
            AskodoxTile(
                id: 'smart_tricks',
                icon: Icons.lightbulb_outline,
                title: t('Smart Tricks: buy vs rent, repair vs replace', 'Smart Tricks: కొనాలా / అద్దెకా, రిపేరా / కొత్తదా'),
                onTap: () => context.push('/intel/tricks')),
            AskodoxTile(
                id: 'fraud_check',
                icon: Icons.gpp_maybe_outlined,
                title: t('Scam checklists & where to report', 'మోసాల checklists, ఎక్కడ report చేయాలి'),
                onTap: () => context.push('/intel/fraud')),
          ]),
          head(t('My money records', 'నా డబ్బు records')),
          AskodoxTileGrid(keyPrefix: 'askodoxFinance', tiles: [
            AskodoxTile(
                id: 'shop_advances',
                icon: Icons.savings_outlined,
                title: t('Shop advances (approve)', 'Shop advances (approve చేయండి)'),
                onTap: () => context.push('/me/shop-advances')),
            AskodoxTile(
                id: 'payment_methods',
                icon: Icons.account_balance_wallet_outlined,
                title: t('My payment methods (UPI / bank)', 'నా payment methods (UPI / bank)'),
                onTap: () => context.push('/me/payment-methods')),
            AskodoxTile(
                id: 'ai_credits',
                icon: Icons.bolt_outlined,
                title: t('AI Credits', 'AI Credits'),
                onTap: () => context.push('/me/ai-credits')),
          ]),
        ],
      ),
    );
  }
}
