import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/theme/askodox_design_tokens.dart';

enum AskodoxAiState {
  idle,
  listening,
  thinking,
  understanding,
  responding,
  speaking,
  completed,
  error,
}

extension AskodoxAiStateCopy on AskodoxAiState {
  String get label => switch (this) {
        AskodoxAiState.idle => 'Ready',
        AskodoxAiState.listening => 'Listening',
        AskodoxAiState.thinking => 'Thinking',
        AskodoxAiState.understanding => 'Understanding',
        AskodoxAiState.responding => 'Responding',
        AskodoxAiState.speaking => 'Speaking',
        AskodoxAiState.completed => 'Completed',
        AskodoxAiState.error => 'Try again',
      };

  IconData get icon => switch (this) {
        AskodoxAiState.idle => Icons.auto_awesome_rounded,
        AskodoxAiState.listening => Icons.mic_rounded,
        AskodoxAiState.thinking => Icons.psychology_rounded,
        AskodoxAiState.understanding => Icons.check_circle_outline_rounded,
        AskodoxAiState.responding => Icons.chat_bubble_rounded,
        AskodoxAiState.speaking => Icons.graphic_eq_rounded,
        AskodoxAiState.completed => Icons.check_rounded,
        AskodoxAiState.error => Icons.refresh_rounded,
      };
}

class AskodoxAiStateVisual extends StatefulWidget {
  const AskodoxAiStateVisual({
    super.key,
    required this.state,
    this.size = 220,
    this.showLabel = false,
  });

  final AskodoxAiState state;
  final double size;
  final bool showLabel;

  @override
  State<AskodoxAiStateVisual> createState() => _AskodoxAiStateVisualState();
}

class _AskodoxAiStateVisualState extends State<AskodoxAiStateVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * math.pi * 2;
            final active = widget.state != AskodoxAiState.idle &&
                widget.state != AskodoxAiState.completed &&
                widget.state != AskodoxAiState.error;
            final scale = active ? 1 + math.sin(phase) * 0.018 : 1.0;
            final ringOpacity = active ? 0.26 + (math.sin(phase) + 1) * 0.10 : 0.20;

            return Transform.scale(
              scale: scale,
              child: Container(
                key: const Key('askodoxAiStateVisual'),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.28, -0.30),
                    radius: 0.96,
                    colors: [
                      Color(0xFFF8F4FF),
                      AskodoxDesignTokens.violet100,
                      AskodoxDesignTokens.violet500,
                      AskodoxDesignTokens.violet900,
                    ],
                    stops: [0, 0.24, 0.62, 1],
                  ),
                  border: Border.all(
                    color: AskodoxDesignTokens.cyan.withValues(alpha: ringOpacity),
                    width: 1.5,
                  ),
                  boxShadow: [
                    AskodoxDesignTokens.glow(
                      widget.state == AskodoxAiState.error
                          ? AskodoxDesignTokens.error
                          : AskodoxDesignTokens.electricBlue,
                      blur: 34,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: widget.size * 0.36,
                    height: widget.size * 0.36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Icon(
                      widget.state.icon,
                      size: widget.size * 0.17,
                      color: widget.state == AskodoxAiState.error
                          ? AskodoxDesignTokens.error
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.showLabel) ...[
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              widget.state.label,
              key: ValueKey(widget.state),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
