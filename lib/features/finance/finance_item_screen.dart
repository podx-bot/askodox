import '../../config/theme/askodox_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';
import '../steps/presentation/step_kit.dart';

/// Finance item (owner 2026-11-25): an insurance / loan / card offer answered from the COMPANY'S OWN document.
/// 1 ask (checked points, ready questions, a box + mic) -> 2 the answer with its page, or "not in the document" and
/// a card asking "shall our executive call you?" (the number is passed only on a yes) -> 3 ✓ they will call.
/// ASKODOX gives no advice here: every answer says where in the document it stands.
String askodoxFinanceKindLabel(String kind, bool te) => switch (kind) {
      'insurance' => te ? 'ఇన్సూరెన్స్' : 'Insurance',
      'loan' => te ? 'లోన్' : 'Loan',
      'credit_card' => te ? 'క్రెడిట్ కార్డ్' : 'Credit card',
      _ => te ? 'ఫైనాన్స్' : 'Finance',
    };

/// Where an answer came from, in the customer's words (never empty for a found answer).
String askodoxFinanceSourceLabel(Map<String, Object?> answer, bool te) {
  if (answer['source'] == 'executive') return te ? '📞 మా ఎగ్జిక్యూటివ్ చెప్పిన జవాబు' : '📞 Answer from our executive';
  final page = answer['page'];
  final name = '${answer['document'] ?? ''}'.trim();
  final where = te ? 'పేజీ $page' : 'page $page';
  return name.isEmpty ? '📄 $where' : '📄 $name · $where';
}

/// The finance item id inside a result card id (`catalog-12` -> `12`); null for any other card.
String? askodoxFinanceItemIdOf(String matchId, String? itemType) {
  if (itemType != 'financial_offer' || !matchId.startsWith('catalog-')) return null;
  final id = matchId.substring('catalog-'.length);
  return RegExp(r'^\d+$').hasMatch(id) ? id : null;
}

class AskodoxFinanceItemScreen extends ConsumerStatefulWidget {
  const AskodoxFinanceItemScreen({super.key, required this.itemId});
  final String itemId;

  @override
  ConsumerState<AskodoxFinanceItemScreen> createState() => _FinanceItemState();
}

