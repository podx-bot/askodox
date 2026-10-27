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
                    if (s.payable.contains(p.code))
                      s.paymentMode == 'test'
                          ? t('Test payment available', 'టెస్ట్ చెల్లింపు అందుబాటులో ఉంది')
                          : t('Available', 'అందుబాటులో ఉంది')
                    else if (!p.available)
                      t('Not available yet', 'ఇంకా అందుబాటులో లేదు'),
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
          if (_payNote(s, t) case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(note,
                  key: const Key('askodoxPlansPayNote'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475467))),
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

  /// Why there is no Pay button, from the SERVER's answer (never guessed).
  static String? _payNote(AskodoxPlansState s, String Function(String, String) t) {
    if (s.paymentNeedsSignIn) {
      return t('Sign in again to see payment options.', 'చెల్లింపు ఎంపికలు చూడడానికి మళ్లీ సైన్ ఇన్ చేయండి.');
    }
    if (s.payable.isNotEmpty) return null;
    final reasons = s.payReasons.values.toSet();
    if (reasons.contains('TEST_MODE_TESTERS_ONLY')) {
      final who = s.accountLast4.isEmpty ? '' : ' (••••${s.accountLast4})';
      return t(
          'Payments are in TEST mode: only billing testers chosen by staff can pay. '
              'This account$who is not on the billing tester list.',
          'చెల్లింపులు టెస్ట్ మోడ్‌లో ఉన్నాయి: స్టాఫ్ ఎంచుకున్న బిల్లింగ్ టెస్టర్లు మాత్రమే చెల్లించగలరు. '
              'ఈ అకౌంట్$who బిల్లింగ్ టెస్టర్ జాబితాలో లేదు.');
    }
    if (reasons.contains('NO_PAYMENT_GATEWAY')) {
      return t('Online payment is not available yet.', 'ఆన్‌లైన్ చెల్లింపు ఇంకా అందుబాటులో లేదు.');
    }
    return null;
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
        builder: (_) => AskodoxPaymentStatusDialog(purchaseId: started.purchaseId!, repo: repo, t: t));
    ref.invalidate(plansProvider);
  }
}

/// Shows the server's status for one purchase; "Check status" asks again
/// (the server reads it back from Razorpay). Nothing here marks a payment paid.
class AskodoxPaymentStatusDialog extends StatefulWidget {
  const AskodoxPaymentStatusDialog(
      {super.key, required this.purchaseId, required this.repo, required this.t, this.credits = false});
  final String purchaseId;

  /// AI Credits pack instead of a plan (different words for ACTIVE / TEST_PAID).
  final bool credits;
  final PlansRepository repo;
  final String Function(String, String) t;

  @override
  State<AskodoxPaymentStatusDialog> createState() => AskodoxPaymentStatusDialogState();
}

class AskodoxPaymentStatusDialogState extends State<AskodoxPaymentStatusDialog> {
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
      'ACTIVE' when widget.credits =>
        t('Paid. AI Credits were added to your balance.', 'చెల్లింపు అయింది. AI Credits మీ బ్యాలెన్స్‌లో చేరాయి.'),
      'TEST_PAID' when widget.credits => t('Test payment confirmed: TEST credits added (sandbox money, not real).',
          'టెస్ట్ చెల్లింపు నిర్ధారణ: TEST credits చేరాయి (sandbox, నిజమైన డబ్బు కాదు).'),
      'ACTIVE' => t('Paid. Your plan is active.', 'చెల్లింపు అయింది. మీ ప్లాన్ యాక్టివ్.'),
      'TEST_PAID' => t('Test payment confirmed. TEST mode: no plan was activated.',
          'టెస్ట్ చెల్లింపు నిర్ధారణ అయింది. టెస్ట్ మోడ్: ఏ ప్లాన్ యాక్టివ్ కాలేదు.'),
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
