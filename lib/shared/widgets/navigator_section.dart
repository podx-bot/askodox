import 'package:flutter/material.dart';

/// ASKODOX Navigator: ONE compact grouped-section look for Profile, My
/// Business, Listings and every nested page -- a small heading with an icon,
/// then one rounded card of rows (no card per row, no tall empty gaps).
class AskodoxNavSection extends StatelessWidget {
  const AskodoxNavSection({super.key, required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  static const ink = Color(0xFF10204A);
  static const accent = Color(0xFF1769FF);

  @override
  Widget build(BuildContext context) {
    final rows = [for (final c in children) if (c is! SizedBox || c.child != null) c];
    if (rows.isEmpty) return const SizedBox.shrink();
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
  });

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
