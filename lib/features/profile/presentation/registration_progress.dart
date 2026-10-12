import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/registration_repository.dart';

/// My Roles -> registration progress: each held role is a DRAFT until its
/// required details exist; a complete role can ask staff for verification
/// (only the reference's last 4 characters are kept). Hidden when signed out.
class AskodoxRegistrationProgress extends ConsumerWidget {
  const AskodoxRegistrationProgress({super.key});

  static const kinds = ['gstin', 'fssai', 'driving_licence', 'vehicle_rc', 'trade_licence', 'udyam', 'other'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final reg = ref.watch(registrationProvider).valueOrNull;
    if (reg == null || (reg.roles.isEmpty && reg.basicsMissing.isEmpty)) return const SizedBox.shrink();
    String verificationText(String v) => switch (v) {
          'verified' => t('Verified', 'ధృవీకరించబడింది'),
          'pending' => t('Verification requested', 'ధృవీకరణ కోరారు'),
          'rejected' => t('Verification not approved', 'ధృవీకరణ ఆమోదం కాలేదు'),
          _ => t('Not verified', 'ధృవీకరణ లేదు'),
        };
    return Card(
      key: const Key('askodoxRegistrationProgress'),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Registration', 'నమోదు'), style: Theme.of(context).textTheme.titleSmall),
          if (reg.basicsMissing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  t('Still needed in your profile: ', 'ప్రొఫైల్‌లో ఇంకా కావాలి: ') +
                      reg.basicsMissing.map(askodoxFieldLabel).join(', '),
                  key: const Key('askodoxRegistrationBasics')),
            ),
          for (final r in reg.roles)
            ListTile(
              key: ValueKey('askodoxRegistrationRole-${r.role}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(r.status == 'complete' ? Icons.check_circle_outline_rounded : Icons.edit_note_rounded,
                  color: r.status == 'complete' ? const Color(0xFF16A34A) : const Color(0xFFB45309)),
              title: Text(askodoxFieldLabel(r.role)),
              subtitle: Text(r.status == 'complete'
                  ? verificationText(r.verification)
                  : t('Draft -- add: ', 'డ్రాఫ్ట్ -- జోడించండి: ') + r.missing.map(askodoxFieldLabel).join(', ')),
              trailing: r.status != 'complete'
                  ? TextButton(onPressed: () => context.go('/profile'), child: Text(t('Complete', 'పూర్తి చేయండి')))
                  : r.canRequestVerification
                      ? TextButton(
                          key: ValueKey('askodoxRequestVerification-${r.role}'),
                          onPressed: () => _request(context, ref, r.role, te),
                          child: Text(t('Verify', 'ధృవీకరించండి')),
                        )
                      : null,
            ),
        ]),
      ),
    );
  }

  Future<void> _request(BuildContext context, WidgetRef ref, String role, bool te) async {
    var kind = 'other';
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text(te ? 'ధృవీకరణ కోరండి' : 'Request verification'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              key: const Key('askodoxVerificationKind'),
              isExpanded: true,
              value: kind,
              items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(askodoxFieldLabel(k)))],
              onChanged: (v) => setState(() => kind = v ?? 'other'),
            ),
            TextField(
              key: const Key('askodoxVerificationReference'),
              controller: reference,
              maxLength: 40,
              decoration: InputDecoration(
                  labelText: te ? 'నంబర్ (చివరి 4 అక్షరాలు మాత్రమే ఉంచుతాం)' : 'Number (only the last 4 are kept)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxVerificationSend'),
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(te ? 'పంపండి' : 'Send')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final state = await ref
        .read(registrationRepositoryProvider)
        .requestVerification(role, kind: kind, reference: reference.text.trim());
    ref.invalidate(registrationProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(state == null
            ? (te ? 'ఇప్పుడు పంపలేకపోయాం.' : 'Could not send right now.')
            : (te ? 'ధృవీకరణ కోరబడింది.' : 'Verification requested.'))));
  }
}
