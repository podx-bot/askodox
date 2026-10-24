import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/guide/in_app_guide.dart';
import 'askodox_mascot.dart';

/// ASKODOX Navigator: ONE compact grouped-section look for Profile, My
/// Business, Listings and every nested page -- a small heading with an icon,
/// then one rounded card of rows (no card per row, no tall empty gaps).
///
/// Every [AskodoxNavRow] without a trailing control is drawn as a tile of the
/// shared POS-dashboard look (2 columns, 3 on wide screens: icon + bold title +
/// one line); any other child (switches, chips, rows with a value) stays a
/// full-width list above the tiles. [grid] is kept for callers; both modes now
/// draw the same tiles.
class AskodoxNavSection extends StatelessWidget {
  const AskodoxNavSection(
      {super.key, required this.title, required this.icon, required this.children, this.grid = false, this.mascot});

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool grid;

  /// The teammate shown next to the heading (BIZZO for business, ...).
  final AskodoxMascotRole? mascot;

  static const ink = Color(0xFF10204A);
  static const accent = Color(0xFF1769FF);

  @override
  Widget build(BuildContext context) {
    final rows = [for (final c in children) if (c is! SizedBox || c.child != null) c];
    if (rows.isEmpty) return const SizedBox.shrink();
    if (grid || rows.any((r) => r is AskodoxNavRow && r.trailing == null)) return _gridSection(rows);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E9F3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 52, color: Color(0xFFEEF2F7)),
                  row,
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

extension on AskodoxNavSection {
  Widget _gridSection(List<Widget> rows) {
    final tiles = [for (final r in rows) if (r is AskodoxNavRow && r.trailing == null) r];
    final others = [for (final r in rows) if (r is! AskodoxNavRow || r.trailing != null) r];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            if (mascot != null)
              AskodoxMascot(role: mascot!, size: 30)
            else
              Icon(icon, size: 18, color: AskodoxNavSection.accent),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: AskodoxNavSection.ink, fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
        ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE3E9F3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(type: MaterialType.transparency, child: Column(children: others)),
              ),
            ),
          ),
        if (tiles.isNotEmpty)
          LayoutBuilder(builder: (context, box) {
            final columns = box.maxWidth >= 720 ? 3 : 2;
            const gap = 10.0;
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final t in tiles) SizedBox(width: width, child: AskodoxNavTile(row: t)),
            ]);
          }),
      ]),
    );
  }
}

/// A [AskodoxNavRow] drawn as a grid tile: icon, title, a short line about
/// what opens, and (when the row has a guide) a small "Guide" button that
/// walks the person through that screen -- what to fill and where.
class AskodoxNavTile extends ConsumerWidget {
  const AskodoxNavTile({super.key, required this.row});
  final AskodoxNavRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final flow = row.guide == null ? null : askodoxGuideById(row.guide!);
    return KeyedSubtree(
      key: row.key,
      child: Tooltip(
        message: row.subtitle ?? row.title,
        triggerMode: TooltipTriggerMode.longPress,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE3E9F3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: row.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Icon(row.icon, color: AskodoxNavSection.ink, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(row.title,
                        style: const TextStyle(
                            color: AskodoxNavSection.ink, fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                    if (row.subtitle != null && row.subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(row.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF667085))),
                      ),
                  ]),
                ),
                if (flow != null)
                  Tooltip(
                    message: te ? 'గైడ్: ఇక్కడ ఏం చేయాలి' : 'Guide: what to do here',
                    child: InkResponse(
                      key: ValueKey('askodoxTileGuide-${row.guide}'),
                      radius: 20,
                      onTap: () => ref.read(askodoxGuideProvider.notifier).start(flow),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: AskodoxMascot(size: 24),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a [AskodoxNavSection]: icon, title, optional one-line subtitle,
/// and a real destination ([onTap]) -- never a dead row.
class AskodoxNavRow extends StatelessWidget {
  const AskodoxNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.guide,
  });

  /// Id of the in-app guide flow for this destination (Guide button).
  final String? guide;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(icon, color: AskodoxNavSection.accent, size: 22),
        title: Text(title,
            style: const TextStyle(color: AskodoxNavSection.ink, fontWeight: FontWeight.w800, fontSize: 14.5)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
        onTap: onTap,
      );
}
