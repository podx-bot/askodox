import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitAsk() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    // Foundation behavior: hand off to the existing discovery surface until the
    // typed Universal Conversation API client lands in the next slice.
    context.go('/search');
  }

  void _startVoice() => context.go('/discover/voice');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 16,
              child: _RoundAction(
                tooltip: 'Menu',
                icon: Icons.menu_rounded,
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: _RoundAction(
                tooltip: 'Preferences',
                icon: Icons.tune_rounded,
                onPressed: () => context.go('/profile'),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 92),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AiOrb(),
                    const SizedBox(height: 22),
                    Text(
                      BrandConfig.assistantName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask anything local. Buy, sell, work, services or rides.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white60,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        key: const Key('askodoxAskField'),
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitAsk(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: BrandConfig.askHint,
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          prefixIcon: IconButton(
                            tooltip: 'Add',
                            onPressed: () {},
                            icon: const Icon(Icons.add_rounded, color: Colors.white),
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Send',
                            onPressed: _submitAsk,
                            icon: Icon(Icons.arrow_upward_rounded, color: colors.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RoundAction(
                    key: const Key('askodoxMicButton'),
                    tooltip: BrandConfig.voiceHint,
                    icon: Icons.mic_none_rounded,
                    onPressed: _startVoice,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiOrb extends StatelessWidget {
  const _AiOrb();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${BrandConfig.assistantName} listening orb',
      child: Container(
        key: const Key('askodoxOrb'),
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.28, -0.20),
            radius: 0.95,
            colors: [
              Color(0xFFF5F6FF),
              Color(0xFFC9D1FF),
              Color(0xFF7C8CFF),
              Color(0xFF4455C7),
            ],
            stops: [0.0, 0.38, 0.72, 1.0],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x667C8CFF),
              blurRadius: 42,
              spreadRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF202020),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}
