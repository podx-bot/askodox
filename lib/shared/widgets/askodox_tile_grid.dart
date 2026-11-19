import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'page_layout.dart';

/// One tile of the shared tile grid (the POS dashboard look): icon + bold
/// title (+ optional small subtitle / status label).
class AskodoxTile {
  const AskodoxTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.enabled = true,
  });

  /// Stable id: the tile's widget key is `ValueKey('<keyPrefix>-<id>')`.
  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Short status label shown on the tile (e.g. "Not tested on a phone yet").
  final String? badge;
  final bool enabled;
  final VoidCallback onTap;
}

/// The shared tile grid: 2 columns on phones, 3 on wide screens. Tiles grow to
/// fit two-line titles (no clipping in Telugu).
class AskodoxTileGrid extends StatelessWidget {
  const AskodoxTileGrid(
      {super.key, required this.tiles, this.keyPrefix = 'askodoxTile', this.minTileHeight = 96, this.layoutId, this.layoutTitle});

  final List<AskodoxTile> tiles;
  final String keyPrefix;
  final double minTileHeight;

  /// Owner 2026-11-19: with an id, the person may reorder / rename / hide these tiles (page_layout.dart); the tile
  /// ids and keys never change. [layoutTitle] = the grid's name in the arrange sheet.
  final String? layoutId;
  final String? layoutTitle;

  @override
  Widget build(BuildContext context) {
    final section = layoutId;
    // Without a layout id no provider is touched (screens / tests without a ProviderScope keep working).
    if (section == null) return _grid(tiles);
    return Consumer(builder: (context, ref, _) => _arranged(context, ref, section));
  }

  Widget _arranged(BuildContext context, WidgetRef ref, String section) {
    var tiles = this.tiles;
    {
      final layout = ref.watch(askodoxPageLayoutProvider)[section] ?? const AskodoxSectionLayout();
      if (!layout.isDefault) {
        final byId = {for (final t in this.tiles) t.id: t};
        tiles = [
          for (final id in askodoxArrangedIds(byId.keys.toList(), layout))
            if (!layout.hidden.contains(id))
              layout.names[id] == null
                  ? byId[id]!
                  : AskodoxTile(
                      id: id,
                      icon: byId[id]!.icon,
                      title: layout.names[id]!,
                      subtitle: byId[id]!.subtitle,
                      badge: byId[id]!.badge,
                      enabled: byId[id]!.enabled,
                      onTap: byId[id]!.onTap,
                    ),
        ];
      }
    }
    final grid = _grid(tiles);
    if (this.tiles.length < 2) return grid;
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: ValueKey('askodoxArrange-$section'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: const Color(0xFF6B7280)),
          onPressed: () => askodoxArrangeSection(context, section, layoutTitle ?? '', [
            for (final t in this.tiles) AskodoxLayoutItem(id: t.id, title: t.title, icon: t.icon),
          ]),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Text(te ? 'క్రమం మార్చు' : 'Arrange', style: const TextStyle(fontSize: 12)),
        ),
      ),
      grid,
    ]);
  }

  Widget _grid(List<AskodoxTile> tiles) {
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 720 ? 3 : 2;
      const gap = 10.0;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final t in tiles)
            SizedBox(
              width: width,
              child: _TileCard(tile: t, keyPrefix: keyPrefix, minHeight: minTileHeight),
            ),
        ],
      );
    });
  }
}

class _TileCard extends StatelessWidget {
  const _TileCard({required this.tile, required this.keyPrefix, required this.minHeight});
  final AskodoxTile tile;
  final String keyPrefix;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = !tile.enabled;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('$keyPrefix-${tile.id}'),
        onTap: tile.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(tile.icon, size: 28, color: faded ? scheme.outline : scheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    tile.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15.5, color: faded ? scheme.outline : scheme.onSurface),
                  ),
                  if (tile.subtitle != null && tile.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(tile.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                  if (tile.badge != null && tile.badge!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tile.badge!, style: const TextStyle(fontSize: 10.5, color: Color(0xFF9A3412))),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
