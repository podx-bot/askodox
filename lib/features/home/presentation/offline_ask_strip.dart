import 'package:flutter/material.dart';

import '../../../core/net/net_quality.dart';
import '../domain/offline_questions.dart';

/// Owner 2026-11-23 (ASKODOX Lite step 3): with no net, the questions the phone can answer by itself sit ready above
/// the composer (one tap = asked), next to how many other questions wait for the net. Nothing on a working net with
/// nothing waiting.
class AskodoxOfflineAskStrip extends StatelessWidget {
  const AskodoxOfflineAskStrip({super.key, required this.lang, required this.onAsk});
  final String lang;
  final void Function(String question) onAsk;

  static const _ink = Color(0xFF9A4A07);
  static const _paper = Color(0xFFFFF1E0);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AskodoxNet>(
        valueListenable: AskodoxNetQuality.instance.state,
        builder: (context, net, _) => ValueListenableBuilder<int>(
          valueListenable: AskodoxHeldQuestions.instance.count,
          builder: (context, waiting, _) {
            final offline = net == AskodoxNet.offline;
            if (!offline && waiting == 0) return const SizedBox.shrink();
            final te = lang == 'te', hi = lang == 'hi';
            final held = waiting == 0
                ? null
                : offline
                    ? (te
                        ? '$waiting ప్రశ్న${waiting > 1 ? 'లు' : ''} net కోసం ఆగి ఉన్నాయి'
                        : hi
                            ? '$waiting सवाल net के लिए रुके हैं'
                            : '$waiting question${waiting > 1 ? 's' : ''} waiting for the net')
                    : (te ? 'Net వచ్చింది · జవాబులు వస్తున్నాయి…' : hi ? 'Net आ गया · जवाब आ रहे हैं…' : 'Net is back · answers coming…');
            return SizedBox(
              key: const Key('askodoxOfflineAskStrip'),
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                children: [
                  if (held != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        key: const Key('askodoxOfflineHeld'),
                        avatar: Icon(offline ? Icons.schedule_rounded : Icons.sync_rounded, size: 16, color: _ink),
                        label: Text(held, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                        backgroundColor: _paper,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                    ),
                  if (offline)
                    for (final (i, q) in askodoxOfflineReadyQuestions(lang).indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          key: Key('askodoxOfflineAsk-$i'),
                          label: Text(q, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onAsk(q),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      );
}
