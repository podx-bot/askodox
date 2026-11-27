import '../../config/theme/askodox_look.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import '../location/application/location_controller.dart' show LocationController;
import '../pos/data/pos_repository.dart';
import '../steps/presentation/step_kit.dart';
import '../money_home/money_home_store.dart' show askodoxMoneyShopProvider;
import 'guide_arrange.dart';
import 'guide_reminders.dart';
import 'guide_session_logic.dart';

enum _Phase { loading, time, consent, talk, summary }

/// The helper's session (owner 2026-11-26, design "ASKODOX గైడ్ ప్రయాణం" 8-16): how much time -> why we ask + permission ->
/// one adaptive question at a time (mic or typing; "I did not understand" / "why?" explain again in other words) ->
/// what is done and what is left. A short time is never refused: the rest waits and comes back as a reminder.
class AskodoxGuideSessionScreen extends ConsumerStatefulWidget {
  const AskodoxGuideSessionScreen({super.key});

  @override
  ConsumerState<AskodoxGuideSessionScreen> createState() => _AskodoxGuideSessionScreenState();
}

class _AskodoxGuideSessionScreenState extends ConsumerState<AskodoxGuideSessionScreen> {
  _Phase _phase = _Phase.loading;
  Map<String, Object?> _status = const {};
  int _minutes = 10;
  DateTime? _started;
  Timer? _clock;
  bool _timeUp = false;
  bool _busy = false;
  bool _showWhy = false;
  bool _consent = false;
  String _question = '';
  String _explanation = '';
  String _lastSaid = '';
  List<Map<String, Object?>> _facts = const [];
  List<String> _done = const [];
  List<String> _left = const [];
  bool _finished = false;
  String? _error;
  bool _gapSent = false;
  bool _arranged = false;
  AskodoxGuideArrangeUndo? _undo;
  final _answer = TextEditingController();

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String get _lang => Localizations.localeOf(context).languageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await ref.read(askodoxPosRepositoryProvider).guideSession(_lang);
      if (!mounted) return;
      setState(() {
        _status = st;
        _consent = st['consent'] == true;
        _done = askodoxGuideKeys(st['done']);
        _left = askodoxGuideKeys(st['remaining']);
        _phase = _Phase.time;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.time);
    }
  }

  Future<void> _pickTime(int minutes) async {
    setState(() {
      _minutes = minutes;
      _busy = true;
      _error = null;
    });
    try {
      final st = await ref.read(askodoxPosRepositoryProvider).guideStart(minutes);
      final fresh = await ref.read(askodoxPosRepositoryProvider).guideSession(_lang);
      if (!mounted) return;
      _status = {...st, ...fresh};
      _consent = _status['consent'] == true;
      _started = DateTime.now();
      _clock?.cancel();
      _clock = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_started != null && !_timeUp && askodoxGuideTimeUp(_started!, _minutes, DateTime.now()) && mounted) {
          setState(() => _timeUp = true);
        }
      });
      setState(() {
        _busy = false;
        _phase = _consent ? _Phase.talk : _Phase.consent;
        _question = '${_status['question'] ?? ''}';
      });
      if (_consent) _speak(_question);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _te ? 'ఇప్పుడు కలవలేకపోయాం. కొంచెం తర్వాత మళ్ళీ ప్రయత్నించండి.' : 'Could not connect now. Try again in a moment.';
        });
      }
    }
  }

  Future<void> _decide(bool allow) async {
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).guideConsent(allow);
      final fresh = await ref.read(askodoxPosRepositoryProvider).guideSession(_lang);
      if (!mounted) return;
      _status = {..._status, ...fresh};
      setState(() {
        _consent = allow;
        _busy = false;
        _phase = _Phase.talk;
        _question = '${_status['question'] ?? _question}';
      });
      _speak(_question);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _speak(String text) {
    if (!LocationController.askOnStart || text.isEmpty) return; // the real app only; tests stay silent
    unawaited(ref.read(askodoxGuideSpeakerProvider)(text, _lang));
  }

  Future<void> _send({bool notUnderstood = false, bool why = false, bool skip = false}) async {
    final said = _answer.text.trim();
    if (said.isEmpty && !notUnderstood && !why && !skip) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(askodoxPosRepositoryProvider).guideTurn(said, _lang, askedWhy: why, notUnderstood: notUnderstood, skip: skip);
      if (!mounted) return;
      final next = '${r['question'] ?? ''}';
      setState(() {
        _busy = false;
        _lastSaid = said.isNotEmpty ? said : _lastSaid;
        _answer.clear();
        _facts = [
          for (final f in (r['facts'] is List ? r['facts'] as List : const []))
            if (f is Map) Map<String, Object?>.from(f)
        ];
        _explanation = '${r['explanation'] ?? ''}';
        _done = askodoxGuideKeys(r['done']);
        _left = askodoxGuideKeys(r['remaining']);
        _finished = r['finished'] == true;
        if (_finished) {
          _phase = _Phase.summary;
          _clock?.cancel();
          unawaited(_arrange());
        } else {
          _question = next.isEmpty ? _question : next;
        }
      });
      if (!_finished) _speak(_explanation.isNotEmpty ? '$_explanation $_question' : _question);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _te ? 'జవాబు పంపలేకపోయాం. మళ్ళీ నొక్కండి.' : 'Could not send. Tap again.';
        });
      }
    }
  }

  Future<void> _stopForNow() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(askodoxPosRepositoryProvider).guidePause();
      if (!mounted) return;
      setState(() {
        _done = askodoxGuideKeys(r['done']);
        _left = askodoxGuideKeys(r['remaining']);
        _phase = _Phase.summary;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
    _clock?.cancel();
    unawaited(_arrange());
    unawaited(ref.read(askodoxGuideRemindersProvider.notifier).refresh(_lang));
  }

  /// Brings the pages the person's own answers point at to the front (move only; one tap undoes it).
  Future<void> _arrange() async {
    if (_arranged || !_consent) return;
    try {
      final r = await ref.read(askodoxPosRepositoryProvider).guideArrangement();
      if (r['ready'] != true) return;
      final undo = await askodoxApplyGuideArrangement(
        buyer: askodoxGuideKeys(r['buyer']),
        seller: askodoxGuideKeys(r['seller']),
        shop: ref.read(askodoxMoneyShopProvider),
      );
      if (!mounted) return;
      setState(() {
        _arranged = undo != null;
        _undo = undo;
      });
    } catch (_) {
      // The arrangement is a nicety: a failure leaves the person's pages as they were.
    }
  }

  Future<void> _undoArrange() async {
    await _undo?.restore();
    if (mounted) setState(() => _undo = null);
  }

  Future<void> _deleteMine() async {
    try {
      await ref.read(askodoxPosRepositoryProvider).guideDeleteFacts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const Key('askodoxGuideDeleted'),
        content: Text(_te ? 'మీరు చెప్పిన వివరాలన్నీ తొలగించాం.' : 'All the details you told were deleted.'),
      ));
    } catch (_) {}
  }

  Future<void> _gapSheet() async {
    final text = TextEditingController();
    var consent = false;
    var tell = true;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_te ? 'యాప్ లో లేనిది ఏం కావాలి?' : 'What do you need that the app does not have?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(key: const Key('askodoxFeatureGapText'), controller: text, minLines: 2, maxLines: 4),
            CheckboxListTile(
              key: const Key('askodoxFeatureGapConsent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: (v) => set(() => consent = v == true),
              title: Text(_te ? 'నా పేరు లేకుండా ఈ అవసరాన్ని ASKODOX టీమ్ కి పంపండి' : 'Send this need to the ASKODOX team, without my name'),
            ),
            CheckboxListTile(
              key: const Key('askodoxFeatureGapTell'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: tell,
              onChanged: (v) => set(() => tell = v == true),
              title: Text(_te ? 'తయారైనప్పుడు నాకు చెప్పండి' : 'Tell me when it is ready'),
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: const Key('askodoxFeatureGapSend'),
              onPressed: consent && text.text.trim().length >= 4 || (consent && text.text.isNotEmpty)
                  ? () async {
                      try {
                        await ref.read(askodoxPosRepositoryProvider).featureRequest(text.text.trim(), consent: true, tellMe: tell);
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (_) {
                        if (ctx.mounted) Navigator.of(ctx).pop(false);
                      }
                    }
                  : null,
              child: Text(_te ? 'పంపండి' : 'Send'),
            ),
          ]),
        ),
      ),
    );
    text.dispose();
    if (sent == true && mounted) setState(() => _gapSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final more = [
      AskodoxStepMore('askodoxGuideGapMenu', te ? 'యాప్ లో లేనిది కావాలి' : 'I need something the app lacks', Icons.add_box_outlined, _gapSheet),
      AskodoxStepMore('askodoxGuideDeleteMenu', te ? 'నేను చెప్పినవి తొలగించు' : 'Delete what I told', Icons.delete_outline, _deleteMine),
    ];
    switch (_phase) {
      case _Phase.loading:
        return AskodoxStepScaffold(
            title: te ? 'గైడ్' : 'Guide', body: const Center(child: CircularProgressIndicator()), more: more);
      case _Phase.time:
        return AskodoxStepScaffold(
          title: te ? 'గైడ్' : 'Guide',
          step: 1,
          total: 5,
          question: te ? 'ఇప్పుడు ఎంత టైం ఉంది?' : 'How much time do you have now?',
          hint: te
              ? 'ఎంత ఉన్నా సరే. ఇప్పుడు వీలైనంత చేసుకుందాం, మిగతాది మీకు వీలైనప్పుడు.'
              : 'Any amount is fine. We do as much as we can now, the rest when you can.',
          more: more,
          body: ListView(padding: const EdgeInsets.all(18), children: [
            if (_left.isNotEmpty && _done.isNotEmpty)
              _card(
                  te ? 'ఇంతకు ముందు చేసినవి మిగిలాయి: ${_left.map((k) => askodoxGuideTopicName(k, te: true)).join(', ')}' : 'Left from before: ${_left.map((k) => askodoxGuideTopicName(k, te: false)).join(', ')}',
                  const Color(0xFF392C01)),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in askodoxGuideTimeChoices)
                ChoiceChip(
                  key: ValueKey('askodoxGuideTime-$m'),
                  label: Text(askodoxGuideMinutesLabel(m, te: te), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  selected: _minutes == m,
                  onSelected: _busy ? null : (_) => _pickTime(m),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: askodoxStepBad))),
          ]),
        );
      case _Phase.consent:
        final points = askodoxGuideWhyPoints(te: te);
        return AskodoxStepScaffold(
          title: te ? 'గైడ్' : 'Guide',
          step: 2,
          total: 5,
          question: te ? 'మీ వివరాలు ఎందుకు అడుగుతున్నాం?' : 'Why do we ask for your details?',
          more: more,
          onBack: () => setState(() => _phase = _Phase.time),
          body: ListView(padding: const EdgeInsets.all(18), children: [
            for (final p in points) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card('• $p', askodoxStepGreenSoft)),
            OutlinedButton(
              key: const Key('askodoxGuideWhyMore'),
              onPressed: () => setState(() => _showWhy = !_showWhy),
              child: Text(te ? 'ఇవన్నీ ఎందుకు?' : 'Why all this?'),
            ),
            if (_showWhy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _card(
                    te
                        ? 'ఉదాహరణకు రేపు మీరు "బైక్ కి పెట్రోల్ ఎంత" అని అడిగితే, మీ బైక్ వివరాలతో లెక్క వేసి చెప్పడానికి. చెప్పడం ఇష్టం లేనిది వదిలేయొచ్చు.'
                        : 'For example, if you ask tomorrow "how much petrol for my bike", I can work it out with your bike. Anything you do not want to tell can be left out.',
                    const Color(0xFF392C01)),
              ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('askodoxGuideConsentNo'),
              onPressed: _busy ? null : () => _decide(false),
              child: Text(te ? 'వద్దు, వివరాలు దాచొద్దు. అయినా కొనసాగు' : 'No, do not keep details. Continue anyway'),
            ),
          ]),
          bottom: AskodoxStepBottom(
              key: const Key('askodoxGuideConsentYes'),
              label: te ? 'అనుమతి ఇస్తున్నా' : 'I allow it',
              busy: _busy,
              onPressed: () => _decide(true)),
        );
      case _Phase.talk:
        return AskodoxStepScaffold(
          title: te ? 'గైడ్' : 'Guide',
          step: 3,
          total: 5,
          question: _question,
          more: more,
          body: ListView(padding: const EdgeInsets.all(18), children: [
            if (_timeUp)
              _card(
                  te ? 'మీరు చెప్పిన ${askodoxGuideMinutesLabel(_minutes, te: true)} అయింది. ఇప్పుడు ఆపి, మిగతాది తర్వాత చేద్దామా?' : 'Your ${askodoxGuideMinutesLabel(_minutes, te: false)} are over. Stop now and do the rest later?',
                  const Color(0xFF392C01),
                  key: const Key('askodoxGuideTimeUp'),
                  action: TextButton(
                      key: const Key('askodoxGuideStopNow'), onPressed: _stopForNow, child: Text(te ? 'తర్వాత చేద్దాం' : 'Later'))),
            if (_lastSaid.isNotEmpty)
              Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: askodoxStepInk, borderRadius: BorderRadius.circular(18)),
                      child: Text(_lastSaid, style: const TextStyle(color: AskodoxLook.sheet, fontSize: 14)))),
            if (_facts.isNotEmpty)
              _card(
                  '${te ? 'నాకు అర్థమైనది' : 'What I understood'}: ${_facts.map((f) => '${f['value']}').join(', ')}', askodoxStepGreenSoft,
                  key: const Key('askodoxGuideUnderstood')),
            if (_explanation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: _card(_explanation, const Color(0xFF392C01), key: const Key('askodoxGuideExplain'))),
            const SizedBox(height: 12),
            TextField(
              key: const Key('askodoxGuideAnswerField'),
              controller: _answer,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(hintText: te ? 'ఇక్కడ రాయండి, లేదా మైక్ నొక్కి చెప్పండి' : 'Type here, or tap the mic and speak'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  key: const Key('askodoxGuideNotUnderstood'),
                  label: Text(te ? 'అర్థం కాలేదు' : 'I did not understand'),
                  onPressed: _busy ? null : () => _send(notUnderstood: true)),
              ActionChip(
                  key: const Key('askodoxGuideAskWhy'),
                  label: Text(te ? 'ఎందుకు అడుగుతున్నారు?' : 'Why do you ask?'),
                  onPressed: _busy ? null : () => _send(why: true)),
              ActionChip(
                  key: const Key('askodoxGuideSkip'),
                  label: Text(te ? 'ఇది వదిలేయి' : 'Skip this'),
                  onPressed: _busy ? null : () => _send(skip: true)),
            ]),
            if (_gapSent) ...[
              const SizedBox(height: 14),
              _gapBox(te),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: askodoxStepBad))),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxGuideNext'),
            label: te ? 'తర్వాత' : 'Next',
            busy: _busy,
            onPressed: _send,
            onSpoken: (words) {
              _answer.text = words;
              _send();
            },
          ),
        );
      case _Phase.summary:
        return AskodoxStepScaffold(
          title: te ? 'గైడ్' : 'Guide',
          step: 5,
          total: 5,
          question: _finished ? (te ? 'అంతా అయింది' : 'All done') : (te ? 'ఇంతవరకు చేశాం' : 'This far for now'),
          more: more,
          body: ListView(padding: const EdgeInsets.all(18), children: [
            if (_done.isNotEmpty)
              _card('${te ? 'అయినవి' : 'Done'}: ${_done.map((k) => askodoxGuideTopicName(k, te: te)).join(', ')}', askodoxStepGreenSoft,
                  key: const Key('askodoxGuideDone')),
            if (_left.isNotEmpty && !_finished)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _card('${te ? 'మిగిలినవి (తర్వాత)' : 'Left for later'}: ${_left.map((k) => askodoxGuideTopicName(k, te: te)).join(', ')}',
                      const Color(0xFF392C01),
                      key: const Key('askodoxGuideLeft'))),
            const SizedBox(height: 10),
            _card(
                te
                    ? 'Home లో పైన "సెటప్ మిగిలింది" చిప్ ఉంటుంది. నొక్కితే ఇక్కడినుంచే కొనసాగుతుంది. మార్పులు కనిపించడానికి యాప్ మూసి మళ్ళీ తెరవండి.'
                    : 'On Home there is a "Setup left" chip. Tap it to continue from here. Close and reopen the app to see the changes.',
                AskodoxLook.sheet),
            if (_arranged)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _card(
                      _undo != null
                          ? (te ? 'మీరు చెప్పినవాటిని బట్టి మీ పేజీలు ముందుకు పెట్టాను. ఏదీ దాచలేదు, తీసేయలేదు.' : 'I moved the pages you talked about to the front. Nothing was hidden or removed.')
                          : (te ? 'పేజీలు మునుపటిలా పెట్టాను.' : 'Your pages are back as they were.'),
                      AskodoxLook.sheet,
                      key: const Key('askodoxGuideArranged'),
                      action: _undo == null
                          ? null
                          : TextButton(key: const Key('askodoxGuideArrangeUndo'), onPressed: _undoArrange, child: Text(te ? 'వద్దు' : 'Undo')))),
            if (_gapSent) Padding(padding: const EdgeInsets.only(top: 10), child: _gapBox(te)),
          ]),
          bottom: AskodoxStepBottom(
              buttonKey: const Key('askodoxGuideHome'), label: te ? 'Home కి' : 'Go Home', onPressed: () => context.go('/')),
        );
    }
  }

  Widget _gapBox(bool te) => Container(
        key: const Key('askodoxFeatureGapBox'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF9398A5), width: 2), borderRadius: BorderRadius.circular(20), color: AskodoxLook.sheet),
        child: Column(children: [
          Text(te ? 'మీ కోసం ఇది తయారవుతోంది' : 'This is being made for you', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(te ? 'తయారైనప్పుడు మీకు చెప్తాం.' : 'We will tell you when it is ready.', style: const TextStyle(color: askodoxStepMuted)),
        ]),
      );

  Widget _card(String text, Color color, {Key? key, Widget? action}) => Container(
        key: key,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.5, color: askodoxStepInk))),
          if (action != null) action,
        ]),
      );
}
