import 'package:flutter/material.dart';

import '../../config/theme/askodox_design_tokens.dart';

/// Reusable ASKODOX brand mark built entirely with Flutter primitives so it
/// stays sharp at launcher-card, app-bar and profile sizes without raster blur.
class AskodoxBrandMark extends StatelessWidget {
  const AskodoxBrandMark({
    super.key,
    this.size = 44,
    this.showWordmark = false,
    this.subtitle,
  });

  final double size;
  final bool showWordmark;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      key: const Key('askodoxBrandMark'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .28),
        gradient: AskodoxDesignTokens.brandGradient,
        boxShadow: [AskodoxDesignTokens.glow(AskodoxDesignTokens.violet500, blur: 20)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .66,
            height: size * .66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: .18),
              border: Border.all(color: Colors.white.withValues(alpha: .28)),
            ),
          ),
          Icon(Icons.hub_rounded, size: size * .39, color: Colors.white),
          Positioned(
            right: size * .15,
            top: size * .14,
            child: Container(
              width: size * .13,
              height: size * .13,
              decoration: const BoxDecoration(
                color: AskodoxDesignTokens.cyan,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ASKODOX',
              key: const Key('askodoxWordmark'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ],
    );
  }
}
