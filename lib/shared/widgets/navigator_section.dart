import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flags/askodox_release_phase.dart';
import '../../features/guide/in_app_guide.dart';
import 'askodox_mascot.dart';
import 'chat_pins.dart';

/// ASKODOX Navigator: ONE compact grouped-section look for Profile, My
/// Business, Listings and every nested page -- a small heading with an icon,
/// then one rounded card of rows (no card per row, no tall empty gaps).
///
/// Redesign 2026-11-17 (owner: "buttons, not long rows; add colours"): every section is a heading +
/// a 2-column grid of coloured tiles; rows with their own control stay as rows. [grid] is kept only so
/// callers compile.
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

  /// Soft background + strong colour pairs; each section starts at its own colour (owner 2026-11-17: "add colours").
  static const palette = [
    (Color(0xFFE8EEFB), Color(0xFF1E3FA0)),
    (Color(0xFFE7F5EE), Color(0xFF17784C)),
    (Color(0xFFFFF1E3), Color(0xFFB45309)),
    (Color(0xFFF1EBFB), Color(0xFF5B2A9E)),
    (Color(0xFFE3F4F6), Color(0xFF0E6A84)),
    (Color(0xFFFCE9F1), Color(0xFFA3215C)),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = [for (final c in children) if (c is! SizedBox || c.child != null) c];
    if (rows.isEmpty) return const SizedBox.shrink();
    // Owner 2026-11-17: pages are BUTTONS, not long rows -- every plain destination row is a coloured tile in a 2-column
    // grid; rows that carry their own control (a switch, a value) stay as rows in one card below.
    final tiles = [for (final r in rows) if (r is AskodoxNavRow && r.trailing == null) r];
    final others = [for (final r in rows) if (!(r is AskodoxNavRow && r.trailing == null)) r];
    final start = title.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            // Phase 1: no robot beside the headings (owner 2026-11-15, pani C) -- the plain icon instead.
            if (mascot != null && askodoxGuidesOn) AskodoxMascot(role: mascot!, size: 26) else Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        if (tiles.isNotEmpty)
          LayoutBuilder(builder: (context, box) {
            final width = (box.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (i, row) in tiles.indexed)
                SizedBox(
                  width: tiles.length.isOdd && i == tiles.length - 1 ? box.maxWidth : width,
                  child: AskodoxNavColorTile(row: row, colors: palette[(start + i) % palette.length]),
                ),
            ]);
          }),
        if (others.isNotEmpty) ...[
          if (tiles.isNotEmpty) const SizedBox(height: 10),
          Material(
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE6E9EF)),
            ),
            child: Column(children: [
              for (final (i, row) in others.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 60, color: Color(0xFFEEF0F4)),
                row,
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A plain destination as a coloured button: white icon box, bold title, one or two lines saying what opens, the
/// Guide button when the row has a walkthrough. The whole tile opens the page.
class AskodoxNavColorTile extends ConsumerWidget {
  const AskodoxNavColorTile({super.key, required this.row, required this.colors});
  final AskodoxNavRow row;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final flow = row.guide == null || !askodoxGuidesOn ? null : askodoxGuideById(row.guide!);
    return KeyedSubtree(
      key: row.key,
      child: Material(
        color: colors.$1,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: row.onTap,
          onLongPress: row.longPress(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: 100),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                  child: Icon(row.icon, color: colors.$2, size: 21),
                ),
                const Spacer(),
                if (flow != null)
                  Tooltip(
                    message: te ? 'గైడ్: ఇక్కడ ఏం చేయాలి' : 'Guide: what to do here',
                    child: InkResponse(
                      key: ValueKey('askodoxTileGuide-${row.guide}'),
                      radius: 20,
                      onTap: () => ref.read(askodoxGuideProvider.notifier).start(flow),
                      child: const Padding(padding: EdgeInsets.all(2), child: AskodoxMascot(size: 22)),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AskodoxNavSection.ink, fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.2)),
              if (row.subtitle != null && row.subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(row.subtitle!,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF4B5563))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A [AskodoxNavRow] drawn as a full-width row: icon, bold title, what opens (two lines), the
/// Guide button (when the row has a walkthrough) and a chevron -- tap opens that page.
class AskodoxNavListRow extends ConsumerWidget {
  const AskodoxNavListRow({super.key, required this.row});
  final AskodoxNavRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final flow = row.guide == null || !askodoxGuidesOn ? null : askodoxGuideById(row.guide!);
    return KeyedSubtree(
      key: row.key,
      child: InkWell(
        onTap: row.onTap,
          onLongPress: row.longPress(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: const Color(0xFFE8EEFC), borderRadius: BorderRadius.circular(11)),
              child: Icon(row.icon, color: const Color(0xFF2450C8), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.title,
                    style: const TextStyle(color: AskodoxNavSection.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                if (row.subtitle != null && row.subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(row.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF5A6478))),
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
                  child: const Padding(padding: EdgeInsets.all(4), child: AskodoxMascot(size: 24)),
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
          ]),
        ),
      ),
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
    final flow = row.guide == null || !askodoxGuidesOn ? null : askodoxGuideById(row.guide!);
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
          onLongPress: row.longPress(context),
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
    this.pin,
  });

  /// Id of the in-app guide flow for this destination (Guide button).
  final String? guide;

  /// Long-press offers "Pin above the chat" (owner 2026-11-19); null = not pinnable.
  final AskodoxChatPin? pin;

  /// The long-press action for any drawing of this row (tile, list row, plain ListTile).
  GestureLongPressCallback? longPress(BuildContext context) =>
      pin == null ? null : () => askodoxOfferChatPin(context, pin!);
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
        onLongPress: longPress(context),
      );
}