class _FinanceItemState extends ConsumerState<AskodoxFinanceItemScreen> {
  Map<String, Object?>? _item;
  String? _problem;
  int _step = 0;
  bool _busy = false;
  String _asked = '';
  Map<String, Object?>? _answer;
  String _when = 'now';
  String? _callbackId;
  final _question = TextEditingController();

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result =
        await ref.read(apiClientProvider).get<Map<String, Object?>>('/api/finance/items/${widget.itemId}');
    if (!mounted) return;
    setState(() {
      if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
        _item = data;
        _problem = null;
      } else {
        _problem = _t('This offer is not available now.', 'ఈ ఆఫర్ ఇప్పుడు అందుబాటులో లేదు.');
      }
    });
  }

  Future<void> _ask([String? ready]) async {
    final text = (ready ?? _question.text).trim();
    if (text.length < 3 || _busy) return;
    setState(() => _busy = true);
    final result = await ref.read(apiClientProvider).post<Map<String, Object?>>(
        '/api/finance/items/${widget.itemId}/ask',
        body: {'question': text, 'language': _te ? 'te' : 'en'},
        options: const ApiRequestOptions(timeout: Duration(seconds: 60)));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _asked = text;
      if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
        _answer = data;
        _step = 1;
        _question.clear();
      } else {
        _snack(_t('Could not get the answer. Try again.', 'జవాబు రాలేదు. మళ్ళీ ప్రయత్నించండి.'));
      }
    });
  }

  Future<void> _callMe() async {
    final session = ref.read(authSessionProvider);
    if (session.user == null) {
      _snack(_t('Sign in with your mobile number first.', 'ముందు మీ మొబైల్ నంబర్‌తో సైన్ ఇన్ అవ్వండి.'));
      context.push('/onboarding?signin=1');
      return;
    }
    setState(() => _busy = true);
    final result = await ref.read(apiClientProvider).post<Map<String, Object?>>(
        '/api/finance/items/${widget.itemId}/callback',
        // The customer tapped "Yes, call me": that tap is the consent.
        body: {'question': _asked, 'when': _when, 'consent': true},
        options: ApiRequestOptions(authToken: session.tokenPlaceholder));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
        _callbackId = '${data['id'] ?? ''}';
        _step = 2;
      } else {
        _snack(_t('Could not send it. Try again.', 'పంపలేకపోయాం. మళ్ళీ ప్రయత్నించండి.'));
      }
    });
  }

  Future<void> _cancelCall() async {
    final id = _callbackId;
    final session = ref.read(authSessionProvider);
    if (id == null || id.isEmpty) return;
    await ref
        .read(apiClientProvider)
        .delete<Map<String, Object?>>('/api/finance/callbacks/$id', options: ApiRequestOptions(authToken: session.tokenPlaceholder));
    if (!mounted) return;
    setState(() {
      _callbackId = null;
      _step = 0;
    });
    _snack(_t('Cancelled. Nobody will call.', 'రద్దు చేశాం. ఎవరూ కాల్ చేయరు.'));
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _back() {
    if (_step == 0) {
      context.canPop() ? context.pop() : context.go('/');
    } else {
      setState(() => _step = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = '${item?['title'] ?? ''}'.trim();
    if (item == null) {
      return AskodoxStepScaffold(
        key: const ValueKey('askodoxFinanceItem'),
        title: _t('Finance offer', 'ఫైనాన్స్ ఆఫర్'),
        onBack: _back,
        body: Center(
            child: _problem == null
                ? const CircularProgressIndicator()
                : Padding(padding: const EdgeInsets.all(24), child: Text(_problem!, textAlign: TextAlign.center))),
      );
    }
    final kind = askodoxFinanceKindLabel('${item['kind'] ?? ''}', _te);
    return AskodoxStepScaffold(
      key: const ValueKey('askodoxFinanceItem'),
      title: title.isEmpty ? kind : title,
      sub: kind,
      step: _step + 1,
      total: 3,
      onBack: _back,
      question: switch (_step) {
        0 => _t('What do you want to know?', 'మీకు ఏం తెలుసుకోవాలి?'),
        1 => _asked,
        _ => _t('We will call you', 'మేం కాల్ చేస్తాం'),
      },
      body: switch (_step) { 0 => _askBody(item), 1 => _answerBody(), _ => _doneBody() },
      bottom: switch (_step) {
        0 => AskodoxStepBottom(
            label: _t('Ask', 'అడుగు'),
            icon: Icons.question_answer_rounded,
            buttonKey: const ValueKey('askodoxFinanceAsk'),
            busy: _busy,
            onPressed: item['can_ask'] == true ? _ask : null,
            onSpoken: (said) => setState(() => _question.text = said),
          ),
        1 => _answer?['found'] == true
            ? AskodoxStepBottom(
                label: _t('Ask another', 'ఇంకో ప్రశ్న'),
                icon: Icons.add_comment_rounded,
                buttonKey: const ValueKey('askodoxFinanceAskMore'),
                onPressed: () => setState(() => _step = 0),
              )
            : AskodoxStepBottom(
                label: _t('Yes, call me', 'అవును, కాల్ చేయండి'),
                icon: Icons.call_rounded,
                buttonKey: const ValueKey('askodoxFinanceCallYes'),
                busy: _busy,
                onPressed: _callMe,
              ),
        _ => AskodoxStepBottom(
            label: _t('Done', 'సరే'),
            icon: Icons.check_rounded,
            buttonKey: const ValueKey('askodoxFinanceDone'),
            onPressed: () => setState(() => _step = 0),
          ),
      },
    );
  }

  Widget _note(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: const TextStyle(color: askodoxStepMuted, fontSize: 13, height: 1.35)),
      );

  Widget _askBody(Map<String, Object?> item) {
    final points = [for (final p in (item['points'] as List? ?? const [])) '$p'];
    final ready = [for (final q in (item['questions'] as List? ?? const [])) if (q is Map) '${q['question'] ?? ''}'];
    final canAsk = item['can_ask'] == true;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      if (!canAsk)
        _note(_t('The company\'s document is being added. Please check again soon.',
            'కంపెనీ document ఇంకా పెడుతున్నాం. కాసేపట్లో మళ్ళీ చూడండి.')),
      for (final p in points)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: askodoxStepGreen),
            const SizedBox(width: 8),
            Expanded(child: Text(p, style: const TextStyle(fontSize: 15, color: askodoxStepInk, height: 1.3))),
          ]),
        ),
      if (canAsk) ...[
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('askodoxFinanceQuestion'),
          controller: _question,
          minLines: 1,
          maxLines: 3,
          maxLength: 300,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _ask(),
          decoration: InputDecoration(
            hintText: _t('Type your doubt (or use the mic)', 'మీ సందేహం రాయండి (లేదా మైక్ వాడండి)'),
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, q) in ready.indexed)
            if (q.trim().isNotEmpty)
              ActionChip(
                  key: ValueKey('askodoxFinanceReady-$i'),
                  label: Text(q, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onPressed: _busy ? null : () => _ask(q)),
        ]),
        const SizedBox(height: 12),
        _note(_t('Answers come only from the company\'s own document, with the page number. This is not advice.',
            'జవాబులు కంపెనీ ఇచ్చిన document నుంచి మాత్రమే, పేజీ నంబర్‌తో వస్తాయి. ఇది సలహా కాదు.')),
      ],
    ]);
  }

  Widget _answerBody() {
    final answer = _answer ?? const <String, Object?>{};
    final found = answer['found'] == true;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Text('${answer['answer'] ?? ''}',
          key: const ValueKey('askodoxFinanceAnswer'),
          style: const TextStyle(fontSize: 18, height: 1.4, color: askodoxStepInk, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      if (found) ...[
        Align(
            alignment: Alignment.centerLeft,
            child: AskodoxStepPill(askodoxFinanceSourceLabel(answer, _te), key: const ValueKey('askodoxFinanceSource'))),
        const SizedBox(height: 12),
        _note('${answer['not_advice'] ?? ''}'),
      ] else ...[
        Container(
          key: const ValueKey('askodoxFinanceCallCard'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              border: Border.all(color: askodoxStepLine), borderRadius: BorderRadius.circular(16), color: AskodoxLook.sheet),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('Shall our executive call you and tell you?', 'మా ఎగ్జిక్యూటివ్ కాల్ చేసి చెప్పమంటారా?'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: askodoxStepInk)),
            const SizedBox(height: 6),
            Text(
                _t('Only if you say yes, your number goes to our executive for this one call. No one else gets it.',
                    'మీరు "అవును" అంటేనే మీ నంబర్ ఈ ఒక్క కాల్ కోసం మా ఎగ్జిక్యూటివ్‌కి వెళ్తుంది. ఇంకెవరికీ ఇవ్వం.'),
                style: const TextStyle(fontSize: 13, color: askodoxStepMuted, height: 1.35)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, en, te) in const [
                ('now', 'Now', 'ఇప్పుడే'),
                ('evening', 'Evening', 'సాయంత్రం'),
                ('tomorrow', 'Tomorrow', 'రేపు'),
              ])
                ChoiceChip(
                    key: ValueKey('askodoxFinanceWhen-$key'),
                    label: Text(_t(en, te)),
                    selected: _when == key,
                    onSelected: (_) => setState(() => _when = key)),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              key: const ValueKey('askodoxFinanceCallNo'),
              onPressed: () => setState(() => _step = 0),
              child: Text(_t('No, thanks', 'వద్దు'))),
        ),
      ],
    ]);
  }

  Widget _doneBody() => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
        const Center(child: AskodoxStepDoneMark()),
        const SizedBox(height: 16),
        Text(
            switch (_when) {
              'evening' => _t('Our executive will call you this evening.', 'మా ఎగ్జిక్యూటివ్ ఈ సాయంత్రం కాల్ చేస్తారు.'),
              'tomorrow' => _t('Our executive will call you tomorrow.', 'మా ఎగ్జిక్యూటివ్ రేపు కాల్ చేస్తారు.'),
              _ => _t('Our executive will call you soon.', 'మా ఎగ్జిక్యూటివ్ త్వరలో కాల్ చేస్తారు.'),
            },
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: askodoxStepInk)),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
              key: const ValueKey('askodoxFinanceCallCancel'),
              onPressed: _cancelCall,
              child: Text(_t('I changed my mind: do not call', 'వద్దు, కాల్ చేయకండి'))),
        ),
      ]);
}
