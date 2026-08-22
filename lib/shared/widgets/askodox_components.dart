import 'package:flutter/material.dart';

import '../../config/theme/askodox_design_tokens.dart';

class AskodoxActionButton extends StatelessWidget {
  const AskodoxActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasized = false,
    this.size = 56,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool emphasized;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: emphasized ? AskodoxDesignTokens.actionGradient : null,
            color: emphasized
                ? null
                : (Theme.of(context).brightness == Brightness.dark
                    ? AskodoxDesignTokens.surfaceSoft
                    : colors.surfaceContainerHighest),
            border: Border.all(
              color: emphasized
                  ? AskodoxDesignTokens.violet100.withValues(alpha: 0.40)
                  : colors.outline.withValues(alpha: 0.55),
            ),
            boxShadow: emphasized
                ? [AskodoxDesignTokens.glow(AskodoxDesignTokens.electricBlue)]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  icon,
                  color: emphasized ? Colors.white : colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AskodoxIntentChip extends StatelessWidget {
  const AskodoxIntentChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: selected
          ? colors.primary.withValues(alpha: 0.20)
          : colors.surfaceContainerHighest.withValues(alpha: 0.65),
      side: BorderSide(
        color: selected
            ? colors.primary.withValues(alpha: 0.65)
            : colors.outline.withValues(alpha: 0.45),
      ),
      labelStyle: TextStyle(
        color: selected ? colors.primary : colors.onSurface,
        fontWeight: FontWeight.w600,
      ),
      shape: const StadiumBorder(),
    );
  }
}

class AskodoxComposer extends StatelessWidget {
  const AskodoxComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.hintText = 'Ask ASKODOX',
    this.onAdd,
    this.onVoice,
    this.enabled = true,
    this.fieldKey,
    this.sendKey,
    this.voiceKey,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final VoidCallback? onAdd;
  final VoidCallback? onVoice;
  final String hintText;
  final bool enabled;
  final Key? fieldKey;
  final Key? sendKey;
  final Key? voiceKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: fieldKey ?? const Key('askodoxComposerField'),
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: enabled ? (_) => onSend() : null,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: IconButton(
                tooltip: 'Add',
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add_rounded),
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AskodoxDesignTokens.actionGradient,
                  ),
                  child: IconButton(
                    key: sendKey,
                    tooltip: 'Send',
                    onPressed: enabled ? onSend : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onVoice != null) ...[
          const SizedBox(width: 10),
          AskodoxActionButton(
            key: voiceKey,
            icon: Icons.mic_rounded,
            tooltip: 'Speak to ASKODOX',
            onPressed: enabled ? onVoice : null,
            emphasized: true,
            size: 58,
          ),
        ],
      ],
    );
  }
}
