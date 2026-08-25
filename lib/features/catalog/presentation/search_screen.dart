import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../matching/presentation/universal_match_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _answer = TextEditingController();
  final _focusNode = FocusNode();
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

  void _sendAnswer() {
    final text = _answer.text.trim();
    if (text.isEmpty) return;
    _syncLanguage(text);
    ref.read(universalDealControllerProvider.notifier).answer(text);
    _answer.clear();
    _focusNode.requestFocus();
  }

  void _start(String prompt) {
    _syncLanguage(prompt);
    ref.read(universalDealControllerProvider.notifier).start(prompt);
    _focusNode.requestFocus();
  }

  void _confirmAndMatch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UniversalMatchScreen()),
    );
  }

  @override
  void dispose() {
    _answer.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(universalDealControllerProvider);
    final deal = session.deal;
    final te = _isTelugu(deal);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF14213D)),
        ),
        title: const Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFE8F8ED),
              child: Icon(Icons.smart_toy_rounded, color: Color(0xFF10A53A), size: 20),
            ),
            SizedBox(width: 9),
            Text('ASKODOX', style: TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New request',
            onPressed: () {
              ref.read(universalDealControllerProvider.notifier).reset();
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
        padding: const EdgeInsets.fromLTRB(22, 34, 22, 24),
        children: [
          const Icon(Icons.smart_toy_rounded, size: 72, color: Color(0xFF1769FF)),
          const SizedBox(height: 14),
          Text(
            te ? 'ASKODOX తో మాట్లాడండి' : 'Talk to ASKODOX',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
          ),
          const SizedBox(height: 8),
          Text(
            te ? 'వేరే Search page అవసరం లేదు. మీకు కావాల్సింది సహజంగా చెప్పండి.' : 'No separate search flow. Just say what you need naturally.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF667085), height: 1.45),
          ),
          const SizedBox(height: 24),
          for (final item in [
            (Icons.shopping_bag_outlined, te ? 'దగ్గరలో చికెన్ కావాలి' : 'I want chicken nearby'),
            (Icons.work_outline_rounded, te ? 'నాకు ఉద్యోగం కావాలి' : 'I need a job'),
            (Icons.directions_car_outlined, te ? 'విజయవాడకి రైడ్ కావాలి' : 'I need a ride to Vijayawada'),
          ])
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE5EAF2)),
              ),
              child: ListTile(
                onTap: () => _start(item.$2),
                leading: CircleAvatar(backgroundColor: const Color(0xFFEAF1FF), child: Icon(item.$1, color: const Color(0xFF1769FF))),
                title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
        ],
      );

  Widget _conversation(UniversalDealSession session, UniversalDeal deal, bool te) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(deal.rawText, style: const TextStyle(color: Color(0xFF14213D), fontSize: 16)),
            ),
          ),
          const SizedBox(height: 14),
          _understoodCard(deal, te),
          const SizedBox(height: 14),
          if (!session.completed) ...[
            _assistantBubble(_questionFor(deal, te)),
            const SizedBox(height: 12),
            _answerBox(te),
            const SizedBox(height: 9),
            Text(
              te ? 'ASKODOX మీరు చెప్పినది గుర్తుంచుకుని, మిగిలిన వివరమే అడుగుతుంది.' : 'ASKODOX remembers what you already said and asks only what is still missing.',
              style: const TextStyle(color: Color(0xFF667085), fontSize: 12.5),
            ),
          ] else ...[
            _readyCard(deal, te),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('confirmRequirementButton'),
              onPressed: _confirmAndMatch,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10A53A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(te ? 'మ్యాచ్‌లు కనుగొను' : 'Find my best matches', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _focusNode.requestFocus(),
              icon: const Icon(Icons.edit_outlined),
              label: Text(te ? 'మార్చాలి' : 'Change details'),
            ),
          ],
          const SizedBox(height: 24),
          _historyHint(te),
        ],
      );

  Widget _understoodCard(UniversalDeal deal, bool te) {
    final rows = <String>[
      if (deal.subject != null && deal.subject!.trim().isNotEmpty)
        '${te ? 'అవసరం' : 'Need'}: ${deal.subject}',
      if (deal.quantity != null) '${te ? 'పరిమాణం' : 'Quantity'}: ${deal.quantity} ${deal.unit ?? ''}',
      if (deal.price != null) '${te ? 'బడ్జెట్' : 'Budget'}: ₹${deal.price}',
      if (deal.location.isKnown)
        '${te ? 'లొకేషన్' : 'Location'}: ${deal.location.label ?? '${deal.location.latitude}, ${deal.location.longitude}'}',
      if (deal.timing != null) '${te ? 'సమయం' : 'Timing'}: ${deal.timing}',
    ];

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFFE8F8ED), child: Icon(Icons.psychology_alt_rounded, color: Color(0xFF10A53A))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                te ? 'నేను అర్థం చేసుకున్నది' : 'Here’s what I understood',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF14213D)),
              ),
            ),
          ]),
          const SizedBox(height: 13),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: Color(0xFF1769FF))),
                const SizedBox(width: 9),
                Expanded(child: Text(row, style: const TextStyle(fontSize: 15, color: Color(0xFF344054)))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _assistantBubble(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8ED),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.smart_toy_rounded, color: Color(0xFF10A53A), size: 20),
            const SizedBox(width: 9),
            Flexible(child: Text(text, style: const TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w700))),
          ]),
        ),
      );

  Widget _answerBox(bool te) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFB8CCFF)),
        ),
        child: TextField(
          key: const Key('askodoxClarificationField'),
          controller: _answer,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendAnswer(),
          decoration: InputDecoration(
            hintText: te ? 'ఈ వివరమే చెప్పండి…' : 'Answer only this detail…',
            prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1769FF)),
            suffixIcon: IconButton(onPressed: _sendAnswer, icon: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF1769FF))),
            border: InputBorder.none,
          ),
        ),
      );

  Widget _readyCard(UniversalDeal deal, bool te) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE8F8ED), Color(0xFFEAF1FF)]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.hub_rounded, color: Color(0xFF1769FF))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(te ? 'అవసరం సిద్ధంగా ఉంది' : 'Requirement ready', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF14213D))),
              const SizedBox(height: 4),
              Text(
                te ? 'ఇప్పుడు ASKODOX సరైన ${deal.partyB.role} వైపు మ్యాచ్‌లను చూస్తుంది.' : 'ASKODOX can now look for the matching side: ${deal.partyB.role}.',
                style: const TextStyle(color: Color(0xFF475467), height: 1.35),
              ),
            ]),
          ),
        ]),
      );

  Widget _historyHint(bool te) => InkWell(
        onTap: () => context.go('/watchlist'),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE5EAF2))),
          child: Row(children: [
            const Icon(Icons.history_rounded, color: Color(0xFF1769FF)),
            const SizedBox(width: 10),
            Expanded(child: Text(te ? 'ఈ అవసరం History లో కొనసాగించవచ్చు' : 'Continue this later from History', style: const TextStyle(fontWeight: FontWeight.w800))),
            const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          ]),
        ),
      );

  String _questionFor(UniversalDeal deal, bool te) {
    final field = deal.missingForMatch.isEmpty ? null : deal.missingForMatch.first;
    if (te) {
      return switch (field) {
        'subject' => 'మీకు ఖచ్చితంగా ఏమి కావాలి?',
        'location' => 'ఎక్కడ మ్యాచ్ కావాలి?',
        'timing' => 'ఎప్పుడు కావాలి?',
        'from' => 'ఎక్కడి నుంచి ప్రారంభం?',
        'to' => 'ఎక్కడికి వెళ్లాలి?',
        'skill' => 'ఏ పని లేదా స్కిల్ కావాలి?',
        _ => 'మిగిలిన వివరాన్ని చెప్పండి.',
      };
    }
    return switch (field) {
      'subject' => 'What exactly do you need or offer?',
      'location' => 'Where should ASKODOX find the match?',
      'timing' => 'When do you need this?',
      'from' => 'Where does it start from?',
      'to' => 'Where should it go to?',
      'skill' => 'What skill or work is required?',
      _ => 'Tell me the missing detail.',
    };
  }
}
