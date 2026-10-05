import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/askodox_video_service.dart';
import 'question_mic.dart';

String _pick(String lang, String en, String te, String hi) => switch (lang) { 'te' => te, 'hi' => hi, _ => en };

/// ASKODOX Video Study for ONE video (a YouTube result or the customer's own
/// upload): eligibility (hard length cap) -> study on request -> fact sheet
/// with the basis of every value -> grounded Q&A with timestamps -> external
/// market comparison (always labelled external) -> the existing request /
/// order flow, carrying what the video offers.
class AskodoxVideoStudyPanel extends ConsumerStatefulWidget {
  const AskodoxVideoStudyPanel({
    super.key,
    required this.videoRef,
    this.durationSeconds,
    this.lang = 'en',
    this.onFollow,
    this.onJump,
    this.initial,
  });

  /// `yt_<id>` / `up_<sha>`; null = this video cannot be studied.
  final String? videoRef;
  final int? durationSeconds;
  final String lang;

  /// A next step in the SAME conversation (enquiry, similar nearby, offer).
  final void Function(String ask)? onFollow;

  /// Jump the player to a timestamp (seconds).
  final void Function(int seconds)? onJump;

  /// A study the caller already has (an upload studied with its attachment).
  final AskodoxVideoStudy? initial;

  @override
  ConsumerState<AskodoxVideoStudyPanel> createState() => _AskodoxVideoStudyPanelState();
}

class _AskodoxVideoStudyPanelState extends ConsumerState<AskodoxVideoStudyPanel> {
  AskodoxVideoStudy? _study;
  bool _busy = false;
  bool _asking = false;
  final _answers = <(String, AskodoxVideoAnswer)>[];
  Map<String, Object?>? _market;
  bool _marketBusy = false;
  final _question = TextEditingController();

  String get lang => widget.lang;
  bool get _tooLong => (widget.durationSeconds ?? 0) > askodoxVideoStudyMaxSeconds;

  @override
  void initState() {
    super.initState();
    _study = widget.initial;
    if (_study == null && widget.videoRef != null && !_tooLong) _loadStatus();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final status = await ref.read(askodoxVideoServiceProvider).studyStatus(widget.videoRef!, language: lang);
    if (mounted && status != null) setState(() => _study = status);
  }

