import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/askodox_design_tokens.dart';
import '../../../core/providers/app_settings_provider.dart';
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

  static const _discover = <(String, String, IconData)>[
    ('Products', 'Find products nearby', Icons.shopping_cart_outlined),
    ('Services', 'Find a service provider', Icons.home_repair_service_outlined),
    ('Jobs', 'Find jobs near me', Icons.work_outline_rounded),
    ('Rides', 'Find a ride', Icons.directions_car_filled_outlined),
    ('Property', 'Find property', Icons.apartment_outlined),
    ('More', 'Explore ASKODOX', Icons.grid_view_rounded),
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

  Future<void> _pickLanguage() async {
    final settings = ref.read(appSettingsProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF11182E),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Language',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'ASKODOX follows your device language automatically. You can override it anytime.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              RadioListTile<String>(
                value: 'system',
                groupValue: settings.locale == null ? 'system' : settings.locale!.languageCode,
                onChanged: (value) => Navigator.pop(context, value),
                title: const Text('Auto / Device language', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Recommended', style: TextStyle(color: Colors.white60)),
              ),
              RadioListTile<String>(
                value: 'en',
                groupValue: settings.locale?.languageCode,
                onChanged: (value) => Navigator.pop(context, value),
                title: const Text('English', style: TextStyle(color: Colors.white)),
              ),
              RadioListTile<String>(
                value: 'te',
                groupValue: settings.locale?.languageCode,
                onChanged: (value) => Navigator.pop(context, value),
                title: const Text('తెలుగు', style: TextStyle(color: Colors.white)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'More languages can be added without changing Deal Brain logic; the app keeps one universal flow.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final notifier = ref.read(appSettingsProvider.notifier);
    if (choice == 'system') {
      notifier.useSystemLocale();
    } else {
      notifier.setLocale(Locale(choice));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appSettingsProvider).locale;
    final languageLabel = locale == null
        ? 'Auto'
        : switch (locale.languageCode) {
            'te' => 'తెలుగు',
            _ => 'EN',
          };

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
        title: const Text(
          'ASKODOX',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        actions: [
          TextButton.icon(
            key: const Key('askodoxLanguageButton'),
            onPressed: _pickLanguage,
            icon: const Icon(Icons.language_rounded, size: 19),
            label: Text(languageLabel),
          ),
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
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
            children: [
              if (_updateInfo != null) _updateCard(),
              const SizedBox(height: 4),
              const _CompactMascot(),
              const SizedBox(height: 12),
              const _BrandTitle(),
              const SizedBox(height: 6),
              const Text(
                'Ask anything. Get matched, compared, done.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              _askBox(),
              const SizedBox(height: 18),
              const _SectionHeader(title: 'Find exactly what you need', action: 'Explore'),
              const SizedBox(height: 10),
              _discoverGrid(),
              const SizedBox(height: 20),
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
                      avatar: Icon(item.$3, size: 18, color: AskodoxDesignTokens.violet100),
                      label: Text(item.$1),
                      onPressed: () => _startFlow(item.$2),
                      backgroundColor: const Color(0xFF12192D),
                      side: BorderSide(color: AskodoxDesignTokens.violet300.withValues(alpha: .45)),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Best matches', action: 'View all'),
              const SizedBox(height: 10),
              _matchPreviewCard(),
              const SizedBox(height: 14),
              _exploreCard(),
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
          border: Border.all(color: AskodoxDesignTokens.violet300.withValues(alpha: .6)),
          boxShadow: const [BoxShadow(color: Color(0x332A16FF), blurRadius: 22)],
        ),
        child: TextField(
          key: const Key('askodoxAskField'),
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Tell ASKODOX what you need…',
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.auto_awesome_rounded, color: AskodoxDesignTokens.violet100),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              ],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          ),
        ),
      );

  Widget _discoverGrid() => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _discover.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .98,
        ),
        itemBuilder: (context, index) {
          final item = _discover[index];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _startFlow(item.$2),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF11182E).withValues(alpha: .92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AskodoxDesignTokens.violet300.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item.$3, color: AskodoxDesignTokens.violet100),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    item.$1,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _matchPreviewCard() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/search'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11182E).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AskodoxDesignTokens.violet300.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [Color(0xFF6F4CFF), Color(0xFF2F6BFF)]),
                ),
                child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Matching works after you confirm your need', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    SizedBox(height: 5),
                    Text('ASKODOX compares relevant opposite-side offers, distance and deal fit.', style: TextStyle(color: Colors.white60, height: 1.35, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
            ],
          ),
        ),
      );

  Widget _exploreCard() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/search'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF24164A), Color(0xFF10234A)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AskodoxDesignTokens.violet300.withValues(alpha: .45)),
          ),
          child: const Row(
            children: [
              Icon(Icons.explore_outlined, color: AskodoxDesignTokens.violet100, size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Explore more on ASKODOX', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Jobs, services, rides, property, utilities, offline vs online and more.', style: TextStyle(color: Colors.white70, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: Colors.white70),
            ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
            ),
          ),
          Text(action, style: const TextStyle(color: AskodoxDesignTokens.violet100, fontWeight: FontWeight.w700)),
        ],
      );
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) => RichText(
        textAlign: TextAlign.center,
        text: const TextSpan(
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.6),
          children: [
            TextSpan(text: 'ASKODOX '),
            TextSpan(text: 'AI', style: TextStyle(color: AskodoxDesignTokens.violet100)),
          ],
        ),
      );
}

class _CompactMascot extends StatelessWidget {
  const _CompactMascot();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0xFF9A45FF), Color(0xFF3759FF)]),
            boxShadow: const [BoxShadow(color: Color(0x667C38FF), blurRadius: 24, spreadRadius: 2)],
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFF080B19), borderRadius: BorderRadius.circular(24)),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.smart_toy_rounded, color: Colors.white, size: 50),
                Positioned(right: 9, bottom: 8, child: Icon(Icons.graphic_eq_rounded, color: AskodoxDesignTokens.violet100, size: 20)),
              ],
            ),
          ),
        ),
      );
}
