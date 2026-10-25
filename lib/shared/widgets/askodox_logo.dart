import 'package:flutter/material.dart';

/// The ONE in-app ASKODOX logo (brain circuit + arrow "D"). Same artwork as
/// the launcher icon (android/app/src/main/res/mipmap-*). [boxed] draws the
/// dark rounded app-icon tile; otherwise the bare mark (for dark surfaces).
class AskodoxLogo extends StatelessWidget {
  const AskodoxLogo({super.key, this.size = 28, this.boxed = true});

  final double size;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      boxed ? 'assets/brand/askodox_icon.png' : 'assets/brand/askodox_mark.png',
      key: const Key('askodoxLogo'),
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ASKODOX',
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
}
