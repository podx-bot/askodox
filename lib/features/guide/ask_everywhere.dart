import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui_switches.dart';
import '../home/application/conversation_archive.dart';
import '../home/presentation/question_mic.dart';
import 'guide_sheet.dart';
import 'in_app_guide.dart';
import 'screen_help.dart';

/// Owner 2026-11-26: no Guide chip, no guide button, no mics inside pages -- ONE "Ask" button on every page. The five
/// bottom-bar pages already carry the centre Ask; every other page gets this small button on its right edge. A tap
/// opens a small sheet ON that page: say or type what you need, the answer comes there (and is spoken) -- the person
/// is never sent to the chat room unless they choose it.
const askodoxAskShellRoots = {'/', '/money-home', '/mode', '/updates', '/profile'};

/// Where the Ask button shows: a page outside the bottom bar, not a private page (sign-in / payment), no keyboard
/// open, no walkthrough running.
bool askodoxAskShownOn(String pattern, String path, {double keyboard = 0, bool guiding = false}) =>
    askodoxAskEverywhereOn &&
    pattern.isNotEmpty &&
    !askodoxAskShellRoots.contains(pattern) &&
    !askodoxGuideIsPrivate(path) &&
    keyboard == 0 &&
    !guiding;

class AskodoxAskLayer extends ConsumerStatefulWidget {
  const AskodoxAskLayer({super.key, required this.child, this.router});
  final Widget child;
  final GoRouter? router;

  @override
  ConsumerState<AskodoxAskLayer> createState() => _AskodoxAskLayerState();
}

class _AskodoxAskLayerState extends ConsumerState<AskodoxAskLayer> {
  bool _queued = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.router?.routerDelegate.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AskodoxAskLayer old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routerDelegate.removeListener(_changed);
      widget.router?.routerDelegate.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.router?.routerDelegate.removeListener(_changed);
    super.dispose();
  }

  // The router notifies while the app is still building a frame: redraw after it.
  void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  (String pattern, String path) _where() {
    final config = widget.router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return ('', '');
    return (config.fullPath, config.uri.path);
  }

  Future<void> _ask(String pattern, String path) async {
    final navContext = widget.router?.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || _open) return;
    final te = Localizations.maybeLocaleOf(navContext)?.languageCode == 'te';
    setState(() => _open = true);
    final flow = await showModalBottomSheet<AskodoxGuideFlow>(
      context: navContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AskodoxAskSheet(help: askodoxScreenHelpFor(pattern), path: path, te: te),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (flow != null) ref.read(askodoxGuideProvider.notifier).start(flow);
  }

  @override
  Widget build(BuildContext context) {
    if (!askodoxAskEverywhereOn) return widget.child;
    final (pattern, path) = _where();
    final guiding = ref.watch(askodoxGuideProvider) != null;
    final keyboard = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final show = !_open && askodoxAskShownOn(pattern, path, keyboard: keyboard, guiding: guiding);
    return Stack(children: [
      widget.child,
      if (show)
        Positioned(
          right: 0,
          bottom: 168,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: te ? 'అడగండి' : 'Ask',
              child: Material(
                color: const Color(0xFF2E7D5B),
                elevation: 3,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(22))),
                child: InkWell(
                  key: const Key('askodoxAskHere'),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
                  onTap: () => _ask(pattern, path),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                      Text(te ? 'అడుగు' : 'Ask',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Say or type what you need on THIS page; the answer shows here and is spoken. Nothing else on the sheet.
class AskodoxAskSheet extends ConsumerStatefulWidget {
  const AskodoxAskSheet({super.key, required this.help, required this.path, required this.te});
  final AskodoxScreenHelp? help;
  final String path;
  final bool te;

  @override
  ConsumerState<AskodoxAskSheet> createState() => _AskodoxAskSheetState();
}

class _AskodoxAskSheetState extends ConsumerState<AskodoxAskSheet> {
  static const _device = MethodChannel('com.askodox.app/device');
  final _box = TextEditingController();
  String? _answer;
  String _asked = '';
  bool _asking = false;
  bool _none = false;
  AskodoxGuideFlow? _flow;

  bool get _te => widget.te;

  @override
  void dispose() {
    _box.dispose();
    askodoxGuideSpeechTurn++; // a closed sheet never keeps talking
    unawaited(_device.invokeMethod<bool>('stopSpeaking').then<void>((_) {}, onError: (Object _) {}));
    super.dispose();
  }

  Future<void> _go([String? spoken]) async {
    final question = (spoken ?? _box.text).trim();
    if (question.isEmpty || _asking) return;
    if (spoken != null) _box.text = spoken;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _asking = true;
      _asked = question;
      _answer = null;
      _none = false;
      _flow = askodoxFlowForQuestion(question);
    });
    final help = widget.help;
    final answer = await ref.read(askodoxGuideAnswererProvider)(
        question,
        help?.title(_te) ?? widget.path,
        help?.steps(_te) ?? const <String>[],
        [for (final f in askodoxGuideFlows.where(askodoxGuideAvailable)) _te ? f.titleTe : f.titleEn],
        _te ? 'te' : 'en');
    if (!mounted) return;
    setState(() {
      _asking = false;
      _answer = answer.isEmpty ? null : answer;
      _none = answer.isEmpty;
    });
    if (answer.isNotEmpty) {
      unawaited(ref.read(askodoxGuideSpeakerProvider)(answer, _te ? 'te' : 'en').catchError((_) {}));
    }
  }

  /// The person's own choice: take the same words to the chat (for things this page's helper cannot answer).
  void _toChat() {
    ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(_asked);
    final router = GoRouter.maybeOf(context);
    Navigator.pop(context);
    router?.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    return SafeArea(
      child: Padding(
        key: const Key('askodoxAskSheet'),
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'ఏం కావాలో చెప్పండి' : 'Say what you need',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('askodoxAskBox'),
                controller: _box,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: te ? 'ఇక్కడ రాయండి, లేదా మైక్ నొక్కి చెప్పండి' : 'Type here, or tap the mic and speak'),
              ),
            ),
            AskodoxQuestionMic(lang: te ? 'te' : 'en', followCentre: false, always: true, onText: (text) => _go(text)),
            IconButton(
              key: const Key('askodoxAskSend'),
              onPressed: _asking ? null : () => _go(),
              icon: _asking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ]),
          if (_answer != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('askodoxAskAnswer'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F8F4), borderRadius: BorderRadius.circular(12)),
              child: Text(_answer!, style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          ],
          if (_none) ...[
            const SizedBox(height: 12),
            Text(te ? 'దీనికి జవాబు ఈ పేజీలో దొరకలేదు.' : 'I could not answer that from this page.',
                key: const Key('askodoxAskNone')),
          ],
          if (_answer != null || _none)
            Wrap(spacing: 8, children: [
              if (_flow != null)
                FilledButton.tonalIcon(
                  key: const Key('askodoxAskShow'),
                  onPressed: () => Navigator.pop(context, _flow),
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text(te ? 'స్క్రీన్ మీద చూపించు' : 'Show me on the screen'),
                ),
              TextButton(
                key: const Key('askodoxAskToChat'),
                onPressed: _toChat,
                child: Text(te ? 'చాట్‌లో అడుగు' : 'Ask in the chat'),
              ),
            ]),
        ]),
      ),
    );
  }
}
