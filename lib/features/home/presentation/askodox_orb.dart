import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/application/product_discovery_controller.dart';
import '../../search/domain/search_models.dart';

enum AskodoxOrbState { idle, listening, thinking, speaking }

AskodoxOrbState askodoxOrbStateForVoice(VoiceSearchState state) => switch (state) {
      VoiceSearchState.listening => AskodoxOrbState.listening,
      VoiceSearchState.processing => AskodoxOrbState.thinking,
      VoiceSearchState.speaking => AskodoxOrbState.speaking,
      _ => AskodoxOrbState.idle,
    };

class AskodoxVoiceOrb extends ConsumerWidget {
  const AskodoxVoiceOrb({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(
      productDiscoveryControllerProvider.select((state) => state.voiceState),
    );
    return AskodoxOrb(
      state: askodoxOrbStateForVoice(voiceState),
      onTap: onTap,
    );
  }
}

class AskodoxOrb extends StatefulWidget {
  const AskodoxOrb({
    super.key,
    this.state = AskodoxOrbState.idle,
    this.onTap,
  });

  final AskodoxOrbState state;
  final VoidCallback? onTap;

  @override
  State<AskodoxOrb> createState() => _AskodoxOrbState();
}

class _AskodoxOrbState extends State<AskodoxOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.state) {
        AskodoxOrbState.idle => Icons.smart_toy_rounded,
        AskodoxOrbState.listening => Icons.hearing_rounded,
        AskodoxOrbState.thinking => Icons.psychology_rounded,
        AskodoxOrbState.speaking => Icons.graphic_eq_rounded,
      };

  String get _semanticLabel => switch (widget.state) {
        AskodoxOrbState.idle => 'ASKODOX ready',
        AskodoxOrbState.listening => 'ASKODOX listening',
        AskodoxOrbState.thinking => 'ASKODOX thinking',
        AskodoxOrbState.speaking => 'ASKODOX speaking',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      button: widget.onTap != null,
      child: GestureDetector(
        key: const Key('askodoxHomeOrb'),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final active = widget.state != AskodoxOrbState.idle;
            final pulse = active ? _pulse.value : _pulse.value * .35;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 112 + (pulse * 8),
              height: 112 + (pulse * 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: switch (widget.state) {
                    AskodoxOrbState.listening => const [
                        Color(0xFFFFFFFF),
                        Color(0xFFDFF7FF),
                        Color(0xFF4D9FFF),
                      ],
                    AskodoxOrbState.thinking => const [
                        Color(0xFFFFFFFF),
                        Color(0xFFF0E6FF),
                        Color(0xFF7A4DFF),
                      ],
                    AskodoxOrbState.speaking => const [
                        Color(0xFFFFFFFF),
                        Color(0xFFE4FFF2),
                        Color(0xFF42B883),
                      ],
                    AskodoxOrbState.idle => const [
                        Color(0xFFFFFFFF),
                        Color(0xFFE8E1FF),
                        Color(0xFF7A4DFF),
                      ],
                  },
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7A4DFF)
                        .withValues(alpha: .22 + (pulse * .16)),
                    blurRadius: 24 + (pulse * 14),
                    spreadRadius: 2 + (pulse * 3),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  _icon,
                  key: ValueKey(widget.state),
                  color: Colors.white,
                  size: 48,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
