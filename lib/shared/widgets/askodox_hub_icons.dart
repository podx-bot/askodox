import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The habit button beside the ASKODOX logo: the Work Mode game only.
/// Talk and Radio were removed from the app entry points (owner 2026-11-12); their
/// screens stay in the code and will be recalled in a later phase.
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
      // The game shows as a LIVE pill (owner 2026-11-09) so it reads as something happening now.
      if (current == 'work')
        icon('work', '/work', Icons.sports_esports_rounded, 'Work Mode game', 'వర్క్ మోడ్ గేమ్',
            const Key('askodoxHeaderGameButton'))
      else
        AskodoxLiveGameButton(te: te, onTap: () => context.push('/work')),
    ]);
  }
}

/// The header's Work Mode button: a game pad with a pulsing red "LIVE" dot.
class AskodoxLiveGameButton extends StatefulWidget {
  const AskodoxLiveGameButton({super.key, required this.te, required this.onTap});
  final bool te;
  final VoidCallback onTap;

  @override
  State<AskodoxLiveGameButton> createState() => _AskodoxLiveGameButtonState();
}

class _AskodoxLiveGameButtonState extends State<AskodoxLiveGameButton> with SingleTickerProviderStateMixin {
  // Tests settle frames; a forever animation would never settle there.
  static final bool _animate = !Platform.environment.containsKey('FLUTTER_TEST');
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (_animate) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.te ? 'వర్క్ మోడ్ గేమ్ — లైవ్' : 'Work Mode game — live',
      child: InkWell(
        key: const Key('askodoxHeaderGameButton'),
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1F8A5B), Color(0xFF2E7DD7)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sports_esports_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 4),
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 3),
            const Text('LIVE',
                key: Key('askodoxHeaderGameLive'),
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          ]),
        ),
      ),
    );
  }
}
