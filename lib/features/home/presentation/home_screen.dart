import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../config/theme/askodox_design_tokens.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../deal_brain/application/universal_deal_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _updateService = const AskodoxUpdateService();
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  AskodoxUpdateInfo? _updateInfo;
  bool _updating = false;
  double _updateProgress = 0;

  static const _quickAsks = <(String, IconData)>[
    ('Buy nearby', Icons.shopping_bag_outlined),
    ('Sell something', Icons.business_center_outlined),
    ('Find work', Icons.person_search_outlined),
    ('Book a service', Icons.handyman_outlined),
    ('Find a ride', Icons.directions_car_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    if (AskodoxUpdateService.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await _updateService.checkForUpdate();
    if (mounted && info != null) setState(() => _updateInfo = info);
  }

  Future<void> _installUpdate() async {
    final info = _updateInfo;
    if (info == null || _updating) return;
    setState(() {
      _updating = true;
      _updateProgress = 0;
    });
    try {
      await _updateService.downloadAndInstall(
        info,
        onProgress: (value) {
          if (mounted) setState(() => _updateProgress = value);
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update could not start. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    ref.read(universalDealControllerProvider.notifier).start(query);
    context.go('/search');
  }

  Widget _updateCard() {
    final info = _updateInfo;
    if (info == null) return const SizedBox.shrink();
    final pct = (_updateProgress * 100).round();
    return Container(
      key: const Key('askodoxUpdateCard'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AskodoxDesignTokens.navy.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AskodoxDesignTokens.violet300.withValues(alpha: .65),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt_rounded,
            color: AskodoxDesignTokens.violet100,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ASKODOX update ready',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _updating
                      ? 'Downloading… $pct%'
                      : 'Tap Update — no manual APK download.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('askodoxUpdateButton'),
            onPressed: _updating ? null : _installUpdate,
            child: Text(_updating ? '$pct%' : 'Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AskodoxDesignTokens.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(7),
          child: _RoundGlassButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onPressed: () => context.go('/profile'),
          ),
        ),
        title: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.all(7),
            child: _RoundGlassButton(
              icon: Icons.tune_rounded,
              tooltip: 'Deals',
              onPressed: () => context.go('/deals'),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AskodoxDesignTokens.backgroundGradient,
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _updateCard(),
                    _AnimatedAskodoxRobot(
                      key: const Key('askodoxOrb'),
                      animation: _pulse,
                    ),
                    const SizedBox(height: 22),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.4,
                            ),
                        children: const [
                          TextSpan(text: 'ASKODOX '),
                          TextSpan(
                            text: 'AI',
                            style: TextStyle(color: AskodoxDesignTokens.violet100),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BrandConfig.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AskodoxDesignTokens.violet100,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BrandConfig.localPromise,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF11182E).withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AskodoxDesignTokens.violet300.withValues(alpha: .55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AskodoxDesignTokens.violet500.withValues(alpha: .16),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: TextField(
                        key: const Key('askodoxAskField'),
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: BrandConfig.askHint,
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AskodoxDesignTokens.violet100,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: const Key('askodoxMicButton'),
                                tooltip: 'Speak to ASKODOX',
                                onPressed: () => context.go('/discover/voice'),
                                icon: const Icon(
                                  Icons.mic_rounded,
                                  color: AskodoxDesignTokens.violet100,
                                ),
                              ),
                              IconButton(
                                key: const Key('askodoxSendButton'),
                                tooltip: 'Ask',
                                onPressed: _submit,
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: AskodoxDesignTokens.violet100,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final item in _quickAsks)
                          ActionChip(
                            avatar: Icon(
                              item.$2,
                              size: 18,
                              color: AskodoxDesignTokens.violet100,
                            ),
                            label: Text(item.$1),
                            side: BorderSide(
                              color: AskodoxDesignTokens.violet300.withValues(alpha: .38),
                            ),
                            backgroundColor:
                                const Color(0xFF131A31).withValues(alpha: .78),
                            labelStyle: const TextStyle(color: Colors.white),
                            onPressed: () {
                              _controller.text = item.$1;
                              _controller.selection = TextSelection.collapsed(
                                offset: item.$1.length,
                              );
                              _focusNode.requestFocus();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF111629).withValues(alpha: .86),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
        ),
      );
}

class _AnimatedAskodoxRobot extends StatelessWidget {
  const _AnimatedAskodoxRobot({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          final glow = 26 + (28 * t);
          final scale = .985 + (.025 * t);
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 248,
              height: 248,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 228,
                    height: 228,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFB23DFF), Color(0xFF3759FF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C38FF).withValues(alpha: .58),
                          blurRadius: glow,
                          spreadRadius: 4 + (4 * t),
                        ),
                        BoxShadow(
                          color: const Color(0xFF1D7CFF).withValues(alpha: .25),
                          blurRadius: glow * 1.25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 208,
                    height: 208,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF070A18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .16),
                        width: 2,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    child: _WaveBars(intensity: t),
                  ),
                  Positioned(
                    right: 8,
                    top: 86,
                    child: Container(
                      width: 52,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF13224B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF5AA4FF)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x775AA4FF), blurRadius: 15),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Dot(),
                          SizedBox(width: 4),
                          _Dot(),
                          SizedBox(width: 4),
                          _Dot(),
                        ],
                      ),
                    ),
                  ),
                  const _RobotBody(),
                ],
              ),
            ),
          );
        },
      );
}

class _RobotBody extends StatelessWidget {
  const _RobotBody();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFB9C3E8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  children: [
                    Container(
                      width: 5,
                      height: 18,
                      color: const Color(0xFF7285D9),
                    ),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4B9CFF),
                        boxShadow: [
                          BoxShadow(color: Color(0xAA4B9CFF), blurRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 132,
            height: 92,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE9ECFA), Color(0xFF9EAAE0)],
              ),
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x665A7CFF), blurRadius: 18),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF050817),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Stack(
                children: [
                  Positioned(left: 25, top: 28, child: _EyeArc()),
                  Positioned(right: 25, top: 28, child: _EyeArc()),
                  Positioned(left: 50, top: 49, child: _Smile()),
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -2),
            child: Container(
              width: 84,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE3E7FA), Color(0xFF9BA7DE)],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(34),
                  bottomRight: Radius.circular(34),
                ),
                border: Border.all(color: Colors.white70),
              ),
              child: Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1E8CFF),
                    boxShadow: [
                      BoxShadow(color: Color(0xCC1E8CFF), blurRadius: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _EyeArc extends StatelessWidget {
  const _EyeArc();

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 12,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF3FD5FF), width: 4),
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      );
}

class _Smile extends StatelessWidget {
  const _Smile();

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 14,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF3FD5FF), width: 3),
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      );
}

class _WaveBars extends StatelessWidget {
  const _WaveBars({required this.intensity});

  final double intensity;

  @override
  Widget build(BuildContext context) {
    const heights = [18.0, 36.0, 54.0, 36.0, 18.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < heights.length; i++)
          Container(
            width: 4,
            height: heights[i] * (.72 + (.28 * intensity)),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3B9BFF),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Color(0xAA3B9BFF), blurRadius: 9),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: Color(0xFFB9E7FF),
          shape: BoxShape.circle,
        ),
      );
}
