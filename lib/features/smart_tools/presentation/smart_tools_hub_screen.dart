import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/smart_tool_catalog.dart';
import 'smart_tool_widgets.dart';

/// Smart Tools hub: every tool from the ONE registry, grouped, each with an
/// honest readiness label. Only built tools open; the rest explain what they
/// need. Reached from Profile and from chat ("how many bricks ...").
class AskodoxSmartToolsHubScreen extends StatelessWidget {
  const AskodoxSmartToolsHubScreen({super.key});

  static String groupLabel(AskodoxToolGroup group, bool te) => switch (group) {
        AskodoxToolGroup.measure => te ? 'కొలతలు & ప్లానింగ్' : 'Measure & plan',
        AskodoxToolGroup.construction => te ? 'నిర్మాణ మెటీరియల్ లెక్కలు' : 'Construction materials',
        AskodoxToolGroup.inspect => te ? 'ఫోటో పరిశీలన' : 'Photo inspection',
        AskodoxToolGroup.sensors => te ? 'ఫోన్ సెన్సార్లు' : 'Phone sensors',
        AskodoxToolGroup.devices => te ? 'బయటి పరికరాలు' : 'External devices',
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్మార్ట్ టూల్స్' : 'Smart Tools')),
      body: ListView(
        key: const Key('askodoxSmartToolsHub'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              te
                  ? 'అంచనాలు మాత్రమే — సర్టిఫైడ్ కొలత పరికరాలు లేదా ఇంజనీర్ / నిపుణుల స్థానాన్ని భర్తీ చేయవు.'
                  : 'Estimates only — they never replace certified instruments, an engineer or an expert.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
          for (final group in AskodoxToolGroup.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(groupLabel(group, te), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            for (final tool in askodoxSmartTools.where((t) => t.group == group)) _ToolTile(tool: tool, te: te),
          ],
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, required this.te});
  final AskodoxSmartTool tool;
  final bool te;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opens = tool.opens;
    final color = switch (tool.readiness) {
      AskodoxToolReadiness.ready => const Color(0xFF15803D),
      AskodoxToolReadiness.hardwareUnverified => const Color(0xFFB45309),
      _ => scheme.onSurfaceVariant,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        key: ValueKey('askodoxTool-${tool.id}'),
        enabled: true,
        title: Text(tool.name(te),
            style: TextStyle(fontWeight: FontWeight.w700, color: opens ? null : scheme.onSurfaceVariant)),
        subtitle: Text(askodoxReadinessLabel(tool.readiness, te), style: TextStyle(color: color, fontSize: 12.5)),
        trailing: Icon(opens ? Icons.chevron_right_rounded : Icons.info_outline_rounded),
        onTap: () {
          if (opens) {
            context.push(tool.route!);
          } else {
            _explain(context);
          }
        },
      ),
    );
  }

  void _explain(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        key: ValueKey('askodoxToolInfo-${tool.id}'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tool.name(te), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 6),
          Text(askodoxReadinessLabel(tool.readiness, te)),
          const SizedBox(height: 10),
          Text(te ? 'దీనికి కావలసినవి:' : 'What it needs:', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final need in tool.needs) Text('• ${askodoxNeedLabel(need, te)}'),
          const SizedBox(height: 10),
          Text(te
              ? 'ఇది ఇంకా ఈ యాప్‌లో పని చేయదు. పని చేస్తున్నట్లు చూపించము.'
              : 'This does not work in the app yet; ASKODOX will not pretend it does.'),
        ]),
      ),
    );
  }
}
