import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../matching/data/demo_natural_match_catalog.dart';
import '../../matching/data/universal_match_repository.dart';
import 'askodox_orb.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF667085);
const _accent = Color(0xFFFFC928);
const _blue = Color(0xFF1769FF);

class AskodoxPrimaryHomeScreen extends ConsumerStatefulWidget {
  const AskodoxPrimaryHomeScreen({super.key});
  @override
  ConsumerState<AskodoxPrimaryHomeScreen> createState() => _AskodoxPrimaryHomeScreenState();
}

class _AskodoxPrimaryHomeScreenState extends ConsumerState<AskodoxPrimaryHomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _store = ConversationTurnStore();
  final List<ConversationTurnRecord> _turns = [];
  List<UniversalMatch> _matches = const [];
  bool _active = false;

  bool get _te => ref.read(appSettingsProvider).locale?.languageCode == 'te';

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final records = await _store.load();
    if (!mounted || records.isEmpty) return;
    final deal = ref.read(universalDealControllerProvider).deal;
    setState(() {
      _turns.addAll(records);
      _active = true;
      if (deal != null) _matches = DemoNaturalMatchCatalog.forDeal(deal, enabled: true);
    });
    _scrollBottom();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;

    final notifier = ref.read(universalDealControllerProvider.notifier);
    final session = ref.read(universalDealControllerProvider);
    if (session.deal == null || session.completed) {
      if (session.deal != null) notifier.reset();
      notifier.start(text);
    } else {
      notifier.answer(text);
    }

    final deal = ref.read(universalDealControllerProvider).deal;
    final matches = deal == null
        ? const <UniversalMatch>[]
        : DemoNaturalMatchCatalog.forDeal(deal, enabled: true)
          ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));

    setState(() {
      _active = true;
      _matches = matches;
      _turns.add(ConversationTurnRecord(text: text, isUser: true));
      _turns.add(ConversationTurnRecord(text: _assistantReply(text, _te), isUser: false));
    });
    _controller.clear();
    await _store.save(_turns);
    _scrollBottom();
  }

  String _assistantReply(String text, bool te) {
    final q = text.toLowerCase();
    if (_has(q, ['job', 'work', 'ఉద్యోగం', 'జాబ్', 'computer operator'])) {
      return te ? 'మీరు ఉద్యోగం కోసం చూస్తున్నారు. మీ అవసరానికి సరిపోయే స్థానిక ఉద్యోగ అవకాశాలను చూపిస్తున్నాను.' : 'You’re looking for a job. I’m showing local openings that match your request.';
    }
    if (_has(q, ['ac repair', 'repair', 'service', 'plumber', 'electrician', 'మెకానిక్'])) {
      return te ? 'మీకు సర్వీస్ ప్రొవైడర్ కావాలి. దగ్గరలో అందుబాటులో ఉన్న సరైన ప్రొవైడర్లను చూపిస్తున్నాను.' : 'You need a service provider. Here are relevant nearby providers available to help.';
    }
    if (_has(q, ['ride', 'carpool', 'driver', 'passenger', 'రైడ్'])) {
      return te ? 'మీ రైడ్ అవసరాన్ని అర్థం చేసుకున్నాను. సరిపోయే డ్రైవర్ లేదా రైడ్ ఆప్షన్లను చూపిస్తున్నాను.' : 'I understand your ride request. Here are matching driver and ride options.';
    }
    if (_has(q, ['parcel', 'delivery', 'courier', 'పార్సెల్'])) {
      return te ? 'మీ పార్సెల్ లేదా డెలివరీ అవసరానికి సరిపోయే ఆప్షన్లను చూపిస్తున్నాను.' : 'Here are delivery and courier options that match your request.';
    }
    if (_has(q, ['chicken', 'చికెన్', 'కోడి', 'mutton', 'మటన్', 'meat'])) {
      return te ? 'మీకు చికెన్ లేదా మాంసం కావాలి. దగ్గరలో ఉన్న సంబంధిత విక్రేతలను మాత్రమే చూపిస్తున్నాను.' : 'You’re looking for chicken or meat. I’m showing only relevant nearby sellers.';
    }
    return te ? 'మీ అవసరాన్ని అర్థం చేసుకున్నాను. దానికి సంబంధించిన సరైన స్థానిక ఎంపికలను చూపిస్తున్నాను.' : 'I understand your request. Here are the most relevant local options.';
  }

  bool _has(String text, List<String> words) => words.any(text.contains);

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    return ColoredBox(color: const Color(0xFFF9FBFF), child: Column(children: [Expanded(child: _active ? _chat(te) : _home(te)), _composer(te)]));
  }

  Widget _home(bool te) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          const SizedBox(height: 8),
          Center(child: AskodoxVoiceOrb(onTap: () => context.push('/discover/voice'))),
          const SizedBox(height: 16),
          Text(te ? 'మీకు ఏ విధంగా సహాయం చేయగలను?' : 'How can I help you today?', textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          Text(te ? 'ఉద్యోగం, సర్వీస్, లోకల్ కొనుగోలు, రైడ్ లేదా డెలివరీ — మీ అవసరాన్ని సహజంగా చెప్పండి.' : 'Jobs, services, local buying, rides or delivery — just tell me naturally what you need.', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 15, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _quick(te ? 'ఉద్యోగం కావాలి' : 'I need a job', Icons.work_outline_rounded),
              _quick(te ? 'AC రిపేర్ కావాలి' : 'I need AC repair', Icons.home_repair_service_outlined),
              _quick(te ? 'చికెన్ కొనాలి' : 'Buy chicken nearby', Icons.storefront_outlined),
              _quick(te ? 'పార్సెల్ పంపాలి' : 'Send a parcel', Icons.local_shipping_outlined),
            ],
          ),
        ],
      );

  Widget _quick(String text, IconData icon) => ActionChip(avatar: Icon(icon, size: 18, color: _blue), label: Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)), onPressed: () => _send(text));

  Widget _chat(bool te) => ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          for (final turn in _turns)
            Align(
              alignment: turn.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 330),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: turn.isUser ? _blue : Colors.white, borderRadius: BorderRadius.circular(18), border: turn.isUser ? null : Border.all(color: const Color(0xFFE1E8F2))),
                child: Text(turn.text, style: TextStyle(color: turn.isUser ? Colors.white : _ink, height: 1.35, fontWeight: FontWeight.w500)),
              ),
            ),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [Text(te ? 'సంబంధిత ఎంపికలు' : 'Relevant matches', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink)), const Spacer(), const Text('DEMO', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800))]),
            const SizedBox(height: 10),
            ..._matches.map((match) => _MatchCard(match: match, te: te)),
          ],
        ],
      );

  Widget _composer(bool te) => Container(
        padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE1E7F0)))),
        child: Row(children: [
          IconButton.filled(onPressed: () => context.push('/discover/voice'), style: IconButton.styleFrom(backgroundColor: _accent), icon: const Icon(Icons.mic_rounded, color: _ink)),
          const SizedBox(width: 6),
          Expanded(child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            cursorColor: const Color(0xFF5B4BFF),
            style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: te ? 'మీకు ఏమి కావాలో చెప్పండి…' : 'Tell me what you need…',
              hintStyle: const TextStyle(color: Color(0xFF7B8496), fontWeight: FontWeight.w500),
              filled: true,
              fillColor: const Color(0xFFF8F9FC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Color(0xFFDDD9FF), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Color(0xFF6C4DFF), width: 2)),
            ),
          )),
          IconButton(onPressed: () => context.push('/discover/image'), icon: const Icon(Icons.image_outlined, color: _ink)),
          IconButton.filled(onPressed: _send, style: IconButton.styleFrom(backgroundColor: _blue), icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white)),
        ]),
      );

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.te});
  final UniversalMatch match;
  final bool te;

  @override
  Widget build(BuildContext context) {
    final distance = match.distanceKm == null ? null : '${match.distanceKm!.toStringAsFixed(1)} km';
    final price = match.price == null ? null : '₹${match.price!.toStringAsFixed(0)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFF0EFFF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF5B4BFF))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(match.title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 16)),
          if (match.subtitle != null) ...[const SizedBox(height: 4), Text(match.subtitle!, style: const TextStyle(color: _muted, height: 1.35, fontWeight: FontWeight.w500))],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (match.score != null) _meta('★ ${match.score!.toStringAsFixed(0)}%'),
            if (distance != null) _meta(distance),
            if (price != null) _meta(price),
          ]),
        ])),
      ]),
    );
  }

  Widget _meta(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFF6F7FA), borderRadius: BorderRadius.circular(20)), child: Text(text, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)));
}
