import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../config/theme/askodox_design_tokens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static const _quickAsks = <String>[
    'Buy nearby',
    'Sell something',
    'Find work',
    'Book a service',
    'Find a ride',
  ];

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
    context.go('/search');
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
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 54),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
