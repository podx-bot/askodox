import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/media_picker.dart';
import '../../../shared/widgets/navigator_section.dart';
import '../data/kyc_repository.dart';

/// Verification (KYC): level + badges (completed verification only), consent
/// first, documents read by AI (shown masked; never "verified" by AI), and
/// what each activity needs. Basic features never need full KYC.
class AskodoxKycScreen extends ConsumerWidget {
  const AskodoxKycScreen({super.key});

  static const _activities = {
    'buy': ('Buy & request', 'కొనుగోలు & అభ్యర్థన'),
    'sell': ('Sell', 'అమ్మకం'),
    'receive_payouts': ('Receive payouts', 'చెల్లింపులు స్వీకరించడం'),
    'business_badge': ('Business badge', 'వ్యాపార బ్యాడ్జ్'),
    'professional_badge': ('Professional badge', 'ప్రొఫెషనల్ బ్యాడ్జ్'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final state = ref.watch(kycProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Verification', 'ధృవీకరణ'))),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(t('Sign in to see your verification.', 'ధృవీకరణ చూడడానికి సైన్ ఇన్ చేయండి.'))),
        data: (s) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Text('${t('Level', 'స్థాయి')} ${s.level} · ${s.levelLabel}',
              key: const Key('askodoxKycLevel'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Wrap(spacing: 6, children: [
            for (final b in s.badges) Chip(label: Text(b), avatar: const Icon(Icons.verified, size: 16)),
          ]),
          AskodoxNavSection(
            title: t('What each activity needs', 'ప్రతి పనికి ఏం కావాలి'),
            icon: Icons.checklist_rounded,
            children: [
              for (final a in _activities.entries)
                if (s.requirements.containsKey(a.key))
                  ListTile(
                    dense: true,
                    title: Text(te ? a.value.$2 : a.value.$1),
                    trailing: Icon(s.requirements[a.key]! ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: s.requirements[a.key]! ? const Color(0xFF16A34A) : const Color(0xFF98A2B3)),
                  ),
            ],
          ),
          if (!s.consent)
            Card(
              key: const Key('askodoxKycConsent'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.consentText),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('askodoxKycAccept'),
                    onPressed: () async {
                      await ref.read(kycRepositoryProvider).consent(s.consentVersion);
                      ref.invalidate(kycProvider);
                    },
                    child: Text(t('I agree', 'నేను అంగీకరిస్తున్నాను')),
                  ),
                ]),
              ),
            )
          else ...[
            FilledButton.icon(
              key: const Key('askodoxKycAddDocument'),
              icon: const Icon(Icons.upload_file),
              label: Text(t('Add a document', 'పత్రం జోడించండి')),
              onPressed: () => _add(context, ref, t),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  t('PAN card, GST certificate, bank proof, business registration or professional licence. '
                      'Do not upload Aadhaar: use DigiLocker when it is enabled.',
                      'PAN కార్డ్, GST సర్టిఫికెట్, బ్యాంక్ ప్రూఫ్, వ్యాపార నమోదు లేదా ప్రొఫెషనల్ లైసెన్స్. '
                          'ఆధార్ అప్‌లోడ్ చేయవద్దు.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
            ),
          ],
          for (final c in s.checks)
            Card(
              key: ValueKey('askodoxKycCheck-${c.id}'),
              child: ListTile(
                title: Text('${c.label} · ${_status(c.status, t)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (c.fields.isNotEmpty) c.fields.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                  ...c.issues,
                  ...c.nextSteps,
                ].join('\n')),
              ),
            ),
          if (s.consent)
            TextButton(
              key: const Key('askodoxKycWithdraw'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                          content: Text(t('Withdraw consent? Your stored verification details will be deleted.',
                              'అనుమతి ఉపసంహరించాలా? మీ ధృవీకరణ వివరాలు తొలగించబడతాయి.')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(t('Cancel', 'రద్దు'))),
                            FilledButton(
                                key: const Key('askodoxKycWithdrawConfirm'),
                                onPressed: () => Navigator.pop(dialog, true),
                                child: Text(t('Withdraw', 'ఉపసంహరించు'))),
                          ],
                        ));
                if (ok == true) {
                  await ref.read(kycRepositoryProvider).withdraw();
                  ref.invalidate(kycProvider);
                }
              },
              child: Text(t('Withdraw consent & delete details', 'అనుమతి ఉపసంహరించి వివరాలు తొలగించండి')),
            ),
        ]),
      ),
    );
  }

  static String _status(String status, String Function(String, String) t) => switch (status) {
        'VERIFIED' => t('Verified', 'ధృవీకరించబడింది'),
        'AWAITING_PROVIDER' => t('Waiting for a verification provider', 'ధృవీకరణ ప్రొవైడర్ కోసం వేచి ఉంది'),
        'NEEDS_REVIEW' => t('Needs review', 'సమీక్ష అవసరం'),
        'REJECTED' => t('Not accepted', 'అంగీకరించలేదు'),
        'EXPIRED' => t('Expired', 'గడువు ముగిసింది'),
        _ => t('Read, not verified', 'చదివాం, ధృవీకరించలేదు'),
      };

  Future<void> _add(BuildContext context, WidgetRef ref, String Function(String, String) t) async {
    final picked = await ref.read(askodoxMediaPickerProvider).pick('files');
    if (picked.isEmpty || !context.mounted) return;
    final file = picked.first;
    final result = await ref.read(kycRepositoryProvider).submit(file.bytes, name: file.name, mimeType: file.mimeType);
    ref.invalidate(kycProvider);
    if (!context.mounted) return;
    final said = [...result.issues, ...result.nextSteps].join(' ').trim();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const Key('askodoxKycResult'),
        content: Text(result.error != null
            ? t('Could not read the document.', 'పత్రం చదవలేకపోయాం.')
            : said.isEmpty
                ? t('Document read.', 'పత్రం చదివాం.')
                : said)));
  }
}
