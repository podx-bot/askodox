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

  static const _quickAsks = <(String, IconData)>[
    ('Buy nearby', Icons.shopping_bag_outlined),
    ('Sell something', Icons.sell_outlined),
    ('Find work', Icons.work_outline_rounded),
    ('Book a service', Icons.handyman_outlined),
    ('Find a ride', Icons.directions_car_outlined),
  ];

  static const _explore = <(String, IconData, String)>[
    ('Buy & Sell', Icons.shopping_bag_outlined, 'Buy nearby'),
    ('Jobs & Work', Icons.work_outline_rounded, 'Find work'),
    ('Services', Icons.handyman_outlined, 'Book a service'),
    ('Travel & Rides', Icons.directions_car_outlined, 'Find a ride'),
    ('Money & Loans', Icons.account_balance_wallet_outlined, 'Find a loan'),
    ('Insurance', Icons.shield_outlined, 'Compare insurance'),
    ('Bills & Utilities', Icons.receipt_long_outlined, 'Bills and utilities'),
    ('Credit Cards', Icons.credit_card_rounded, 'Compare credit cards'),
    ('Real Estate', Icons.home_work_outlined, 'Find property'),
    ('Education', Icons.school_outlined, 'Find education'),
    ('Health', Icons.health_and_safety_outlined, 'Find healthcare'),
    ('More', Icons.apps_rounded, 'Show more services'),
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

  void _start(String query) {
    final clean = query.trim();
    if (clean.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    ref.read(universalDealControllerProvider.notifier).start(clean);
    context.go('/search');
  }

  void _submit() => _start(_controller.text);

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
      body: Container(
        decoration: const BoxDecoration(gradient: AskodoxDesignTokens.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                if (_updateInfo != null) ...[const SizedBox(height: 12), _updateCard()],
                const SizedBox(height: 18),
                _askBar(),
                const SizedBox(height: 14),
                _quickActions(),
                const SizedBox(height: 24),
                const _SectionTitle('Compare & Choose'),
                const SizedBox(height: 10),
                _comparisonCard(),
                const SizedBox(height: 24),
                const _SectionTitle('Explore ASKODOX'),
                const SizedBox(height: 10),
                _exploreGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          IconButton(
            key: const Key('askodoxMenuButton'),
            tooltip: 'Menu',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
          ),
          const _CompactMascot(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'ASKODOX ', style: TextStyle(color: Colors.white)),
                TextSpan(text: 'AI', style: TextStyle(color: AskodoxDesignTokens.violet100)),
              ]),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
          ),
          IconButton(
            tooltip: 'Deals',
            onPressed: () => context.go('/deals'),
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
          ),
        ],
      );

  Widget _askBar() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF11182E).withValues(alpha: .94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AskodoxDesignTokens.violet300.withValues(alpha: .55)),
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
            prefixIcon: const Icon(Icons.auto_awesome_rounded, color: AskodoxDesignTokens.violet100),
            border: InputBorder.none,
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const Key('askodoxMicButton'),
                tooltip: 'Speak to ASKODOX',
                onPressed: () => context.go('/discover/voice'),
                icon: const Icon(Icons.mic_rounded, color: AskodoxDesignTokens.violet100),
              ),
              IconButton(
                key: const Key('askodoxSendButton'),
                tooltip: 'Ask',
                onPressed: _submit,
                icon: const Icon(Icons.arrow_upward_rounded, color: AskodoxDesignTokens.violet100),
              ),
            ]),
          ),
        ),
      );

  Widget _quickActions() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in _quickAsks)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  key: Key('quick-${item.$1.toLowerCase().replaceAll(' ', '-')}'),
                  avatar: Icon(item.$2, size: 18, color: AskodoxDesignTokens.violet100),
                  label: Text(item.$1),
                  labelStyle: const TextStyle(color: Colors.white),
                  backgroundColor: const Color(0xFF131A31),
                  side: BorderSide(color: AskodoxDesignTokens.violet300.withValues(alpha: .35)),
                  onPressed: () => _start(item.$1),
                ),
              ),
          ],
        ),
      );

  Widget _comparisonCard() => InkWell(
        key: const Key('askodoxCompareCard'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => _start('Compare nearby and online options'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10172C),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF3A466D)),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Offline vs Online', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Compare price, distance, availability, delivery and total value.', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _ScopePill('1 km'), _ScopePill('5 km'), _ScopePill('25 km'), _ScopePill('100 km'), _ScopePill('Anywhere'), _ScopePill('Online'),
            ]),
          ]),
        ),
      );

  Widget _exploreGrid() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _explore.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (context, index) {
          final item = _explore[index];
          return InkWell(
            key: Key('explore-${item.$1.toLowerCase().replaceAll(' ', '-').replaceAll('&', 'and')}'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => _start(item.$3),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF121A31),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF303B60)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(item.$2, color: AskodoxDesignTokens.violet100, size: 27),
                const SizedBox(height: 8),
                Text(item.$1, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          );
        },
      );

  Widget _updateCard() {
    final pct = (_updateProgress * 100).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AskodoxDesignTokens.navy, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.system_update_alt_rounded, color: AskodoxDesignTokens.violet100),
        const SizedBox(width: 8),
        Expanded(child: Text(_updating ? 'Downloading… $pct%' : 'ASKODOX update ready', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        FilledButton(onPressed: _updating ? null : _installUpdate, child: Text(_updating ? '$pct%' : 'Update')),
      ]),
    );
  }
}

class _CompactMascot extends StatelessWidget {
  const _CompactMascot();

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFB23DFF), Color(0xFF3759FF)]),
          boxShadow: [BoxShadow(color: AskodoxDesignTokens.violet500.withValues(alpha: .35), blurRadius: 16)],
        ),
        child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 30),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900));
}

class _ScopePill extends StatelessWidget {
  const _ScopePill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFF1A2340), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      );
}
