import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../conversation/presentation/conversation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _orbController;

  static const _quickAsks = <String>[
    'Buy nearby',
    'Sell something',
    'Find work',
    'Book a service',
    'Find a ride',
  ];

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _orbController.dispose();
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(initialQuery: text),
      ),
    );
  }

  void _selectQuickAsk(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _focusNode.requestFocus();
  }

  void _startVoice() => context.go('/discover/voice');
  void _openSettings() => context.go('/developer');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _AmbientBackground()),
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 680;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      compact ? 20 : 28,
                      20,
                      150,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 170),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _AiOrb(animation: _orbController),
                          SizedBox(height: compact ? 18 : 26),
                          Text(
                            BrandConfig.assistantName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ask anything local. Buy, sell, work, services or rides.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white60,
                              height: 1.45,
                            ),
                          ),
                          SizedBox(height: compact ? 18 : 26),
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              shrinkWrap: true,
                              itemCount: _quickAsks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final quickAsk = _quickAsks[index];
                                return ActionChip(
                                  key: Key('askodoxQuickAsk$index'),
                                  label: Text(quickAsk),
                                  onPressed: () => _selectQuickAsk(quickAsk),
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.06),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                  labelStyle: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  shape: const StadiumBorder(),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xF21B1B1D),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: TextField(
                        key: const Key('askodoxAskField'),
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitAsk(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: BrandConfig.askHint,
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15),
                          prefixIcon: IconButton(
                            tooltip: 'Add',
                            onPressed: () {},
                            icon: const Icon(
                              Icons.add_rounded,
                              color: Colors.white70,
                            ),
                          ),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Material(
                              color: colors.primary,
                              shape: const CircleBorder(),
                              child: IconButton(
                                tooltip: 'Send',
                                onPressed: _submitAsk,
                                icon: Icon(
                                  Icons.arrow_upward_rounded,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RoundAction(
                    key: const Key('askodoxMicButton'),
                    tooltip: BrandConfig.voiceHint,
                    icon: Icons.mic_rounded,
                    onPressed: _startVoice,
                    emphasized: true,
                  ),
                ],
              ),
            ),
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
                key: const Key('askodoxSettingsButton'),
                tooltip: 'Settings',
                icon: Icons.tune_rounded,
                onPressed: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 0.95,
            colors: [
              Color(0x1A7587FF),
              Color(0x0D5A66FF),
              Colors.transparent,
            ],
            stops: [0, 0.44, 1],
          ),
        ),
      ),
    );
  }
}

class _AiOrb extends StatelessWidget {
  const _AiOrb({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${BrandConfig.assistantName} listening orb',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final phase = animation.value * math.pi * 2;
          final pulse = 1 + (math.sin(phase) * 0.018);
          final glow = 34 + (math.sin(phase) + 1) * 8;

          return Transform.scale(
            scale: pulse,
            child: Container(
              key: const Key('askodoxOrb'),
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(
                    -0.30 + math.sin(phase) * 0.05,
                    -0.22 + math.cos(phase) * 0.04,
                  ),
                  radius: 0.96,
                  colors: const [
                    Color(0xFFFFFFFF),
                    Color(0xFFE3E7FF),
                    Color(0xFF9AA7FF),
                    Color(0xFF596BEE),
                    Color(0xFF3342A7),
                  ],
                  stops: const [0, 0.22, 0.50, 0.76, 1],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7788FF).withValues(alpha: 0.35),
                    blurRadius: glow,
                    spreadRadius: 5,
                  ),
                  const BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
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
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: emphasized ? colors.primary : const Color(0xE6202022),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: emphasized ? 6 : 0,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: emphasized ? colors.onPrimary : Colors.white,
        ),
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}
