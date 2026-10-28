import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/askodox_mascot.dart';
import '../../core/startup/startup_hint.dart';
import 'guide_sheet.dart';
import 'guide_watch.dart';
import 'in_app_guide.dart';
import 'screen_help.dart';

/// The guide button on EVERY screen (a small ASKO tab on the left edge). One
/// press opens "what to do here" for the screen on top, with "Show me on the
/// screen" when a walkthrough exists for it. Hidden while a walkthrough runs,
/// while the keyboard is open, and on exempt screens (sign-up, staff tools).
///
/// It also WATCHES: when the person sits on an empty box for a few seconds, or
/// something they did is refused, the tab asks "Need help?" by itself (no / yes:
/// what to write here, or explain the page) -- so fields need no "?" icons.
class AskodoxScreenHelpLayer extends ConsumerStatefulWidget {
  const AskodoxScreenHelpLayer({super.key, required this.child, this.router});
  final Widget child;
  final GoRouter? router;

  @override
  ConsumerState<AskodoxScreenHelpLayer> createState() => _AskodoxScreenHelpLayerState();
}

class _AskodoxScreenHelpLayerState extends ConsumerState<AskodoxScreenHelpLayer> {
  Timer? _idle;
  final _declined = <FocusNode>{};

  @override
  void initState() {
    super.initState();
    widget.router?.routerDelegate.addListener(_changed);
    FocusManager.instance.addListener(_focusChanged);
    AskodoxGuideNudges.instance.addListener(_changed);
  }

