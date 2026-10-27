import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../data/plans_repository.dart';
import 'plans_screen.dart';

/// AI Credits (pay-as-you-go for the AI assistant). The SERVER keeps the balance: credits are added only after the
/// payment gateway confirms a pack was paid, and each AI use is deducted on the server. This screen only shows them.
class AskodoxAiCreditsState {
  const AskodoxAiCreditsState(this.data);
  final Map<String, Object?> data;

  int balance(String mode) => (((data['balance_paise'] as Map?) ?? const {})[mode] as num?)?.toInt() ?? 0;
  bool get charging => data['charging'] == true;
  Map rates() => (data['rates_paise'] as Map?) ?? const {};
  Map free() => (data['free_per_day'] as Map?) ?? const {};
  Map usedToday() => (data['used_today'] as Map?) ?? const {};
  List<Map> packs() => ((data['packs'] as List?) ?? const []).whereType<Map>().toList();
  List<Map> history() => ((data['history'] as List?) ?? const []).whereType<Map>().toList();
}

final askodoxAiCreditsProvider = FutureProvider.autoDispose<AskodoxAiCreditsState>((ref) async {
  final session = ref.watch(authSessionProvider);
  final result = await ref.watch(apiClientProvider).get<Map<String, Object?>>('/api/me/ai-credits',
      options: ApiRequestOptions(authToken: session.user == null ? null : session.tokenPlaceholder));
  return switch (result) {
    ApiSuccess<Map<String, Object?>>(:final data) => AskodoxAiCreditsState(data),
    ApiError<Map<String, Object?>>(:final failure) => throw Exception(failure.message ?? 'failed'),
  };
});

String askodoxRupees(int paise) {
  final sign = paise < 0 ? '-' : '';
  final p = paise.abs();
  return p % 100 == 0 ? '$sign₹${p ~/ 100}' : '$sign₹${(p / 100).toStringAsFixed(2)}';
}

const _features = {
  'chat': ('AI chat', 'AI చాట్'),
  'reasoning': ('Deep reasoning', 'లోతైన విశ్లేషణ'),
  'voice': ('Voice', 'వాయిస్'),
  'web_search': ('Web search', 'వెబ్ సెర్చ్'),
  'image': ('Photo understanding', 'ఫోటో విశ్లేషణ'),
};

