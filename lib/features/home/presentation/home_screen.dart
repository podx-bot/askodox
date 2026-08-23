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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _updateService = const AskodoxUpdateService();
  AskodoxUpdateInfo? _updateInfo;
  bool _updating = false;
  double _updateProgress = 0;

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
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AskodoxDesignTokens.navy.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AskodoxDesignTokens.violet300.withValues(alpha: .65)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: AskodoxDesignTokens.violet100),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ASKODOX update ready', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                Text(
                  _updating ? 'Downloading… $pct%' : 'Tap Update — no manual APK download.',
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
        title: const Text(
          BrandConfig.displayName,
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            tooltip: 'Deals',
            onPressed: () => context.go('/deals'),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AskodoxDesignTokens.backgroundGradient),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _updateCard(),
                    Container(
                      key: const Key('askodoxOrb'),
                      width: 196,
                      height: 196,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AskodoxDesignTokens.brandGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AskodoxDesignTokens.violet500.withValues(alpha: .38),
                            blurRadius: 62,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AskodoxDesignTokens.navy.withValues(alpha: .72),
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: const Icon(Icons.graphic_eq_rounded, size: 64, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      BrandConfig.assistantName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BrandConfig.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AskodoxDesignTokens.violet100,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BrandConfig.localPromise,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      key: const Key('askodoxAskField'),
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: BrandConfig.askHint,
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.auto_awesome_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const Key('askodoxMicButton'),
                              tooltip: 'Speak to ASKODOX',
                              onPressed: () => context.go('/discover/voice'),
                              icon: const Icon(Icons.mic_rounded),
                            ),
                            IconButton(
                              key: const Key('askodoxSendButton'),
                              tooltip: 'Ask',
                              onPressed: _submit,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final item in _quickAsks)
                          ActionChip(
                            label: Text(item),
                            onPressed: () {
                              _controller.text = item;
                              _controller.selection = TextSelection.collapsed(offset: item.length);
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
