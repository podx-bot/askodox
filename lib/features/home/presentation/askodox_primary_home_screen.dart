import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import 'askodox_orb.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF667085);
const _accent = Color(0xFFFFC928);
const _blue = Color(0xFF1769FF);

class AskodoxPrimaryHomeScreen extends ConsumerStatefulWidget {
  const AskodoxPrimaryHomeScreen({super.key});
  @override ConsumerState<AskodoxPrimaryHomeScreen> createState() => _AskodoxPrimaryHomeScreenState();
}

class _AskodoxPrimaryHomeScreenState extends ConsumerState<AskodoxPrimaryHomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _store = ConversationTurnStore();
  final List<ConversationTurnRecord> _turns = [];
  bool _active = false;
  bool get _te => ref.read(appSettingsProvider).locale?.languageCode == 'te';

  @override void initState() { super.initState(); unawaited(_restore()); }
  Future<void> _restore() async { final records = await _store.load(); if (!mounted || records.isEmpty) return; setState(() { _turns.addAll(records); _active = true; }); _scrollBottom(); }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim(); if (text.isEmpty) return;
    final notifier = ref.read(universalDealControllerProvider.notifier); final session = ref.read(universalDealControllerProvider);
    if (session.deal == null) { notifier.start(text); } else { notifier.answer(text); }
    setState(() { _active = true; _turns.add(ConversationTurnRecord(text: text, isUser: true)); _turns.add(ConversationTurnRecord(text: _te ? 'సరే. మీ అవసరాన్ని అర్థం చేసుకున్నాను. దగ్గరలో ఉన్న సరైన ఎంపికలను చూపిస్తున్నాను.' : 'Got it. I understand what you need. Here are the best nearby options.', isUser: false)); });
    _controller.clear(); await _store.save(_turns); _scrollBottom();
  }

  void _scrollBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (!_scrollController.hasClients) return; _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut); }); }

  @override Widget build(BuildContext context) { final te = _te; return ColoredBox(color: const Color(0xFFF9FBFF), child: Column(children: [Expanded(child: _active ? _chat(te) : _home(te)), _composer(te)])); }

  Widget _home(bool te) => ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 16), children: [
    _promo(), const SizedBox(height: 18), Center(child: AskodoxVoiceOrb(onTap: () => context.push('/discover/voice'))), const SizedBox(height: 12),
    Text(te ? 'మీకు ఏ విధంగా సహాయం చేయగలను చెప్పండి' : 'How can I help you today?', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink)),
    const SizedBox(height: 6), Text(te ? 'మీ అవసరాన్ని టైప్ చేయండి లేదా మాట్లాడండి.' : 'Type or speak what you need.', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 15, fontWeight: FontWeight.w600)),
    const SizedBox(height: 22), Row(children: [Text(te ? 'దగ్గరలో మీ కోసం' : 'Nearby for you', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)), const Spacer(), TextButton(onPressed: () => context.push('/nearby'), child: Text(te ? 'అన్నీ చూడండి' : 'See All'))]),
    SizedBox(height: 260, child: ListView(scrollDirection: Axis.horizontal, children: const [_ShopCard(name: 'Sri Lakshmi Chicken Shop', rating: '4.8', distance: '0.5 km', shopId: 'lakshmi-demo'), _ShopCard(name: 'Prana Chicken Shop', rating: '4.6', distance: '1.2 km', shopId: 'prana-demo'), _ShopCard(name: 'Srinivas Chicken', rating: '4.4', distance: '1.8 km', shopId: 'srinivas-demo')]))
  ]);

  Widget _chat(bool te) => ListView(controller: _scrollController, padding: const EdgeInsets.fromLTRB(14, 12, 14, 18), children: [
    for (final turn in _turns) Align(alignment: turn.isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: const BoxConstraints(maxWidth: 330), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: BoxDecoration(color: turn.isUser ? _blue : Colors.white, borderRadius: BorderRadius.circular(18), border: turn.isUser ? null : Border.all(color: const Color(0xFFE1E8F2))), child: Text(turn.text, style: TextStyle(color: turn.isUser ? Colors.white : _ink, height: 1.35, fontWeight: FontWeight.w500)))),
    if (_turns.isNotEmpty) ...[const SizedBox(height: 4), Text(te ? 'దగ్గరలో ఉన్న ఎంపికలు' : 'Nearby matches', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink)), const SizedBox(height: 10), SizedBox(height: 260, child: ListView(scrollDirection: Axis.horizontal, children: const [_ShopCard(name: 'Sri Lakshmi Chicken Shop', rating: '4.8', distance: '0.5 km', shopId: 'lakshmi-demo'), _ShopCard(name: 'Prana Chicken Shop', rating: '4.6', distance: '1.2 km', shopId: 'prana-demo'), _ShopCard(name: 'Srinivas Chicken', rating: '4.4', distance: '1.8 km', shopId: 'srinivas-demo')]))]
  ]);

  Widget _promo() => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF4D2), borderRadius: BorderRadius.circular(20)), child: Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Prana Chicken Shop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)), SizedBox(height: 3), Text('Fresh & Hygienic Chicken', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)), SizedBox(height: 9), Chip(label: Text('10% OFF • This Week'))])), Container(width: 88, height: 72, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.set_meal_rounded, size: 46, color: Color(0xFFE97A7A)))]));

  Widget _composer(bool te) => Container(
    padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
    decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE1E7F0)))),
    child: Row(children: [
      IconButton.filled(onPressed: () => context.push('/discover/voice'), style: IconButton.styleFrom(backgroundColor: _accent), icon: const Icon(Icons.mic_rounded, color: _ink)), const SizedBox(width: 6),
      Expanded(child: TextField(
        controller: _controller, focusNode: _focusNode, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), cursorColor: const Color(0xFF5B4BFF),
        style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: te ? 'టైప్ చేయండి లేదా మాట్లాడండి…' : 'Type or speak your request…', hintStyle: const TextStyle(color: Color(0xFF7B8496), fontWeight: FontWeight.w500),
          filled: true, fillColor: const Color(0xFFF8F9FC), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Color(0xFFDDD9FF), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Color(0xFF6C4DFF), width: 2)),
        ),
      )),
      IconButton(onPressed: () => context.push('/discover/image'), icon: const Icon(Icons.image_outlined, color: _ink)),
      IconButton.filled(onPressed: _send, style: IconButton.styleFrom(backgroundColor: _blue), icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white)),
    ]),
  );

  @override void dispose() { _controller.dispose(); _focusNode.dispose(); _scrollController.dispose(); super.dispose(); }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.name, required this.rating, required this.distance, required this.shopId});
  final String name; final String rating; final String distance; final String shopId;
  @override Widget build(BuildContext context) => Container(width: 190, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E9F2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(height: 105, decoration: const BoxDecoration(color: Color(0xFFFFECEC), borderRadius: BorderRadius.vertical(top: Radius.circular(18))), child: const Center(child: Icon(Icons.set_meal_rounded, size: 64, color: Color(0xFFE97A7A)))),
    Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)), const SizedBox(height: 6), Text('★ $rating   •   $distance', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 6), const Wrap(spacing: 5, children: [Chip(label: Text('Fresh')), Chip(label: Text('Hygienic'))]), SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: () => context.push('/shop/$shopId'), child: const Text('View →')))]))
  ]));
}
