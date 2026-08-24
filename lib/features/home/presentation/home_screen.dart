import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/askodox_design_tokens.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../deal_brain/application/universal_deal_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _updateService = const AskodoxUpdateService();

  AskodoxUpdateInfo? _updateInfo;
  bool _updating = false;
  double _updateProgress = 0;

  static const _quickActions = <(String, String, IconData)>[
    ('Buy / Sell', 'Buy nearby', Icons.shopping_bag_outlined),
    ('Services', 'Book a service', Icons.handyman_outlined),
    ('Rides', 'Find a ride', Icons.directions_car_outlined),
    ('Jobs', 'Find work', Icons.work_outline_rounded),
    ('Bills', 'Pay utility bills', Icons.receipt_long_outlined),
  ];

  @override
  void initState() {
    super.initState();
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

  void _startFlow(String text) {
    ref.read(universalDealControllerProvider.notifier).start(text);
    context.go('/search');
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    _startFlow(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AskodoxDesignTokens.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Menu',
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.menu_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Explore',
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AskodoxDesignTokens.backgroundGradient,
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (_updateInfo != null) _updateCard(),
              const SizedBox(height: 4),
              const _CompactMascot(),
              const SizedBox(height: 14),
              const _BrandTitle(),
              const SizedBox(height: 8),
              const Text(
                'Ask anything. Get matched, compared, done.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 22),
              _askBox(),
              const SizedBox(height: 14),
              const Text(
                'Quick actions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in _quickActions)
                    ActionChip(
                      avatar: Icon(
                        item.$3,
                        size: 18,
                        color: AskodoxDesignTokens.violet100,
                      ),
                      label: Text(item.$1),
                      onPressed: () => _startFlow(item.$2),
                      backgroundColor: const Color(0xFF12192D),
                      side: BorderSide(
                        color: AskodoxDesignTokens.violet300.withValues(alpha: .45),
                      ),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.go('/search'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF11182E).withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AskodoxDesignTokens.violet300.withValues(alpha: .45),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.explore_outlined, color: AskodoxDesignTokens.violet100),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explore more on ASKODOX',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Jobs, services, rides, loans, insurance, utilities, offline vs online and more.',
                              style: TextStyle(color: Colors.white70, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _askBox() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF11182E).withValues(alpha: .94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AskodoxDesignTokens.violet300.withValues(alpha: .6),
          ),
        ),
        child: TextField(
          key: const Key('askodoxAskField'),
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ask anything…',
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(
              Icons.auto_awesome_rounded,
              color: AskodoxDesignTokens.violet100,
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
              ],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          ),
        ),
      );

  Widget _updateCard() {
    final pct = (_updateProgress * 100).round();
    return Card(
      color: const Color(0xFF11182E),
      child: ListTile(
        leading: const Icon(Icons.system_update_alt_rounded),
        title: const Text('ASKODOX update ready'),
        subtitle: Text(_updating ? 'Downloading… $pct%' : 'Tap Update to install'),
        trailing: FilledButton(
          key: const Key('askodoxUpdateButton'),
          onPressed: _updating ? null : _installUpdate,
          child: Text(_updating ? '$pct%' : 'Update'),
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) => RichText(
        textAlign: TextAlign.center,
        text: const TextSpan(
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
          children: [
            TextSpan(text: 'ASKODOX '),
            TextSpan(
              text: 'AI',
              style: TextStyle(color: AskodoxDesignTokens.violet100),
            ),
          ],
        ),
      );
}

class _CompactMascot extends StatelessWidget {
  const _CompactMascot();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF9A45FF), Color(0xFF3759FF)],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x667C38FF), blurRadius: 24, spreadRadius: 2),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF080B19),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 52,
            ),
          ),
        ),
      );
}
