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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _state = AskodoxAiState.listening);
    context.go('/discover/voice');
  }

  void _openMenu() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openDrawer();
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

  void _goFromDrawer(String path) {
    Navigator.of(context).pop();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawer: Drawer(
        key: const Key('askodoxHomeDrawer'),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      BrandConfig.displayName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(BrandConfig.tagline),
                  ],
                ),
              ),
              ListTile(
                key: const Key('askodoxDrawerSearch'),
                leading: const Icon(Icons.search_rounded),
                title: const Text('Search'),
                onTap: () => _goFromDrawer('/search'),
              ),
              ListTile(
                key: const Key('askodoxDrawerAlerts'),
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Alerts'),
                onTap: () => _goFromDrawer('/alerts'),
              ),
              ListTile(
                key: const Key('askodoxDrawerProfile'),
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Profile'),
                onTap: () => _goFromDrawer('/profile'),
              ),
              ListTile(
                key: const Key('askodoxDrawerSettings'),
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Developer settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openSettings();
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          child: AskodoxActionButton(
            key: const Key('askodoxMenuButton'),
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onPressed: _openMenu,
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
            final contentMinHeight =
                constraints.maxHeight > 36 ? constraints.maxHeight - 36 : 0.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, compact ? 8 : 20, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: contentMinHeight),
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
                      BrandConfig.localPromise,
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
            sendKey: const Key('askodoxHomeSendButton'),
            voiceKey: const Key('askodoxMicButton'),
          ),
        ),
      ),
    );
  }
}
