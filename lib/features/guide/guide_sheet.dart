import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';
import '../../shared/widgets/askodox_mascot.dart';
import '../home/presentation/question_mic.dart';
import 'in_app_guide.dart';
import 'screen_help.dart';

/// Answers "how do I ...?" about the app, grounded on THIS screen's help and the guide list
/// (backend `/api/in-app/guide/ask`). "" when no answer came (the sheet says so honestly).
typedef AskodoxGuideAnswerer = Future<String> Function(
    String question, String screen, List<String> steps, List<String> guides, String locale);

final askodoxGuideAnswererProvider = Provider<AskodoxGuideAnswerer>((ref) => (question, screen, steps, guides, locale) async {
      try {
        final out = await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/in-app/guide/ask', body: {
          'question': question,
          'screen': screen,
          'steps': steps,
          'guides': guides,
          'locale': locale,
        });
        if (out case ApiSuccess<Map<String, Object?>>(:final data)) return '${data['answer'] ?? ''}'.trim();
      } catch (_) {}
      return '';
    });

/// The guide reads out loud by default (the person may not read); the speaker button turns it off for the session.
bool askodoxGuideVoiceOn = true;

/// Walkthroughs that END on this screen (its own "show me"), never ones that only pass through it.
/// (The screen of a flow = where its last step that names a screen happens.)
List<AskodoxGuideFlow> askodoxFlowsOwnedBy(String path) => [
      for (final f in askodoxGuideFlows)
        if ((f.steps.lastWhere((s) => s.route != null, orElse: () => f.steps.first).route ?? '').split('?').first == path) f,
    ];

/// A flow the question names (its keywords or title), or null.
AskodoxGuideFlow? askodoxFlowForQuestion(String question) {
  final q = question.toLowerCase();
  final howTo = askodoxGuideFor(q);
  if (howTo != null) return howTo;
  for (final f in askodoxGuideFlows) {
    if (f.keywords.any(q.contains) || q.contains(f.titleEn.toLowerCase()) || q.contains(f.titleTe)) return f;
  }
  return null;
}

/// What the guide button opens: this screen's help, READ ALOUD, a box (and mic) to ASK the guide anything
/// about the app, "show me" walkthroughs for this screen, and every other guide.
class AskodoxGuideSheet extends ConsumerStatefulWidget {
  const AskodoxGuideSheet({super.key, required this.help, required this.path, required this.te, this.welcome = false});
  final AskodoxScreenHelp help;
  final String path;
  final bool te;
  final bool welcome;

  @override
  ConsumerState<AskodoxGuideSheet> createState() => _AskodoxGuideSheetState();
}

class _AskodoxGuideSheetState extends ConsumerState<AskodoxGuideSheet> {
  static const _device = MethodChannel('com.askodox.app/device');
  final _ask = TextEditingController();
  String? _answer;
  AskodoxGuideFlow? _answerFlow;
  bool _asking = false;
  bool _speaking = false;

  bool get _te => widget.te;

