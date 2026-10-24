import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/intelligence_repository.dart';

/// The round 2 card under an assistant reply: tax / GST facts, a scam
/// checklist, an awareness-only answer, or a smart-trick calculator link.
/// Always shows its official sources and the date they were checked.
class AskodoxIntelligenceCard extends StatelessWidget {
  const AskodoxIntelligenceCard({super.key, required this.intelligence, required this.te, required this.onOpen});

  final Map<String, Object?> intelligence;
  final bool te;
  final void Function(String route) onOpen;

  static Color accentFor(String kind) => switch (kind) {
        'fraud' || 'fraud_refusal' || 'tax_evasion_awareness' => const Color(0xFFB45309),
        'smart_tricks' => const Color(0xFF15803D),
        _ => const Color(0xFF1769FF),
      };

  static IconData iconFor(String kind) => switch (kind) {
        'fraud' || 'fraud_refusal' => Icons.gpp_maybe_outlined,
        'tax_evasion_awareness' => Icons.policy_outlined,
        'smart_tricks' => Icons.savings_outlined,
        'gst' => Icons.receipt_long_outlined,
        _ => Icons.account_balance_outlined,
      };

  Widget _bullets(List<String> lines) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(padding: const EdgeInsets.only(top: 3), child: Text('• $line', style: const TextStyle(fontSize: 13))),
        ],
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  List<String> _strings(Object? v) => [for (final x in askodoxList(v)) askodoxStr(x)].where((s) => s.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final kind = askodoxStr(intelligence['kind']);
    final color = accentFor(kind);
    final scheme = askodoxMap(intelligence['scheme']);
    final sources = [for (final s in askodoxList(intelligence['sources'])) askodoxMap(s)];
    final schemeChannels = [for (final c in askodoxList(scheme['report'])) askodoxMap(c)];
    final action = askodoxMap(intelligence['action']);
    final route = askodoxStr(action['route']);
    final verified = askodoxStr(intelligence['verified_on'] ?? scheme['verified_on']);
    return Container(
      key: ValueKey('askodoxIntel-$kind'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(iconFor(kind), color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(askodoxStr(intelligence['title']),
                style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
          ),
        ]),
        if (askodoxStr(intelligence['refusal']).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(askodoxStr(intelligence['refusal']))),
        if (askodoxStr(intelligence['summary']).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(askodoxStr(intelligence['summary']))),
        if (askodoxStr(intelligence['year_label']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${askodoxStr(intelligence['year_label'])} · ${askodoxStr(intelligence['law'])}',
                style: const TextStyle(fontSize: 12)),
          ),
        if (_strings(intelligence['facts']).isNotEmpty) _bullets(_strings(intelligence['facts'])),
        if (scheme.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(askodoxStr(scheme['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          _heading(te ? 'హెచ్చరిక సంకేతాలు' : 'Warning signs'),
          _bullets(_strings(scheme['warning_signs'])),
          _heading(te ? 'ఎలా నిర్ధారించుకోవాలి' : 'How to verify'),
          _bullets(_strings(scheme['verify'])),
          _heading(te ? 'ఫిర్యాదు ఎక్కడ' : 'Where to report'),
          _bullets([for (final c in schemeChannels) askodoxStr(c['name'])]),
        ],
        if (askodoxList(intelligence['awareness']).isNotEmpty) ...[
          _heading(te ? 'ఇవి ఎలా పట్టుబడతాయి' : 'How these are caught and what they cost'),
          _bullets([
            for (final a in askodoxList(intelligence['awareness']))
              '${askodoxStr(askodoxMap(a)['practice'])}: ${askodoxStr(askodoxMap(a)['consequence'])}',
          ]),
        ],
        if (_strings(intelligence['lawful_planning']).isNotEmpty) ...[
          _heading(te ? 'చట్టబద్ధంగా పన్ను తగ్గించుకోవడం' : 'Lawful ways to reduce tax'),
          _bullets(_strings(intelligence['lawful_planning'])),
        ],
        if (askodoxStr(intelligence['evidence_rule']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(askodoxStr(intelligence['evidence_rule']), style: const TextStyle(fontSize: 12)),
          ),
        if (sources.isNotEmpty) ...[
          _heading(te ? 'అధికారిక మూలాలు' : 'Official sources'),
          for (final source in sources.take(4))
            InkWell(
              onTap: () => launchUrl(Uri.parse(askodoxStr(source['url'])), mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(askodoxStr(source['title']),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1769FF), decoration: TextDecoration.underline)),
              ),
            ),
        ],
        if (verified.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(te ? 'ధృవీకరించిన తేదీ: $verified' : 'Checked against official sources on $verified',
                style: const TextStyle(fontSize: 11.5)),
          ),
        if (askodoxStr(intelligence['professional_note']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(askodoxStr(intelligence['professional_note']), style: const TextStyle(fontSize: 11.5)),
          ),
        if (route.startsWith('/'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              key: ValueKey('askodoxIntelOpen-$kind'),
              onPressed: () => onOpen(route),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(askodoxStr(action['label'])),
            ),
          ),
      ]),
    );
  }
}