  /// Focus moved: if it is an empty text box, offer help after a pause.
  void _focusChanged() {
    _idle?.cancel();
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || ctx == null || _declined.contains(node)) return;
    final editable = ctx.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null) return;
    _idle = Timer(askodoxGuideIdleDelay, () {
      if (!mounted || FocusManager.instance.primaryFocus != node || editable.controller.text.trim().isNotEmpty) return;
      if (!node.context!.mounted) return;
      final info = node.context!.findAncestorWidgetOfExactType<AskodoxFieldGuideInfo>();
      final decoration = node.context!.findAncestorWidgetOfExactType<TextField>()?.decoration;
      final label = decoration?.labelText ?? '';
      _nudgeNode = node;
      AskodoxGuideNudges.instance.offer(AskodoxGuideNudge(
          kind: 'idle_field', messageEn: label, messageTe: label, field: info, fieldHint: decoration?.hintText ?? ''));
    });
  }

  FocusNode? _nudgeNode;

  void _decline() {
    if (_nudgeNode != null) _declined.add(_nudgeNode!);
    AskodoxGuideNudges.instance.clear();
  }

  /// "Yes" opens the answer IN PLACE (the same bubble grows): no popup on top
  /// of the page, the page stays usable, and the voice says exactly the words
  /// shown. An example the box already shows inside it is not repeated.
  ({String title, String body, String? example, AskodoxScreenHelp? help, String path})? _panel;

  void _accept(AskodoxGuideNudge nudge, AskodoxScreenHelp? help, String path) {
    final navContext = widget.router?.routerDelegate.navigatorKey.currentContext ?? context;
    final te = Localizations.maybeLocaleOf(navContext)?.languageCode == 'te';
    final field = nudge.field;
    final String title;
    final String body;
    String? example;
    if (nudge.kind == 'error') {
      title = te ? 'అది జరగలేదు' : 'That did not go through';
      body = '${te ? nudge.messageTe : nudge.messageEn}\n\n${te ? 'ఎరుపులో చూపిన బాక్స్ సరిచేసి మళ్ళీ ప్రయత్నించండి.' : 'Fix the box shown in red and try again.'}';
    } else if (field != null) {
      title = te ? field.titleTe : field.titleEn;
      body = te ? field.te : field.en;
      example = te ? field.exampleTe : field.exampleEn;
      if (askodoxExampleAlreadyShown(example, nudge.fieldHint)) example = null;
    } else {
      final label = te ? nudge.messageTe : nudge.messageEn;
      title = label.isEmpty ? (te ? 'ఇక్కడ ఏం రాయాలి' : 'What to write here') : label;
      body = te
          ? 'ఈ బాక్స్‌లో ${label.isEmpty ? 'అడిగిన వివరం' : '"$label"'} రాయండి.'
          : 'Type ${label.isEmpty ? 'what is asked' : '"$label"'} in this box.';
    }
    if (example != null && example.isEmpty) example = null;
    AskodoxGuideNudges.instance.clear();
    setState(() => _panel = (title: title, body: body, example: example, help: help, path: path));
    if (askodoxGuideVoiceOn) {
      final spoken = [title, body, if (example != null) '${te ? 'ఉదాహరణ' : 'Example'}: $example'].join('. ');
      unawaited(ref.read(askodoxGuideSpeakerProvider)(spoken, te ? 'te' : 'en').catchError((_) {}));
    }
  }

  void _closePanel({bool explain = false}) {
    final panel = _panel;
    if (panel == null) return;
    askodoxGuideSpeechTurn++; // a closed answer never keeps talking
    unawaited(const MethodChannel('com.askodox.app/device')
        .invokeMethod<bool>('stopSpeaking')
        .then<void>((_) {}, onError: (Object _) {}));
    setState(() => _panel = null);
    if (explain && panel.help != null) unawaited(_open(panel.help!, panel.path));
  }

  @override
  void didUpdateWidget(covariant AskodoxScreenHelpLayer old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routerDelegate.removeListener(_changed);
      widget.router?.routerDelegate.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    FocusManager.instance.removeListener(_focusChanged);
    AskodoxGuideNudges.instance.removeListener(_changed);
    widget.router?.routerDelegate.removeListener(_changed);
    super.dispose();
  }

  // The router notifies while the app is still building a frame: redraw after it.
  bool _queued = false;
  String _lastPath = '';
  void _changed() {
    final path = _where().$2;
    if (path != _lastPath) {
      _lastPath = path;
      _idle?.cancel();
      _declined.clear();
      _panel = null; // the answer belonged to the old page
      // A new page: an old "need help?" (idle box or refused action) no longer applies.
      if (AskodoxGuideNudges.instance.current != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => AskodoxGuideNudges.instance.clear());
      }
    }
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
    // A nudge can arrive while nothing is animating: make sure a frame comes.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  (String pattern, String path) _where() {
    final config = widget.router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return ('', '');
    return (config.fullPath, config.uri.path);
  }


  Future<void> _open(AskodoxScreenHelp help, String path, {bool welcome = false}) async {
    final navContext = widget.router?.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;
    final te = Localizations.maybeLocaleOf(navContext)?.languageCode == 'te';
    final flow = await showModalBottomSheet<AskodoxGuideFlow>(
      context: navContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AskodoxGuideSheet(help: help, path: path, te: te, welcome: welcome),
    );
    if (flow == null) return;
    // The walkthrough overlay points at each button (and offers "Take me there" when it is on another screen).
    ref.read(askodoxGuideProvider.notifier).start(flow);
  }

  @override
  Widget build(BuildContext context) {
    final (pattern, path) = _where();
    // The page the layer first shows is not a "page change" (that would clear a fresh nudge).
    if (_lastPath.isEmpty) _lastPath = path;
    final help = askodoxScreenHelpFor(pattern);
    final guiding = ref.watch(askodoxGuideProvider) != null;
    final keyboard = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final nudge = guiding || askodoxGuideIsPrivate(path) || pattern.isEmpty ? null : AskodoxGuideNudges.instance.current;
    final panel = guiding ? null : _panel;
    final show = help != null && !guiding && keyboard == 0 && !askodoxGuideIsPrivate(path);
    if (show && AskodoxStartupHint.justOnboarded && pattern == '/') {
      // First time on Home after sign-up: open the welcome guide once.
      AskodoxStartupHint.justOnboarded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(help, path, welcome: true);
      });
    }
    return Stack(children: [
      widget.child,
      if (panel != null)
        Positioned(
          left: 0,
          right: 16,
          bottom: keyboard > 0 ? keyboard + 12 : 168,
          child: SafeArea(
            top: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Material(
                color: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
                  side: BorderSide(color: Color(0xFFD0DCF5)),
                ),
                child: Padding(padding: EdgeInsets.fromLTRB(4, 4, 6, 4), child: AskodoxMascot(size: 30)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Material(
                  key: const Key('askodoxGuideNudgeSheet'),
                  color: Colors.white,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(panel.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(panel.body, style: const TextStyle(fontSize: 14, height: 1.35)),
                      if (panel.example != null) ...[
                        const SizedBox(height: 6),
                        Text('${te ? 'ఉదాహరణ' : 'Example'}: ${panel.example}',
                            style: const TextStyle(fontSize: 13.5, color: Color(0xFF1749B8))),
                      ],
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (panel.help != null)
                          TextButton(
                            key: const Key('askodoxGuideNudgeExplain'),
                            onPressed: () => _closePanel(explain: true),
                            child: Text(te ? 'ఈ పేజీ వివరించు' : 'Explain this page'),
                          ),
                        FilledButton(onPressed: _closePanel, child: Text(te ? 'అర్థమైంది' : 'Got it')),
                      ]),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      if (nudge != null && panel == null)
        Positioned(
          left: 0,
          right: 16,
          bottom: keyboard > 0 ? keyboard + 12 : 168,
          child: SafeArea(
            top: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Material(
                color: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
                  side: BorderSide(color: Color(0xFFD0DCF5)),
                ),
                child: Padding(padding: EdgeInsets.fromLTRB(4, 4, 6, 4), child: AskodoxMascot(size: 30)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Material(
                  key: const Key('askodoxGuideNudge'),
                  color: Colors.white,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        nudge.kind == 'error'
                            ? (te ? 'అది జరగలేదు — సహాయం కావాలా?' : 'That did not go through — need help?')
                            : (te ? 'ఇక్కడ ఏం రాయాలో సహాయం కావాలా?' : 'Need help with what to write here?'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                            key: const Key('askodoxGuideNudgeNo'), onPressed: _decline, child: Text(te ? 'వద్దు' : 'No')),
                        FilledButton(
                            key: const Key('askodoxGuideNudgeYes'),
                            onPressed: () => _accept(nudge, help, path),
                            child: Text(te ? 'అవును' : 'Yes')),
                      ]),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      if (show && nudge == null && panel == null)
        Positioned(
          left: 0,
          bottom: 168,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: te ? 'గైడ్: ఇక్కడ ఏం చేయాలి' : 'Guide: what to do here',
              child: Material(
                color: Colors.white,
                elevation: 3,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
                  side: BorderSide(color: Color(0xFFD0DCF5)),
                ),
                child: InkWell(
                  key: const Key('askodoxScreenHelpButton'),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
                  onTap: () => _open(help, path),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 6, 4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AskodoxMascot(size: 30),
                      SizedBox(height: 1),
                      _GuideLabel(),
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

class _GuideLabel extends StatelessWidget {
  const _GuideLabel();

  @override
  Widget build(BuildContext context) {
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    return Text(te ? 'గైడ్' : 'Guide',
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF1769FF)));
  }
}
