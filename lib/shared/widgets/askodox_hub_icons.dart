import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The three habit buttons beside the ASKODOX logo (owner 2026-11-08): Work
/// Mode game, anonymous Talk and Radio. Shown in the main header on every tab
/// and in the app bars of those three screens, so people get used to them.
class AskodoxHubIcons extends StatelessWidget {
  const AskodoxHubIcons({super.key, this.current, this.color = const Color(0xFF10204A)});

  /// 'work' / 'talk' / 'radio' when shown on that screen (its own icon is lit).
  final String? current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    Widget icon(String id, String path, IconData glyph, String tipEn, String tipTe, Key key) {
      final here = current == id;
      return IconButton(
        key: key,
        tooltip: te ? tipTe : tipEn,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        isSelected: here,
        style: here ? IconButton.styleFrom(backgroundColor: const Color(0xFFE3F4EA)) : null,
        icon: Icon(glyph, size: 21, color: here ? const Color(0xFF1F8A5B) : color),
        onPressed: here ? null : () => context.push(path),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      icon('work', '/work', Icons.sports_esports_rounded, 'Work Mode game', 'వర్క్ మోడ్ గేమ్',
          const Key('askodoxHeaderGameButton')),
      icon('talk', '/talk', Icons.forum_rounded, 'Talk (anonymous)', 'చర్చ (పేరు లేకుండా)',
          const Key('askodoxHeaderTalkButton')),
      icon('radio', '/radio', Icons.radio_rounded, 'Radio', 'రేడియో', const Key('askodoxHeaderRadioButton')),
    ]);
  }
}
