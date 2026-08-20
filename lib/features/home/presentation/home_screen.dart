import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../shared/widgets/askodox_ai_state.dart';
import '../../../shared/widgets/askodox_components.dart';
import '../../conversation/presentation/conversation_screen.dart';
import '../../developer/presentation/developer_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  AskodoxAiState _state = AskodoxAiState.idle;

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

  void _submitAsk() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _state = AskodoxAiState.understanding);
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationScreen(initialQuery: text),
          ),
        )
        .whenComplete(() {
      if (mounted) setState(() => _state = AskodoxAiState.idle);
    });
  }

  void _selectQuickAsk(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _focusNode.requestFocus();
  }

  void _startVoice() {
    setState(() => _state = AskodoxAiState.listening);
    context.go('/discover/voice');
  }

  void _openSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'askodox-developer-settings'),
        builder: (_) => const DeveloperSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      key: const Key('askodoxHomeScaffold'),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          child: AskodoxActionButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            size: 56,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
            child: AskodoxActionButton(
              key: const Key('askodoxSettingsButton'),
              icon: Icons.tune_rounded,
              tooltip: 'Settings',
              onPressed: _openSettings,
              size: 56,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 610 || keyboardOpen;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, compact ? 8 : 20, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 36).clamp(0, double.infinity),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!keyboardOpen)
                      KeyedSubtree(
                        key: const Key('askodoxOrb'),
                        child: AskodoxAiStateVisual(
                          state: _state,
                          size: compact ? 170 : 220,
                          showLabel: _state != AskodoxAiState.idle,
                        ),
                      ),
                    if (!keyboardOpen) SizedBox(height: compact ? 14 : 24),
                    Text(
                      BrandConfig.assistantName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BrandConfig.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask anything local. Buy, sell, work, services or rides.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                    SizedBox(height: compact ? 14 : 24),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickAsks.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => AskodoxIntentChip(
                          key: Key('askodoxQuickAsk$index'),
                          label: _quickAsks[index],
                          onPressed: () => _selectQuickAsk(_quickAsks[index]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          key: const Key('askodoxComposerBar'),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          color: Theme.of(context).colorScheme.surface,
          child: AskodoxComposer(
            controller: _controller,
            focusNode: _focusNode,
            onSend: _submitAsk,
            onAdd: () {},
            onVoice: _startVoice,
            hintText: BrandConfig.askHint,
            fieldKey: const Key('askodoxAskField'),
            voiceKey: const Key('askodoxMicButton'),
          ),
        ),
      ),
    );
  }
}
