import '../../../core/flags/askodox_release_phase.dart';
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

  /// Trial meter (owner 2026-11-24): what the person's own AI use WOULD cost; null when the server does not send it.
  Map? usage() => data['usage'] as Map?;

  /// AI plan (owner 2026-11-26): percent bars + pace + whether the next recharge carries an extra. Shown only while
  /// charging is on; null from an older server.
  Map? status() => charging ? data['status'] as Map? : null;
}

/// "11:40 PM" from the server's India-time text; '' when it cannot be read.
String askodoxAiClock(Object? iso) {
  final at = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (at == null) return '';
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
}

/// The pace warning under the bars (like "at this pace you will run out"), or null when the pace is fine.
String? askodoxAiPaceWarning(Map status, String Function(String, String) t) {
  final free = (status['free'] as Map?) ?? const {};
  final pack = (status['pack'] as Map?) ?? const {};
  final hasPack = pack['has'] == true;
  final days = (pack['days_left'] as num?)?.toInt();
  if (hasPack && days != null && days <= 3) {
    return days <= 0
        ? t('At this pace your pack ends today.', 'ఈ వేగంతో మీ ప్యాక్ ఈ రోజే అయిపోతుంది.')
        : t('At this pace your pack ends in $days days.', 'ఈ వేగంతో మీ ప్యాక్ $days రోజుల్లో అయిపోతుంది.');
  }
  final ends = askodoxAiClock(free['runs_out_at']);
  if (!hasPack && free['on'] == true && ends.isNotEmpty) {
    return t("At this pace today's free AI ends by $ends.", 'ఈ వేగంతో ఈ రోజు free AI $ends కి అయిపోతుంది.');
  }
  return null;
}

/// The line on the recharge part: is today's extra still there? Null when the plan gives no extra.
String? askodoxAiBonusLine(Map status, String Function(String, String) t) {
  final bonus = (status['bonus'] as Map?) ?? const {};
  final percent = (bonus['percent'] as num?)?.toInt() ?? 0;
  return switch ('${bonus['kind']}') {
    'first_recharge' when percent == 100 =>
      t('First recharge is doubled: pay ₹100, get ₹200. Once.', 'మొదటి రీఛార్జ్ డబుల్: ₹100 కడితే ₹200. ఒక్కసారే.'),
    'first_recharge' when percent > 0 =>
      t('First recharge gets $percent% extra. Once.', 'మొదటి రీఛార్జ్ కి $percent% అదనం. ఒక్కసారే.'),
    'daily_first' when percent > 0 =>
      t("Today's $percent% extra is still left.", 'ఈ రోజు $percent% అదనం ఇంకా మిగిలి ఉంది.'),
    'used_today' => t("Today's extra is used. It comes again on tomorrow's first recharge.",
        'ఈ రోజు అదనం వాడేశారు. రేపు మొదటి రీఛార్జ్ కి మళ్ళీ వస్తుంది.'),
    _ => null,
  };
}

/// The four groups the trial meter shows (server `ai_usage_meter.USER_FEATURES`).
const askodoxUsageGroups = ['chat', 'voice', 'web_search', 'image'];

final askodoxAiCreditsProvider = FutureProvider.autoDispose<AskodoxAiCreditsState>((ref) async {
  final session = ref.watch(authSessionProvider);
  final result = await ref.watch(apiClientProvider).get<Map<String, Object?>>('/api/me/ai-credits',
      options: ApiRequestOptions(authToken: session.user == null ? null : session.tokenPlaceholder));
  return switch (result) {
    ApiSuccess<Map<String, Object?>>(:final data) => AskodoxAiCreditsState(data),
    ApiError<Map<String, Object?>>(:final failure) => throw AskodoxAiCreditsLoadError(failure.statusCode),
  };
});