  @override
  void initState() {
    super.initState();
    if (askodoxGuideVoiceOn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _say(_screenText()));
    }
  }

  @override
  void dispose() {
    _ask.dispose();
    if (_speaking) _device.invokeMethod<bool>('stopSpeaking').catchError((_) => null);
    super.dispose();
  }

  String _screenText() => [
        if (widget.welcome)
          _te
              ? 'ASKODOX కి స్వాగతం. ఏ పేజీలోనైనా సందేహం వస్తే గైడ్ బటన్ నొక్కండి.'
              : 'Welcome to ASKODOX. Whenever you are unsure, press the Guide button.',
        widget.help.title(_te),
        ...widget.help.steps(_te),
      ].join('. ');

  Future<void> _say(String text) async {
    if (!mounted) return;
    setState(() => _speaking = true);
    try {
      await ref.read(askodoxGuideSpeakerProvider)(text, _te ? 'te' : 'en');
    } catch (_) {}
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _toggleVoice() async {
    if (_speaking) {
      askodoxGuideVoiceOn = false;
      try {
        await _device.invokeMethod<bool>('stopSpeaking');
      } catch (_) {}
      if (mounted) setState(() => _speaking = false);
    } else {
      askodoxGuideVoiceOn = true;
      unawaited(_say(_answer ?? _screenText()));
    }
  }

  Future<void> _askNow([String? spoken]) async {
    final question = (spoken ?? _ask.text).trim();
    if (question.isEmpty || _asking) return;
    if (spoken != null) _ask.text = spoken;
    setState(() {
      _asking = true;
      _answer = null;
      _answerFlow = askodoxFlowForQuestion(question);
    });
    final guides = [for (final f in askodoxGuideFlows) if (f.listed || f.id.startsWith('screen_')) f.title(_te)];
    final answer = await ref.read(askodoxGuideAnswererProvider)(
        question, widget.help.title(_te), widget.help.steps(_te), guides, _te ? 'te' : 'en');
    if (!mounted) return;
    final shown = answer.isNotEmpty
        ? answer
        : (_answerFlow != null
            ? (_te ? 'దీనికి గైడ్ ఉంది — కింద "చూపించు" నొక్కండి.' : 'There is a guide for this — tap "Show me" below.')
            : (_te
                ? 'ఇప్పుడు జవాబు రాలేదు. ASKODOX చాట్‌లో అడగండి, లేదా కింద ఉన్న గైడ్‌లు చూడండి.'
                : 'No answer came right now. Ask in ASKODOX chat, or look at the guides below.'));
    setState(() {
      _asking = false;
      _answer = shown;
    });
    if (askodoxGuideVoiceOn) unawaited(_say(shown));
  }

  void _start(AskodoxGuideFlow flow) => Navigator.pop(context, flow);

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final own = askodoxFlowsOwnedBy(widget.path);
    final others = [for (final f in askodoxGuideFlows) if (f.listed && !own.contains(f)) f];
    return SafeArea(
      child: Padding(
        key: const Key('askodoxScreenHelpSheet'),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AskodoxMascot(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'ఇక్కడ ఏం చేయాలి' : 'What to do here', style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
                  Text(widget.help.title(te), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
              IconButton(
                key: const Key('askodoxGuideSpeak'),
                tooltip: _speaking ? (te ? 'ఆపు' : 'Stop') : (te ? 'చదివి వినిపించు' : 'Read aloud'),
                onPressed: _toggleVoice,
                icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
              ),
            ]),
            if (widget.welcome)
              Container(
                key: const Key('askodoxWelcomeGuide'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  te
                      ? 'ASKODOX కి స్వాగతం! ఏ పేజీలోనైనా సందేహం వస్తే ఎడమ వైపు ఉన్న ఈ ASKO "గైడ్" బటన్ నొక్కండి — ఆ పేజీలో ఏం చేయాలో చెబుతుంది, మీరు అడిగితే జవాబు ఇస్తుంది.'
                      : 'Welcome to ASKODOX! Whenever you are unsure on any page, press the ASKO "Guide" button on the left — it tells you what to do there and answers your questions.',
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
              ),
            const SizedBox(height: 12),
            for (final (i, step) in widget.help.steps(te).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFFEAF1FF),
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1769FF))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: const TextStyle(fontSize: 14.5, height: 1.35))),
                ]),
              ),
            // Ask the guide: type or speak.
            Container(
              padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFF), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD0DCF5))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('askodoxGuideAskField'),
                    controller: _ask,
                    onSubmitted: (_) => _askNow(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: te ? 'గైడ్‌ని అడగండి… ఉదా: పావు కిలో ధర ఎలా పెట్టాలి?' : 'Ask the guide… e.g. how do I set a ¼ kg rate?',
                    ),
                  ),
                ),
                AskodoxQuestionMic(lang: te ? 'te' : 'en', onText: (text) => _askNow(text)),
                IconButton(
                  key: const Key('askodoxGuideAskGo'),
                  onPressed: _asking ? null : () => _askNow(),
                  icon: _asking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ]),
            ),
            if (_answer != null)
              Container(
                key: const Key('askodoxGuideAnswer'),
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(10)),
                child: Text(_answer!, style: const TextStyle(fontSize: 14.5, height: 1.35)),
              ),
            if (_answerFlow != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.icon(
                  key: ValueKey('askodoxGuideAnswerFlow-${_answerFlow!.id}'),
                  onPressed: () => _start(_answerFlow!),
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text('${te ? 'స్క్రీన్‌పై చూపించు' : 'Show me'}: ${_answerFlow!.title(te)}'),
                ),
              ),
            const SizedBox(height: 10),
            for (final flow in own.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FilledButton.tonalIcon(
                  key: own.first == flow ? const Key('askodoxScreenHelpShowMe') : ValueKey('askodoxGuideFlow-${flow.id}'),
                  onPressed: () => _start(flow),
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text('${te ? 'స్క్రీన్‌పై చూపించు' : 'Show me on the screen'}: ${flow.title(te)}'),
                ),
              ),
            if (others.isNotEmpty)
              ExpansionTile(
                key: const Key('askodoxGuideMore'),
                tilePadding: EdgeInsets.zero,
                title: Text(te ? 'ఇంకా ఏమి నేర్చుకోవాలి?' : 'Learn something else'),
                children: [
                  for (final f in others)
                    ListTile(
                      key: ValueKey('askodoxGuideOther-${f.id}'),
                      dense: true,
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(f.title(te)),
                      onTap: () => _start(f),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: Text(te ? 'సరే' : 'OK')),
            ),
          ]),
        ),
      ),
    );
  }
}
