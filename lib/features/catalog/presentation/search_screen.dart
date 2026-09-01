import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../matching/presentation/universal_match_screen.dart';

const _ink = Color(0xFF14213D);
const _muted = Color(0xFF667085);
const _purple = Color(0xFF6A3FD6);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _answer = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<_ChatTurn> _turns = [];
  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');

  bool _isTelugu(UniversalDeal? deal) {
    final selected = ref.watch(appSettingsProvider).locale?.languageCode == 'te';
    return selected || (deal != null && _telugu.hasMatch(deal.rawText));
  }

  void _syncLanguage(String text) {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    }
  }

  void _sendAnswer([String? preset]) {
    final text = (preset ?? _answer.text).trim();
    if (text.isEmpty) return;
    _syncLanguage(text);
    final te = _telugu.hasMatch(text) || ref.read(appSettingsProvider).locale?.languageCode == 'te';

    setState(() => _turns.add(_ChatTurn.user(text)));
    ref.read(universalDealControllerProvider.notifier).answer(text);
    final next = ref.read(universalDealControllerProvider);
    _answer.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _turns.add(_ChatTurn.assistant(_assistantText(next, te)));
    });
    _scrollToBottom();
  }

  void _start(String prompt) {
    _syncLanguage(prompt);
    ref.read(universalDealControllerProvider.notifier).start(prompt);
    setState(() => _turns.clear());
    _focusNode.requestFocus();
  }

  void _confirmAndMatch() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UniversalMatchScreen()));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(universalDealControllerProvider);
    final deal = session.deal;
    final te = _isTelugu(deal);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
        ),
        title: const Row(children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFE8F8ED),
            child: Icon(Icons.smart_toy_rounded, color: Color(0xFF10A53A), size: 20),
          ),
          SizedBox(width: 9),
          Text('ASKODOX', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
        ]),
        actions: [
          IconButton(
            tooltip: te ? 'కొత్త అవసరం' : 'New request',
            onPressed: () {
              ref.read(universalDealControllerProvider.notifier).reset();
              setState(() => _turns.clear());
              context.go('/');
            },
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF1769FF)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: deal == null ? _emptyState(te) : _conversation(session, deal, te),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool te) => ListView(
        padding: const EdgeInsets.fromLTRB(22, 42, 22, 24),
        children: [
          const _RobotThinking(size: 76),
          const SizedBox(height: 18),
          Text(
            te ? 'మీకు కావాల్సింది సహజంగా చెప్పండి' : 'Tell me what you need naturally',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink),
          ),
          const SizedBox(height: 9),
          Text(
            te
                ? 'ఫారం నింపాల్సిన అవసరం లేదు. అవసరమైన వివరాలు మాత్రమే నేను మాట్లాడుకుంటూ అడుగుతాను.'
                : 'No forms. I will ask only the details that are actually needed.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.45, fontSize: 15),
          ),
          const SizedBox(height: 26),
          for (final item in [
            (Icons.health_and_safety_outlined, te ? 'నా కుటుంబానికి హెల్త్ ఇన్సూరెన్స్ కావాలి' : 'I need health insurance for my family'),
            (Icons.work_outline_rounded, te ? 'నాకు ఉద్యోగం కావాలి' : 'I need a job'),
            (Icons.directions_car_outlined, te ? 'విజయవాడకి రైడ్ కావాలి' : 'I need a ride to Vijayawada'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                onPressed: () => _start(item.$2),
                icon: Icon(item.$1),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      );

  Widget _conversation(UniversalDealSession session, UniversalDeal deal, bool te) {
    final missing = deal.missingForMatch.firstOrNull;
    final quickReplies = _suggestionsFor(missing, te);

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              _UserBubble(text: deal.rawText),
              const SizedBox(height: 12),
              if (_turns.isEmpty)
                _AssistantBubble(text: _assistantText(session, te), thinking: !session.completed),
              for (final turn in _turns) ...[
                const SizedBox(height: 12),
                turn.isUser ? _UserBubble(text: turn.text) : _AssistantBubble(text: turn.text, thinking: false),
              ],
              if (session.completed) ...[
                const SizedBox(height: 14),
                _RequirementSummary(deal: deal, te: te),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('confirmRequirementButton'),
                  onPressed: _confirmAndMatch,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10A53A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(te ? 'సరే, మంచి మ్యాచ్‌లు చూపించు' : 'Okay, show me the best matches', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ] else if (quickReplies.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickReplies
                      .map((value) => ActionChip(
                            label: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                            onPressed: () => _sendAnswer(value),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        if (!session.completed) _composer(te),
      ],
    );
  }

  String _assistantText(UniversalDealSession session, bool te) {
    final deal = session.deal;
    if (deal == null) return te ? 'మీకు ఏమి కావాలి?' : 'What can I help you find?';
    if (session.completed) {
      return te
          ? 'సరే, అర్థమైంది. కావాల్సిన ముఖ్యమైన వివరాలు వచ్చాయి. నేను వాటిని ఒకసారి సరిచూసి మంచి మ్యాచ్‌లను వెతుకుతాను.'
          : 'Got it. I have the important details. I will verify them once and find the best matches.';
    }
    final field = deal.missingForMatch.firstOrNull;
    return _questionFor(field, te);
  }

  String _questionFor(String? field, bool te) {
    if (te) {
      return switch (field) {
        'subject' => 'సరే. మీకు ఖచ్చితంగా ఏది కావాలి?',
        'quantity' => 'సరే 👍 ఎంత చికెన్ కావాలి? ఉదాహరణకు 1 kg, 2 kg అని చెప్పండి.',
        'freshness' => 'ఫ్రెష్ / live-cut కావాలా, లేక chilled కూడా సరేనా?',
        'cut' => 'ఎలా కట్ చేయాలి? కర్రీ ముక్కలా, బిర్యానీ ముక్కలా, whole chickenలా?',
        'chickenPreference' => 'ఇంకేమైనా preference ఉందా? Skinless/with skin, front/back/mixed, breast/leg/wings, liver/gizzard — ఏది కావాలో చెప్పండి. ఏమీ లేకపోతే “ఏదైనా సరే” అనండి.',
        'fulfilment' => 'మీరు షాప్‌కి వెళ్లి తీసుకుంటారా, లేక delivery కావాలా?',
        'location' => 'ఏ ప్రాంతంలో చూడాలి? మీ ప్రస్తుత స్థానం ఉపయోగించాలంటే “నా ప్రస్తుత స్థానం” అనండి.',
        'timing' => 'ఎప్పుడు కావాలి?',
        'from' => 'ఎక్కడి నుంచి బయలుదేరాలి?',
        'to' => 'ఎక్కడికి వెళ్లాలి?',
        'skill' => 'ఏ పని లేదా skill కావాలి?',
        _ => 'ఇంకో చిన్న వివరము చెప్తారా?',
      };
    }
    return switch (field) {
      'subject' => 'Sure. What exactly do you need?',
      'quantity' => 'How much do you need? For example, 1 kg or 2 kg.',
      'freshness' => 'Do you want fresh/live-cut, or is chilled okay too?',
      'cut' => 'How should it be cut: curry cut, biryani cut, or whole?',
      'chickenPreference' => 'Any preference for skin, portion, breast/leg/wings, liver or gizzard? You can also say “no preference”.',
      'fulfilment' => 'Would you like pickup or delivery?',
      'location' => 'Which area should I search?',
      'timing' => 'When do you need it?',
      'from' => 'Where should the trip start?',
      'to' => 'Where should it go?',
      'skill' => 'What work or skill do you need?',
      _ => 'Tell me one more small detail.',
    };
  }

  List<String> _suggestionsFor(String? field, bool te) {
    if (te) {
      return switch (field) {
        'quantity' => ['1 kg', '2 kg', '3 kg'],
        'freshness' => ['ఫ్రెష్ / live-cut', 'Chilled కూడా సరే'],
        'cut' => ['కర్రీ కట్', 'బిర్యానీ కట్', 'Whole chicken'],
        'chickenPreference' => ['Skinless • mixed pieces', 'Leg pieces', 'Liver కూడా కావాలి', 'ఏదైనా సరే'],
        'fulfilment' => ['డెలివరీ కావాలి', 'పికప్ చేస్తాను'],
        'location' => ['నా ప్రస్తుత స్థానం'],
        'timing' => ['ఇప్పుడు', 'ఈరోజు', 'రేపు'],
        _ => const [],
      };
    }
    return switch (field) {
      'quantity' => ['1 kg', '2 kg', '3 kg'],
      'freshness' => ['Fresh / live-cut', 'Chilled is okay'],
      'cut' => ['Curry cut', 'Biryani cut', 'Whole chicken'],
      'chickenPreference' => ['Skinless • mixed', 'Leg pieces', 'Add liver', 'No preference'],
      'fulfilment' => ['Delivery', 'Pickup'],
      'location' => ['My current location'],
      'timing' => ['Now', 'Today', 'Tomorrow'],
      _ => const [],
    };
  }

  Widget _composer(bool te) => Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).viewPadding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8ECF3))),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _answer,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendAnswer(),
              decoration: InputDecoration(
                hintText: te ? 'మీ సమాధానం టైప్ చేయండి…' : 'Type your reply…',
                filled: true,
                fillColor: const Color(0xFFF3F5FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendAnswer,
            style: IconButton.styleFrom(backgroundColor: _purple),
            icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ]),
      );
}