/// Why the balance could not load: 401 = not signed in; anything else = not available on this server yet / offline.
class AskodoxAiCreditsLoadError implements Exception {
  const AskodoxAiCreditsLoadError(this.statusCode);
  final int? statusCode;
}

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
  'radio': ('Travel Radio', 'ట్రావెల్ రేడియో'),
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
        error: (e, __) => Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              e is AskodoxAiCreditsLoadError && e.statusCode == 401
                  ? t('Sign in to see your AI Credits.', 'AI Credits చూడటానికి సైన్ ఇన్ అవ్వండి.')
                  : t('AI Credits are not available right now. Pull down later or check your connection.',
                      'AI Credits ఇప్పుడు అందుబాటులో లేవు. కాసేపాగి మళ్లీ చూడండి లేదా connection చూడండి.'),
              key: const Key('askodoxAiCreditsError'), textAlign: TextAlign.center),
        )),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(askodoxAiCreditsProvider),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            if (s.status() != null) AskodoxAiBarsCard(status: s.status()!, t: t),
            if (s.status() == null)
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
            if (s.usage() != null && s.status() == null) ...[
              const SizedBox(height: 8),
              _UsageCard(usage: s.usage()!, t: t),
            ],
            if (s.status() != null) ...[
              // Rupees live only from here down (owner 2026-11-26): the recharge part.
              const SizedBox(height: 12),
              Text(t('Recharge', 'రీఛార్జ్'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${t('In your pack', 'మీ ప్యాక్ లో')}: ${askodoxRupees(s.balance('live'))}'
                  '${s.balance('test') != 0 ? ' · TEST ${askodoxRupees(s.balance('test'))}' : ''}',
                  key: const Key('askodoxAiCreditsBalance')),
              if (askodoxAiBonusLine(s.status()!, t) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(askodoxAiBonusLine(s.status()!, t)!,
                      key: const Key('askodoxAiBonusLine'),
                      style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w700)),
                ),
            ],
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
            // Recharge packs show only once at least one is really on sale
            // (owner, 2026-11-04: no list of "Not on sale yet" rows).
            if (!askodoxPlayStoreBuild && s.packs().any((p) => p['payable'] == true)) ...[
            const SizedBox(height: 8),
            if (s.status() == null) Text(t('Recharge', 'రీఛార్జ్'), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final p in s.packs().where((p) => p['payable'] == true))
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
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  askodoxPlayStoreBuild
                      ? t('AI Credits are only for ASKODOX AI features: not transferable, not cash, never used to pay a seller. '
                          'Recharge is not available in this version yet.',
                          'AI Credits ASKODOX AI కోసం మాత్రమే: వేరేవాళ్ళకు పంపలేరు, cash కాదు, seller కి కట్టడానికి వాడరు. '
                              'ఈ వెర్షన్‌లో రీఛార్జ్ ఇంకా అందుబాటులో లేదు.')
                      : t('AI Credits are only for ASKODOX AI features: not transferable, not cash, never used to pay a seller. '
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
      'bonus' => t('Extra with the recharge', 'రీఛార్జ్ తో అదనం'),
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


/// "Your AI use" -- today and this month: uses per group and their approximate value. While testing (charging OFF)
/// it says plainly that nothing is deducted. Our cost / margin is never shown here.
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage, required this.t});
  final Map usage;
  final String Function(String, String) t;

  int _value(Map? block) => ((block?['value_paise'] as num?) ?? 0).toInt();

  @override
  Widget build(BuildContext context) {
    final today = usage['today'] as Map?;
    final month = usage['month'] as Map?;
    final feats = (month?['by_feature'] as Map?) ?? const {};
    final todayFeats = (today?['by_feature'] as Map?) ?? const {};
    final free = usage['free_now'] != false;
    return Card(
      key: const Key('askodoxAiCreditsUsage'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Your AI use', 'మీ AI వాడకం'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Today', 'ఈరోజు'), style: Theme.of(context).textTheme.bodySmall),
                Text('~${askodoxRupees(_value(today))}',
                    key: const Key('askodoxAiCreditsUsageToday'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('This month', 'ఈ నెల'), style: Theme.of(context).textTheme.bodySmall),
                Text('~${askodoxRupees(_value(month))}',
                    key: const Key('askodoxAiCreditsUsageMonth'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          for (final g in askodoxUsageGroups)
            if (((feats[g] as Map?)?['uses'] as num? ?? 0) > 0)
              Padding(
                key: ValueKey('askodoxAiCreditsUsage-$g'),
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(child: Text(t(_features[g]!.$1, _features[g]!.$2))),
                  Text(t('today ${(todayFeats[g] as Map?)?['uses'] ?? 0} · month ${(feats[g] as Map)['uses']}',
                      'ఈరోజు ${(todayFeats[g] as Map?)?['uses'] ?? 0} · నెల ${(feats[g] as Map)['uses']}')),
                  const SizedBox(width: 8),
                  Text('~${askodoxRupees((((feats[g] as Map)['value_paise'] as num?) ?? 0).toInt())}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          const SizedBox(height: 8),
          Text(
              free
                  ? t('Testing time: this is what your use would cost. It is free for you now, nothing is deducted. '
                      'Amounts are approximate.',
                      'టెస్టింగ్ సమయం: మీ వాడకానికి ఇంత అయ్యేది. ఇప్పుడు మీకు ఉచితం, ఏమీ కట్ అవ్వదు. మొత్తాలు సుమారుగా.')
                  : t('Approximate value of your AI use. What is really deducted is in the history below.',
                      'మీ AI వాడకం సుమారు విలువ. నిజంగా కట్ అయినవి కింద చరిత్రలో ఉన్నాయి.'),
              key: const Key('askodoxAiCreditsUsageNote'),
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}


/// Two bars in PERCENT, like a usage screen: today's free AI and my pack. No rupees here (owner 2026-11-26).
class AskodoxAiBarsCard extends StatelessWidget {
  const AskodoxAiBarsCard({super.key, required this.status, required this.t});
  final Map status;
  final String Function(String, String) t;

  @override
  Widget build(BuildContext context) {
    final free = (status['free'] as Map?) ?? const {};
    final pack = (status['pack'] as Map?) ?? const {};
    final warning = askodoxAiPaceWarning(status, t);
    final resets = askodoxAiClock(free['resets_at']);
    return Card(
      key: const Key('askodoxAiBars'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (free['on'] == true)
            _bar(context, const Key('askodoxAiBarFree'), t("Today's free", 'ఈ రోజు free'),
                (free['percent_left'] as num?)?.toInt() ?? 0, const Color(0xFF16A34A),
                resets.isEmpty ? '' : t('Full again at $resets. It cannot be saved.',
                    '$resets కి మళ్ళీ నిండుతుంది. దాచుకోలేరు.')),
          if (free['on'] == true) const SizedBox(height: 14),
          _bar(context, const Key('askodoxAiBarPack'), t('Your pack', 'మీ ప్యాక్'),
              pack['has'] == true ? (pack['percent_left'] as num?)?.toInt() ?? 0 : 0, const Color(0xFF2563EB),
              pack['has'] == true
                  ? t("Used after today's free part. No other limit.", 'ఈ రోజు free అయ్యాక ఇది వాడతాం. ఏ limit లేదు.')
                  : t('No pack yet. Recharge below to keep going after the free part.',
                      'ఇంకా ప్యాక్ లేదు. Free అయ్యాక కూడా వాడాలంటే కింద రీఛార్జ్ చేయండి.')),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('⚠️ $warning',
                  key: const Key('askodoxAiPaceWarning'),
                  style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 10),
          Text(
              t('Payment voice, bills, dues and sales reports are always free.',
                  'Payment voice, బిల్, బాకీ, sales report ఎప్పుడూ ఉచితం.'),
              key: const Key('askodoxAiShopFree'), style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _bar(BuildContext context, Key key, String label, int percent, Color color, String note) {
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
            value: percent / 100, minHeight: 10, color: color, backgroundColor: const Color(0xFFE5E7EB)),
      ),
      if (note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(note, style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }
}