class AskodoxAiCreditsScreen extends ConsumerWidget {
  const AskodoxAiCreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final state = ref.watch(askodoxAiCreditsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('AI Credits', 'AI క్రెడిట్స్'))),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Sign in to see your AI Credits.', 'AI Credits చూడటానికి సైన్ ఇన్ అవ్వండి.'),
              key: const Key('askodoxAiCreditsError'), textAlign: TextAlign.center),
        )),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(askodoxAiCreditsProvider),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Balance', 'బ్యాలెన్స్'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(askodoxRupees(s.balance('live')),
                      key: const Key('askodoxAiCreditsBalance'),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                  if (s.balance('test') != 0)
                    Text('${t('TEST credits (sandbox money)', 'TEST credits (sandbox డబ్బు)')}: ${askodoxRupees(s.balance('test'))}',
                        key: const Key('askodoxAiCreditsTest'), style: const TextStyle(color: Color(0xFFB45309))),
                  const SizedBox(height: 6),
                  Text(
                      s.charging
                          ? t('AI answers use credits at the rates below. Search, orders, POS and payments are free.',
                              'కింది రేట్ల ప్రకారం AI సమాధానాలకు credits వాడతాయి. Search, orders, POS, payments ఉచితం.')
                          : t('AI is free right now — nothing is deducted.', 'ఇప్పుడు AI ఉచితం — ఏమీ కట్ అవ్వదు.'),
                      key: const Key('askodoxAiCreditsCharging')),
                ]),
              ),
            ),
            if (s.charging) ...[
              const SizedBox(height: 8),
              Text(t('Rates', 'రేట్లు'), style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final e in _features.entries)
                if (((s.rates()[e.key] as num?) ?? 0) > 0)
                  ListTile(
                    dense: true,
                    title: Text(t(e.value.$1, e.value.$2)),
                    subtitle: ((s.free()[e.key] as num?) ?? 0) > 0
                        ? Text(t('${s.free()[e.key]} free a day · used today ${s.usedToday()[e.key] ?? 0}',
                            'రోజుకు ${s.free()[e.key]} ఉచితం · ఈరోజు వాడినవి ${s.usedToday()[e.key] ?? 0}'))
                        : null,
                    trailing: Text('${askodoxRupees((s.rates()[e.key] as num).toInt())} ${t('per use', 'ఒక్కసారికి')}'),
                  ),
            ],
            const SizedBox(height: 8),
            Text(t('Recharge', 'రీఛార్జ్'), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final p in s.packs())
              ListTile(
                key: ValueKey('askodoxAiPack-${p['plan_code']}'),
                title: Text('₹${(p['price'] as num?)?.toInt() ?? 0}'),
                subtitle: Text([
                  '${t('Gives', 'వస్తాయి')} ${askodoxRupees((p['credits_paise'] as num?)?.toInt() ?? 0)}',
                  if (p['payable'] != true) t('Not on sale yet', 'ఇంకా అమ్మకానికి లేదు'),
                ].join(' · ')),
                trailing: p['payable'] == true
                    ? FilledButton(
                        key: ValueKey('askodoxAiPackPay-${p['plan_code']}'),
                        onPressed: () => _pay(context, ref, '${p['plan_code']}', t),
                        child: Text(t('Pay', 'చెల్లించు')))
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  t('AI Credits are only for ASKODOX AI features: not transferable, not cash, never used to pay a seller. '
                      'Paid through Razorpay; added only after Razorpay confirms the payment.',
                      'AI Credits ASKODOX AI కోసం మాత్రమే: వేరేవాళ్ళకు పంపలేరు, cash కాదు, seller కి కట్టడానికి వాడరు. '
                          'Razorpay ద్వారా చెల్లింపు; Razorpay confirm చేశాకే చేరతాయి.'),
                  key: const Key('askodoxAiCreditsNote'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            Text(t('History', 'చరిత్ర'), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (s.history().isEmpty) Text(t('Nothing yet.', 'ఇంకా ఏమీ లేదు.')),
            for (final h in s.history())
              ListTile(
                dense: true,
                title: Text(_kind('${h['kind']}', '${h['feature'] ?? ''}', t)),
                subtitle: Text('${h['created_at'] ?? ''}'.replaceFirst('T', ' ').split('.').first),
                trailing: Text(
                    '${askodoxRupees((h['delta_paise'] as num?)?.toInt() ?? 0)}${h['mode'] == 'test' ? ' TEST' : ''}'),
              ),
          ]),
        ),
      ),
    );
  }

  static String _kind(String kind, String feature, String Function(String, String) t) {
    final f = _features[feature];
    return switch (kind) {
      'topup' => t('Recharge', 'రీఛార్జ్'),
      'usage' => f == null ? t('AI use', 'AI వాడకం') : t(f.$1, f.$2),
      'release' => t('Returned (AI gave no answer)', 'తిరిగి వచ్చింది (AI సమాధానం ఇవ్వలేదు)'),
      'refund' => t('Recharge refunded', 'రీఛార్జ్ refund'),
      _ => kind,
    };
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, String code, String Function(String, String) t) async {
    final repo = ref.read(plansRepositoryProvider);
    final started = await repo.startCheckout(code);
    if (!context.mounted) return;
    final url = started.payUrl == null ? null : Uri.tryParse(started.payUrl!);
    if (started.purchaseId == null || url == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Payment could not start (${started.error ?? 'unavailable'}).',
              'చెల్లింపు మొదలవలేదు (${started.error ?? 'అందుబాటులో లేదు'}).'))));
      return;
    }
    await ref.read(askodoxPayLauncherProvider)(url);
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (_) => AskodoxPaymentStatusDialog(purchaseId: started.purchaseId!, repo: repo, t: t, credits: true));
    ref.invalidate(askodoxAiCreditsProvider);
  }
}
