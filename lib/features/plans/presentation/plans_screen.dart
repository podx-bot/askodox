import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/navigator_section.dart';
import '../data/plans_repository.dart';

/// Plans & subscription: Free / Plus / Pro from the server. Plans not yet on
/// sale say so; there is no payment step in the app (no gateway), and the
/// add-on Travel Radio pass lives on its own screen.
class AskodoxPlansScreen extends ConsumerWidget {
  const AskodoxPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final state = ref.watch(plansProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Plans & subscription', 'ప్లాన్లు & సబ్‌స్క్రిప్షన్'))),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(t('Plans are not available right now.', 'ప్లాన్లు ఇప్పుడు అందుబాటులో లేవు.'))),
        data: (s) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (s.currentPlan != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '${t('Your plan', 'మీ ప్లాన్')}: ${s.plans.where((p) => p.code == s.currentPlan).map((p) => p.name).firstOrNull ?? s.currentPlan} · ${s.currentStatus}',
                  key: const Key('askodoxPlansCurrent'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          AskodoxNavSection(
            title: t('Plans', 'ప్లాన్లు'),
            icon: Icons.workspace_premium_outlined,
            children: [
              for (final p in s.plans)
                ListTile(
                  key: ValueKey('askodoxPlan-${p.code}'),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    p.price == 0 ? t('Free', 'ఉచితం') : '₹${p.price} / ${p.periodDays} ${t('days', 'రోజులు')}',
                    if (p.trialDays > 0) t('${p.trialDays}-day trial', '${p.trialDays} రోజుల ట్రయల్'),
                    if (!p.available) t('Not available yet', 'ఇంకా అందుబాటులో లేదు'),
                  ].join(' · ')),
                  trailing: s.currentPlan == p.code
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A))
                      : p.available
                          ? TextButton(
                              key: ValueKey('askodoxPlanChoose-${p.code}'),
                              onPressed: () async {
                                final status = await ref.read(plansRepositoryProvider).choose(p.code);
                                ref.invalidate(plansProvider);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(status == null
                                        ? t('Please sign in first.', 'ముందు సైన్ ఇన్ చేయండి.')
                                        : status == 'PENDING_PAYMENT'
                                            ? t('Payment is not available in the app yet.', 'యాప్‌లో చెల్లింపు ఇంకా లేదు.')
                                            : t('Plan updated.', 'ప్లాన్ మారింది.'))));
                              },
                              child: Text(t('Choose', 'ఎంచుకోండి')))
                          : null,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                t('No payment is taken in the app. Paid plans open once billing is approved.',
                    'యాప్‌లో ఎలాంటి చెల్లింపు తీసుకోము. బిల్లింగ్ ఆమోదం తర్వాతే పెయిడ్ ప్లాన్లు.'),
                key: const Key('askodoxPlansBillingNote'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
          ),
        ]),
      ),
    );
  }
}
