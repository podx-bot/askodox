import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/navigator_section.dart';
import '../data/plans_repository.dart';

/// Plans & subscription: Free / Plus / Pro from the server. Plans not yet on
/// sale say so. A plan the server marks payable (TEST mode: billing testers
/// only) gets "Pay": the server's hosted Razorpay checkout opens in the
/// browser, and the status shown here always comes back from the server. The
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
                  trailing: s.currentPlan == p.code && s.currentStatus != 'PENDING_PAYMENT'
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A))
                      : s.payable.contains(p.code)
                          ? FilledButton(
                              key: ValueKey('askodoxPlanPay-${p.code}'),
                              onPressed: () => _pay(context, ref, p, t),
                              child: Text(s.paymentMode == 'test' ? t('Pay (test)', 'చెల్లించు (టెస్ట్)') : t('Pay', 'చెల్లించు')))
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
          if (s.paymentMode == 'test' && s.payable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  t('TEST MODE: no real money. Use Razorpay test card / test UPI only.',
                      'టెస్ట్ మోడ్: నిజమైన డబ్బు కాదు. Razorpay టెస్ట్ కార్డ్ / టెస్ట్ UPI మాత్రమే వాడండి.'),
                  key: const Key('askodoxPlansTestMode'),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                t('Card / UPI details are entered only on Razorpay\'s page. Paid plans open once billing is approved.',
                    'కార్డ్ / UPI వివరాలు Razorpay పేజీలో మాత్రమే. బిల్లింగ్ ఆమోదం తర్వాతే పెయిడ్ ప్లాన్లు.'),
                key: const Key('askodoxPlansBillingNote'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
          ),
        ]),
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, AskodoxPlan p, String Function(String, String) t) async {
    final repo = ref.read(plansRepositoryProvider);
    final started = await repo.startCheckout(p.code);
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
        builder: (_) => _PaymentStatusDialog(purchaseId: started.purchaseId!, repo: repo, t: t));
    ref.invalidate(plansProvider);
  }
}

/// Shows the server's status for one purchase; "Check status" asks again
/// (the server reads it back from Razorpay). Nothing here marks a payment paid.
class _PaymentStatusDialog extends StatefulWidget {
  const _PaymentStatusDialog({required this.purchaseId, required this.repo, required this.t});
  final String purchaseId;
  final PlansRepository repo;
  final String Function(String, String) t;

  @override
  State<_PaymentStatusDialog> createState() => _PaymentStatusDialogState();
}

class _PaymentStatusDialogState extends State<_PaymentStatusDialog> {
  String? _status;
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    final s = await widget.repo.purchaseStatus(widget.purchaseId);
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final text = switch (_status) {
      null => t('Finish the payment on the Razorpay page, then tap Check status.',
          'Razorpay పేజీలో చెల్లింపు పూర్తి చేసి, Check status నొక్కండి.'),
      'ACTIVE' => t('Paid. Your plan is active.', 'చెల్లింపు అయింది. మీ ప్లాన్ యాక్టివ్.'),
      'PENDING' => t('Not confirmed yet. If you paid, wait a moment and check again.',
          'ఇంకా నిర్ధారణ కాలేదు. చెల్లించి ఉంటే కొద్దిసేపు ఆగి మళ్లీ చూడండి.'),
      'CANCELLED' => t('Checkout was closed. No payment was confirmed.', 'చెక్‌అవుట్ మూసేశారు. చెల్లింపు నిర్ధారణ కాలేదు.'),
      _ => '${t('Status', 'స్థితి')}: $_status',
    };
    return AlertDialog(
      title: Text(t('Payment status', 'చెల్లింపు స్థితి')),
      content: Text(text, key: const Key('askodoxPayStatusText')),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('Close', 'మూసివేయి'))),
        FilledButton(
            key: const Key('askodoxPayCheck'),
            onPressed: _busy ? null : _check,
            child: Text(t('Check status', 'స్థితి చూడండి'))),
      ],
    );
  }
}
