import 'package:flutter/material.dart';

import '../domain/result_board_tabs.dart';

/// ONE horizontal row at the top of the Result Board:
/// Result Board | Local | Online | Deals | Reviews | Videos, then Expand and
/// Minimize. The tabs scroll sideways; the selected tab's cards appear right
/// below it. Keys `askodoxResultBoardMinimize` / `askodoxResultBoardMega`
/// are approved (docs/approved_features.json) -- keep them.
class AskodoxResultBoardTabRow extends StatelessWidget {
  const AskodoxResultBoardTabRow({
    super.key,
    required this.selected,
    required this.counts,
    required this.lang,
    required this.onSelect,
    required this.onMinimize,
    required this.onExpand,
    this.expanded = false,
  });

  final AskodoxBoardTab selected;
  final Map<AskodoxBoardTab, int> counts;
  final String lang;
  final ValueChanged<AskodoxBoardTab> onSelect;
  final VoidCallback onMinimize;
  final VoidCallback onExpand;
  final bool expanded;

  static const _ink = Color(0xFF10204A);
  static const _accent = Color(0xFF1769FF);

  @override
  Widget build(BuildContext context) {
    final te = lang == 'te';
    return SizedBox(
      height: 40,
      child: Row(children: [
        Expanded(
          child: ListView(
            key: const Key('askodoxResultBoardTabs'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            children: [
              for (final tab in AskodoxBoardTab.values) _tab(tab),
            ],
          ),
        ),
        IconButton(
          key: const Key('askodoxResultBoardMega'),
          tooltip: expanded ? (te ? 'తక్కువ' : 'Less') : (te ? 'పూర్తిగా చూపు' : 'Expand'),
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onExpand,
          icon: Icon(expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, color: _ink),
        ),
        IconButton(
          key: const Key('askodoxResultBoardMinimize'),
          tooltip: te ? 'చిన్నదిగా చేయి' : 'Minimize',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onMinimize,
          icon: const Icon(Icons.keyboard_arrow_up_rounded, color: _ink),
        ),
      ]),
    );
  }

  Widget _tab(AskodoxBoardTab tab) {
    final on = tab == selected;
    final count = counts[tab] ?? 0;
    final label = askodoxBoardTabLabel(tab, lang);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: ValueKey('askodoxBoardTab-${tab.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelect(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? _accent : const Color(0xFFDCE4F0)),
          ),
          alignment: Alignment.center,
          child: Text(
            tab == AskodoxBoardTab.all || count == 0 ? label : '$label $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : (count == 0 && tab != AskodoxBoardTab.all ? const Color(0xFF98A2B3) : _ink),
            ),
          ),
        ),
      ),
    );
  }
}
