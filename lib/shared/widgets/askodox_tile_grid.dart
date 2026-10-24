import 'package:flutter/material.dart';

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
  const AskodoxTileGrid({super.key, required this.tiles, this.keyPrefix = 'askodoxTile', this.minTileHeight = 96});

  final List<AskodoxTile> tiles;
  final String keyPrefix;
  final double minTileHeight;

  @override
  Widget build(BuildContext context) {
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
