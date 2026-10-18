import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/guide/in_app_guide.dart';

/// ASKODOX Navigator: ONE compact grouped-section look for Profile, My
/// Business, Listings and every nested page -- a small heading with an icon,
/// then one rounded card of rows (no card per row, no tall empty gaps).
///
/// [grid]: the [AskodoxNavRow]s become a neat 2-column grid of tiles (3 on
/// wide screens); any other child (switches, chips) stays a full-width list
/// above the grid.
class AskodoxNavSection extends StatelessWidget {
  const AskodoxNavSection(
      {super.key, required this.title, required this.icon, required this.children, this.grid = false});

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool grid;

  static const ink = Color(0xFF10204A);
  static const accent = Color(0xFF1769FF);

  @override
  Widget build(BuildContext context) {
    final rows = [for (final c in children) if (c is! SizedBox || c.child != null) c];
    if (rows.isEmpty) return const SizedBox.shrink();
    if (grid) return _gridSection(rows);
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
    final tiles = [for (final r in rows) if (r is AskodoxNavRow) r];
    final others = [for (final r in rows) if (r is! AskodoxNavRow) r];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
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
            final columns = box.maxWidth >= 600 ? 3 : 2;
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
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: row.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 118),
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE3E9F3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(12)),
                  child: Icon(row.icon, color: AskodoxNavSection.accent, size: 22),
                ),
                const Spacer(),
                if (flow != null)
                  Tooltip(
                    message: te ? 'గైడ్: ఇక్కడ ఏం చేయాలి' : 'Guide: what to do here',
                    child: InkResponse(
                      key: ValueKey('askodoxTileGuide-${row.guide}'),
                      radius: 22,
                      onTap: () => ref.read(askodoxGuideProvider.notifier).start(flow),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF1ECFF), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.face_retouching_natural, size: 14, color: Color(0xFF6C4DFF)),
                          const SizedBox(width: 3),
                          Text(te ? 'గైడ్' : 'Guide',
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF6C4DFF))),
                        ]),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AskodoxNavSection.ink, fontWeight: FontWeight.w800, fontSize: 14)),
              if (row.subtitle != null) ...[
                const SizedBox(height: 3),
                Text(row.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF667085), height: 1.25)),
              ],
            ]),
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
