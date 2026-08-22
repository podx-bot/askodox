import 'package:flutter/material.dart';

import '../../../config/brand/brand_config.dart';
import '../../../core/location/askodox_location_service.dart';
import '../../../shared/widgets/askodox_ai_state.dart';
import '../../../shared/widgets/askodox_components.dart';
import '../../location/presentation/askodox_map_picker_screen.dart';
import '../data/conversation_server_settings.dart';
import '../data/universal_conversation_client.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    this.initialQuery = '',
    this.client = const UniversalConversationClient(),
  });

  final String initialQuery;
  final UniversalConversationClient client;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ConversationMessage> _messages = [];
  final ConversationServerSettings _serverSettings =
      const ConversationServerSettings();
  String _senderId = '';
  String _runtimeBaseUrl = '';
  bool _sending = false;
  AskodoxAiState _aiState = AskodoxAiState.idle;

  UniversalConversationClient get _activeClient => widget.client.isConfigured
      ? widget.client
      : UniversalConversationClient(
          baseUrl: _runtimeBaseUrl,
          endpointPath: widget.client.endpointPath,
          locationEndpointPath: widget.client.locationEndpointPath,
          useProductionFallback: widget.client.useProductionFallback,
        );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    try {
      _senderId = await _serverSettings.loadOrCreateSenderId();
    } catch (_) {
      _senderId = 'app-${DateTime.now().microsecondsSinceEpoch}';
    }

    if (!widget.client.isConfigured) {
      try {
        final saved = await _serverSettings.loadBaseUrl();
        if (mounted && saved.isNotEmpty) {
          setState(() => _runtimeBaseUrl = saved);
        }
      } catch (_) {
        // Build-time configuration can still be used when local persistence is
        // unavailable, including lightweight widget-test hosts.
      }
    }

    final initial = widget.initialQuery.trim();
    if (mounted && initial.isNotEmpty) {
      await _send(initial);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureSenderId() async {
    if (_senderId.isNotEmpty) return;
    try {
      _senderId = await _serverSettings.loadOrCreateSenderId();
    } catch (_) {
      _senderId = 'app-${DateTime.now().microsecondsSinceEpoch}';
    }
  }

  Future<void> _sendFromComposer() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    await _send(text);
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;
    await _ensureSenderId();

    if (!mounted) return;
    setState(() {
      _messages.add(_ConversationMessage.user(text.trim()));
      _sending = true;
      _aiState = AskodoxAiState.thinking;
    });
    _scrollToBottom();

    final client = _activeClient;
    if (!client.isConfigured) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _ConversationMessage.assistant(
            'ASKODOX conversation server is not configured. Tap the server icon '
            'at the top, save the live https:// backend URL once, then send your '
            'message again. Future app updates keep this setting.',
          ),
        );
        _sending = false;
        _aiState = AskodoxAiState.error;
      });
      _scrollToBottom();
      return;
    }

    try {
      final reply = await client.send(
        senderId: _senderId,
        message: text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _aiState = AskodoxAiState.responding;
        _messages.add(_ConversationMessage.assistant(reply));
        _aiState = AskodoxAiState.completed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _ConversationMessage.assistant(
            'I could not reach ASKODOX right now. Check the server setting or try again in a moment.',
          ),
        );
        _aiState = AskodoxAiState.error;
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _chooseLocation() async {
    if (_sending) return;
    final point = await Navigator.of(context).push<AskodoxLocationPoint>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'askodox-map-picker'),
        builder: (_) => const AskodoxMapPickerScreen(),
      ),
    );
    if (point == null || !mounted) return;

    await _ensureSenderId();
    setState(() {
      _messages.add(
        _ConversationMessage.user(
          '📍 ${point.label ?? 'Shared location'} • '
          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        ),
      );
      _sending = true;
      _aiState = AskodoxAiState.thinking;
    });
    _scrollToBottom();

    try {
      final reply = await _activeClient.sendLocation(
        senderId: _senderId,
        latitude: point.latitude,
        longitude: point.longitude,
        locationName: point.label,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ConversationMessage.assistant(reply));
        _aiState = AskodoxAiState.completed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _ConversationMessage.assistant(
            'I could not save that location right now. Please try again.',
          ),
        );
        _aiState = AskodoxAiState.error;
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _showServerSettings() async {
    final controller = TextEditingController(
      text: _activeClient.resolvedBaseUrl,
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ASKODOX server'),
          content: TextField(
            key: const Key('askodoxServerUrlField'),
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Live backend URL',
              hintText: 'https://…',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('askodoxServerSave'),
              onPressed: () async {
                try {
                  await _serverSettings.saveBaseUrl(controller.text);
                  if (!mounted) return;
                  setState(() {
                    _runtimeBaseUrl = controller.text.trim();
                    _aiState = AskodoxAiState.idle;
                  });
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } on FormatException catch (error) {
                  setDialogState(() => errorText = error.message);
                } catch (_) {
                  setDialogState(
                    () => errorText = 'Could not save the server URL.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = _activeClient.isConfigured;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          BrandConfig.assistantName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            key: const Key('askodoxConversationLocation'),
            tooltip: 'Share location',
            onPressed: _sending ? null : _chooseLocation,
            icon: const Icon(Icons.location_on_outlined),
          ),
          IconButton(
            key: const Key('askodoxServerSettings'),
            tooltip: 'Conversation server',
            onPressed: _showServerSettings,
            icon: Icon(
              Icons.dns_rounded,
              color: configured
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _sending || _aiState == AskodoxAiState.error
                  ? Padding(
                      key: ValueKey(_aiState),
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: AskodoxAiStateVisual(
                        state: _aiState,
                        size: 82,
                        showLabel: true,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? const _EmptyConversation()
                  : ListView.builder(
                      key: const Key('askodoxConversationList'),
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _MessageBubble(
                        message: _messages[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
          child: AskodoxComposer(
            controller: _controller,
            onSend: _sendFromComposer,
            hintText: BrandConfig.askHint,
            enabled: !_sending,
            fieldKey: const Key('askodoxConversationField'),
            sendKey: const Key('askodoxConversationSend'),
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AskodoxAiStateVisual(
              state: AskodoxAiState.idle,
              size: 120,
            ),
            const SizedBox(height: 20),
            Text(
              'Tell ASKODOX what you need. Buy, sell, work, services and rides all start here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: Key(
          message.fromUser ? 'askodoxUserMessage' : 'askodoxAssistantMessage',
        ),
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.fromUser ? colors.primary : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: message.fromUser
              ? null
              : Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.fromUser ? colors.onPrimary : colors.onSurface,
            fontSize: 16,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ConversationMessage {
  const _ConversationMessage._(this.text, this.fromUser);

  const _ConversationMessage.user(String text) : this._(text, true);
  const _ConversationMessage.assistant(String text) : this._(text, false);

  final String text;
  final bool fromUser;
}