class _ChatTurn {
  const _ChatTurn(this.text, this.isUser);
  factory _ChatTurn.user(String text) => _ChatTurn(text, true);
  factory _ChatTurn.assistant(String text) => _ChatTurn(text, false);
  final String text;
  final bool isUser;
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
        ),
      );
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.thinking});
  final String text;
  final bool thinking;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: _RobotThinking(size: 38)),
            const SizedBox(width: 10),
            Flexible(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 350),
                builder: (context, value, child) => Opacity(opacity: value, child: child),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5EAF2))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700, height: 1.5)),
                      if (thinking) ...[
                        const SizedBox(height: 8),
                        const _TypingDots(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _RobotThinking extends StatelessWidget {
  const _RobotThinking({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .92, end: 1),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeInOut,
        builder: (context, value, child) => Transform.scale(scale: value, child: child),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Color(0xFFE8F8ED), shape: BoxShape.circle),
          child: Icon(Icons.smart_toy_rounded, color: const Color(0xFF10A53A), size: size * .58),
        ),
      );
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();
  @override
  Widget build(BuildContext context) => const Text('●  ●  ●', style: TextStyle(color: Color(0xFF9AA3B2), letterSpacing: 2, fontSize: 9));
}

class _RequirementSummary extends StatelessWidget {
  const _RequirementSummary({required this.deal, required this.te});
  final UniversalDeal deal;
  final bool te;

  @override
  Widget build(BuildContext context) {
    final values = <String>[
      if (deal.quantity != null) '${deal.quantity!.toStringAsFixed(deal.quantity! % 1 == 0 ? 0 : 1)} ${deal.unit ?? ''}'.trim(),
      if (deal.dynamicFields['freshness'] != null) '${deal.dynamicFields['freshness']}',
      if (deal.dynamicFields['cut'] != null) '${deal.dynamicFields['cut']}',
      if (deal.dynamicFields['chickenPreference'] != null) '${deal.dynamicFields['chickenPreference']}',
      if (deal.fulfilment != null) deal.fulfilment!,
      if (deal.location.isKnown) deal.location.label ?? '',
    ].where((e) => e.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF1FAF4), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFCDEED8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(te ? 'నేను అర్థం చేసుకున్నది' : 'What I understood', style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(values.isEmpty ? deal.rawText : values.join(' • '), style: const TextStyle(color: _muted, height: 1.45, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}