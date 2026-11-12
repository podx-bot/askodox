import 'package:flutter/material.dart';

import '../domain/payment_alert_setup.dart';

/// The payment-sound setup at the top of the payment alerts screen: progress, then ONE question with "OK" and
/// "Not now". Every step the phone can check is checked again when the person comes back from Android settings.
class AskodoxPayAlertSetupCard extends StatelessWidget {
  const AskodoxPayAlertSetupCard({
    super.key,
    required this.steps,
    required this.next,
    required this.te,
    required this.onOk,
    required this.onLater,
    required this.onHeard,
    this.maker = '',
    this.askHeard = false,
    this.notHeard = false,
    this.busy = false,
  });

  final List<AskodoxPayAlertSetupStep> steps;
  final AskodoxPayAlertSetupStep? next;
  final bool te;
  final String maker;
  final bool askHeard;
  final bool notHeard;
  final bool busy;
  final void Function(AskodoxPayAlertSetupStep step) onOk;
  final void Function(AskodoxPayAlertSetupStep step) onLater;
  final void Function(bool heard) onHeard;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final done = steps.where((s) => s.done).length;
    final step = next;
    if (step == null) {
      final all = done == steps.length;
      return Card(
        key: const Key('askodoxPayAlertSetupDone'),
        color: all ? const Color(0xFFF0FDF4) : null,
        child: ListTile(
          leading: Icon(all ? Icons.check_circle : Icons.schedule, color: all ? const Color(0xFF15803D) : null),
          title: Text(all
              ? (te ? 'అన్నీ రెడీ. పేమెంట్ వస్తే ఈ ఫోన్ మాట్లాడుతుంది.' : 'All set. This phone speaks when a payment comes.')
              : (te ? 'సెటప్ $done/${steps.length}. మిగతావి తర్వాత అడుగుతాం.' : 'Setup $done/${steps.length}. The rest is asked next time.')),
        ),
      );
    }
    final (question, how) = askodoxPayAlertStepText(step, te: te, maker: maker);
    final sound = step.kind == 'sound';
    return Card(
      key: const Key('askodoxPayAlertSetup'),
      color: const Color(0xFFF5F3FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'సెటప్ ${done + 1}/${steps.length}' : 'Setup ${done + 1}/${steps.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: done / steps.length),
          const SizedBox(height: 12),
          Text(question, key: const Key('askodoxPayAlertSetupQuestion'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(how),
          if (sound && notHeard) ...[
            const SizedBox(height: 8),
            Text(
              te
                  ? 'చూడండి: 1) వాల్యూమ్ బటన్ తో Media వాల్యూమ్ పెంచండి. 2) బ్లూటూత్ స్పీకర్ కనెక్ట్ అయి ఉంటే అక్కడ వస్తుంది. '
                      '3) Settings → Text-to-speech లో Google ఇంజిన్ ఎంచుకోండి. తర్వాత మళ్ళీ ఓకే నొక్కండి.'
                  : 'Check: 1) raise the Media volume with the volume button. 2) a connected Bluetooth speaker plays it there. '
                      '3) choose the Google engine in Settings → Text-to-speech. Then tap OK again.',
              key: const Key('askodoxPayAlertSetupSoundHelp'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309)),
            ),
          ],
          const SizedBox(height: 12),
          if (sound && askHeard)
            Row(children: [
              Expanded(
                child: FilledButton(
                    key: const Key('askodoxPayAlertSetupHeardYes'),
                    onPressed: () => onHeard(true),
                    child: Text(te ? 'వినిపించింది' : 'I heard it')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                    key: const Key('askodoxPayAlertSetupHeardNo'),
                    onPressed: () => onHeard(false),
                    child: Text(te ? 'వినిపించలేదు' : 'Did not hear')),
              ),
            ])
          else
            Row(children: [
              if (!step.ownerOnly)
                Expanded(
                  child: FilledButton(
                      key: const Key('askodoxPayAlertSetupOk'),
                      onPressed: busy ? null : () => onOk(step),
                      child: Text(te ? 'ఓకే' : 'OK')),
                ),
              if (!step.ownerOnly) const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                    key: const Key('askodoxPayAlertSetupLater'),
                    onPressed: () => onLater(step),
                    child: Text(te ? 'ఇప్పుడు వద్దు' : 'Not now')),
              ),
            ]),
        ]),
      ),
    );
  }
}