  Future<void> _runStudy() async {
    setState(() => _busy = true);
    final study = await ref.read(askodoxVideoServiceProvider).study(widget.videoRef!, language: lang);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _study = study ??
          AskodoxVideoStudy(ref: widget.videoRef!, status: 'unavailable',
              message: _pick(lang, 'Video content analysis unavailable.', 'వీడియో కంటెంట్ విశ్లేషణ అందుబాటులో లేదు.',
                  'वीडियो कंटेंट विश्लेषण उपलब्ध नहीं है।'));
    });
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _asking) return;
    setState(() => _asking = true);
    _question.clear();
    final answer = await ref.read(askodoxVideoServiceProvider).ask(widget.videoRef!, q, language: lang);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _answers.add((
        q,
        answer ??
            AskodoxVideoAnswer(found: false, answer: _pick(lang, 'Could not get an answer right now.',
                'ఇప్పుడు సమాధానం రాలేదు.', 'अभी जवाब नहीं मिला।'))
      ));
    });
  }

  Future<void> _loadMarket() async {
    setState(() => _marketBusy = true);
    final market = await ref.read(askodoxVideoServiceProvider).market(widget.videoRef!, language: lang);
    if (!mounted) return;
    setState(() {
      _marketBusy = false;
      _market = market ?? const {};
    });
  }

  String _basisLabel(String basis) => switch (basis) {
        'confirmed_from_video' => _pick(lang, 'Confirmed from video', 'వీడియోలో కనిపించింది', 'वीडियो में दिखा'),
        'externally_verified' => _pick(lang, 'Externally verified', 'బయట ధృవీకరించబడింది', 'बाहर से सत्यापित'),
        'not_confirmed' => _pick(lang, 'Not confirmed', 'నిర్ధారించలేదు', 'पुष्टि नहीं'),
        _ => _pick(lang, 'Seller claim', 'విక్రేత చెప్పినది', 'विक्रेता का दावा'),
      };

  Color _basisColor(String basis) =>
      basis == 'confirmed_from_video' ? const Color(0xFF0F7B3F) : const Color(0xFF9A5B00);

  Widget _timestamp(String key, String ts) => ActionChip(
        key: ValueKey(key),
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.play_arrow_rounded, size: 16),
        label: Text(ts),
        onPressed: widget.onJump == null
            ? null
            : () {
                final seconds = askodoxTimestampSeconds(ts);
                if (seconds != null) widget.onJump!(seconds);
              },
      );

  void _follow(String ask) => widget.onFollow?.call(ask);

  @override
  Widget build(BuildContext context) {
    if (widget.videoRef == null && widget.initial == null) return const SizedBox.shrink();
    if (_tooLong || (_study != null && _study!.reason == 'too_long')) {
      return _note(const Key('askodoxVideoStudyTooLong'), Icons.timer_outlined,
          _study?.message.isNotEmpty == true
              ? _study!.message
              : _pick(lang, 'ASKODOX Video Study is currently available for videos up to 3 minutes.',
                  'ASKODOX వీడియో స్టడీ ప్రస్తుతం 3 నిమిషాల వరకు ఉన్న వీడియోలకు మాత్రమే అందుబాటులో ఉంది.',
                  'ASKODOX वीडियो स्टडी अभी 3 मिनट तक के वीडियो के लिए उपलब्ध है।'));
    }
    final study = _study;
    // Nothing until the backend says the video is studyable (an external
    // video, or a failed status call, never shows a Study button).
    if (study == null) return const SizedBox.shrink();
    if (!study.ready && study.status == 'none' && study.eligible) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('askodoxVideoStudyButton'),
          onPressed: _busy || widget.videoRef == null ? null : _runStudy,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_motion_rounded),
          label: Text(_busy
              ? _pick(lang, 'ASKODOX is studying the video…', 'ASKODOX వీడియోను అధ్యయనం చేస్తోంది…',
                  'ASKODOX वीडियो देख रहा है…')
              : _pick(lang, 'Study this video with ASKODOX', 'ఈ వీడియోను ASKODOXతో అధ్యయనం చేయండి',
                  'इस वीडियो को ASKODOX से समझें')),
        ),
      );
    }
    if (!study.ready) {
      return _note(const Key('askodoxVideoStudyUnavailable'), Icons.visibility_off_outlined,
          study.message.isNotEmpty
              ? study.message
              : _pick(lang, 'Video content analysis unavailable.', 'వీడియో కంటెంట్ విశ్లేషణ అందుబాటులో లేదు.',
                  'वीडियो कंटेंट विश्लेषण उपलब्ध नहीं है।'));
    }
    final context0 = study.contextLine();
    return Column(key: const Key('askodoxVideoStudy'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        key: const Key('askodoxVideoFactSheet'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD6E0FF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_pick(lang, 'FROM THE VIDEO', 'వీడియోలో ఉన్నది', 'वीडियो में'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: .6,
                  color: Color(0xFF10204A))),
          if (study.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(study.summary, style: const TextStyle(height: 1.35)),
          ],
          const SizedBox(height: 6),
          for (final f in study.facts)
            Padding(
              key: ValueKey('askodoxVideoFact-${f.key}'),
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${f.label}: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(f.value),
                Text(_basisLabel(f.basis),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _basisColor(f.basis))),
                if (f.timestamp.isNotEmpty) _timestamp('askodoxVideoTs-${f.key}', f.timestamp),
              ]),
            ),
          if (study.missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_pick(lang, 'Not confirmed in the video', 'వీడియోలో నిర్ధారించలేదు', 'वीडियो में पुष्टि नहीं')}: '
              '${study.missing.join(', ')}',
              key: const Key('askodoxVideoMissing'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      Text(_pick(lang, 'Ask ASKODOX about this video', 'ఈ వీడియో గురించి ASKODOXని అడగండి',
              'इस वीडियो के बारे में ASKODOX से पूछें'),
          style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final (i, q) in study.suggestedQuestions.indexed)
          ActionChip(
            key: ValueKey('askodoxVideoQ-$i'),
            visualDensity: VisualDensity.compact,
            label: Text(q),
            onPressed: _asking ? null : () => _ask(q),
          ),
      ]),
      for (final (i, (q, a)) in _answers.indexed)
        Container(
          key: ValueKey('askodoxVideoAnswer-$i'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: a.found ? Colors.white : const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE1E8F2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF10204A))),
            const SizedBox(height: 4),
            Text(a.answer, style: const TextStyle(height: 1.35)),
            if (a.timestamps.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final t in a.timestamps) _timestamp('askodoxVideoAnswerTs-$i-$t', t),
              ]),
          ]),
        ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('askodoxVideoAskField'),
            controller: _question,
            textInputAction: TextInputAction.send,
            onSubmitted: _ask,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: _pick(lang, 'Ask about this video…', 'ఈ వీడియో గురించి అడగండి…', 'इस वीडियो के बारे में पूछें…'),
            ),
          ),
        ),
        // Speak the question here: the mic records INTO this video's Q&A.
        AskodoxQuestionMic(
          lang: lang,
          onText: (words) {
            _question.text = words;
            if (!_asking) unawaited(_ask(words));
          },
        ),
        IconButton(
          key: const Key('askodoxVideoAskSend'),
          onPressed: _asking ? null : () => _ask(_question.text),
          icon: _asking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
        ),
      ]),
      const SizedBox(height: 10),
      if (_market == null)
        OutlinedButton.icon(
          key: const Key('askodoxVideoMarket'),
          onPressed: _marketBusy ? null : _loadMarket,
          icon: _marketBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.query_stats_rounded, size: 18),
          label: Text(_pick(lang, 'Compare with market', 'మార్కెట్‌తో పోల్చండి', 'बाज़ार से तुलना करें')),
        )
      else
        _marketSection(_market!),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label, ask) in [
          ('interested', _pick(lang, "I'm interested -- enquire", 'ఆసక్తి ఉంది -- విచారించండి', 'रुचि है -- पूछताछ करें'),
           _pick(lang, "I'm interested in $context0. Send an enquiry to the seller.",
               '$context0 పై నాకు ఆసక్తి ఉంది. విక్రేతకు విచారణ పంపండి.', '$context0 में मेरी रुचि है। विक्रेता को पूछताछ भेजें।')),
          ('offer', _pick(lang, 'Make an offer', 'ఆఫర్ ఇవ్వండి', 'ऑफ़र दें'),
           _pick(lang, 'I want to make an offer for $context0', '$context0 కోసం నేను ఆఫర్ ఇవ్వాలనుకుంటున్నాను',
               '$context0 के लिए मैं ऑफ़र देना चाहता हूँ')),
          ('similar', _pick(lang, 'Find similar nearby', 'దగ్గరలో ఇలాంటివి', 'पास में ऐसे ही'),
           _pick(lang, '${study.subject.isEmpty ? context0 : study.subject} near me',
               'దగ్గరలో ${study.subject.isEmpty ? context0 : study.subject}', 'पास में ${study.subject.isEmpty ? context0 : study.subject}')),
          ('lower', _pick(lang, 'Find lower price', 'తక్కువ ధరలో', 'कम कीमत में'),
           _pick(lang, '${study.subject.isEmpty ? context0 : study.subject} lower price',
               'తక్కువ ధరలో ${study.subject.isEmpty ? context0 : study.subject}', 'कम कीमत में ${study.subject.isEmpty ? context0 : study.subject}')),
          ('deals', _pick(lang, 'Show deals', 'డీల్స్', 'डील्स'),
           '${study.subject.isEmpty ? context0 : study.subject} offers'),
        ])
          ActionChip(
            key: ValueKey('askodoxVideoAction-$id'),
            label: Text(label),
            onPressed: widget.onFollow == null ? null : () => _follow(ask),
          ),
        ActionChip(
          key: const ValueKey('askodoxVideoAction-share'),
          avatar: const Icon(Icons.share_outlined, size: 16),
          label: Text(_pick(lang, 'Share', 'షేర్', 'शेयर')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '$context0 · via ASKODOX'));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_pick(lang, 'Copied -- paste it anywhere to share.',
                      'కాపీ అయింది -- ఎక్కడైనా పేస్ట్ చేసి షేర్ చేయండి.', 'कॉपी हुआ -- कहीं भी पेस्ट करके शेयर करें।'))));
            }
          },
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _pick(lang, 'Contact details are shared only after the seller accepts your request.',
              'విక్రేత మీ అభ్యర్థనను అంగీకరించిన తర్వాతే కాంటాక్ట్ వివరాలు పంచుకోబడతాయి.',
              'विक्रेता के अनुरोध स्वीकार करने के बाद ही संपर्क जानकारी साझा होती है।'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
        ),
      ),
    ]);
  }

  String _money(Object? value) {
    if (value is! num) return '';
    final v = value.toDouble();
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)} lakh';
    return '₹${v.toStringAsFixed(0)}';
  }

  Widget _marketSection(Map<String, Object?> data) {
    final market = data['market'] is Map ? Map<String, Object?>.from(data['market'] as Map) : const <String, Object?>{};
    final video = data['video_facts'] is Map ? Map<String, Object?>.from(data['video_facts'] as Map) : const <String, Object?>{};
    final asking = video['asking_price'] is Map ? Map<String, Object?>.from(video['asking_price'] as Map) : null;
    final prices = market['prices'] is Map ? Map<String, Object?>.from(market['prices'] as Map) : null;
    final negotiation =
        market['negotiation'] is Map ? Map<String, Object?>.from(market['negotiation'] as Map) : null;
    final rows = [for (final r in (market['rows'] as List? ?? const [])) if (r is Map) Map<String, Object?>.from(r)];
    final factors = [for (final f in (market['factors'] as List? ?? const [])) '$f'];
    return Container(
      key: const Key('askodoxVideoMarketSection'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0B64A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (asking != null)
          Text(
            '${_pick(lang, 'In the video (seller claim)', 'వీడియోలో (విక్రేత చెప్పినది)', 'वीडियो में (विक्रेता का दावा)')}: '
            '${asking['text']}',
            key: const Key('askodoxVideoMarketAsking'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        const SizedBox(height: 6),
        Text('${market['label'] ?? ''}'.toUpperCase(),
            key: const Key('askodoxVideoMarketLabel'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: .5,
                color: Color(0xFF7A5A00))),
        if (prices != null)
          Text(
            '${_pick(lang, 'Comparable asking prices', 'పోల్చదగిన ధరలు', 'तुलनीय कीमतें')} (${prices['count']}): '
            '${_money(prices['min'])} – ${_money(prices['max'])} · '
            '${_pick(lang, 'median', 'మధ్యస్థం', 'मध्य')} ${_money(prices['median'])} '
            '${_pick(lang, '(page prices, not verified)', '(పేజీ ధరలు, ధృవీకరించలేదు)', '(पेज कीमतें, सत्यापित नहीं)')}',
            key: const Key('askodoxVideoMarketRange'),
          )
        else
          Text(_pick(lang, 'No comparable prices found right now.', 'ఇప్పుడు పోల్చదగిన ధరలు దొరకలేదు.',
              'अभी तुलनीय कीमतें नहीं मिलीं।')),
        if (negotiation != null)
          Text(
            '${_pick(lang, 'Possible negotiation range', 'బేరం పరిధి (అంచనా)', 'मोलभाव की संभावित सीमा')}: '
            '${_money(negotiation['low'])} – ${_money(negotiation['high'])} · ${negotiation['note'] ?? ''}',
            key: const Key('askodoxVideoMarketNegotiation'),
          ),
        for (final (i, r) in rows.take(5).indexed)
          Padding(
            key: ValueKey('askodoxVideoMarketRow-$i'),
            padding: const EdgeInsets.only(top: 4),
            child: Text('• ${r['title'] ?? ''}${r['price'] is num ? ' — ${_money(r['price'])}' : ''}',
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        if (factors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '${_pick(lang, 'Price depends on', 'ధరను ప్రభావితం చేసేవి', 'कीमत इन पर निर्भर')}: ${factors.join(', ')}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
          ),
      ]),
    );
  }

  Widget _note(Key key, IconData icon, String text) => Container(
        key: key,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF6F7FA), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF667085)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF344054)))),
        ]),
      );
}
