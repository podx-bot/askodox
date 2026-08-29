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

  String? _lastAnswer;

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
    setState(() => _lastAnswer = text);
    ref.read(universalDealControllerProvider.notifier).answer(text);
    _answer.clear();
    FocusScope.of(context).unfocus();
  }

  void _start(String prompt) {
    _syncLanguage(prompt);
    setState(() => _lastAnswer = null);
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
              setState(() => _lastAnswer = null);
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
            te ? 'మీకు కావాల్సింది సహజంగా చెప్పండి. ASKODOX ఒక్కో అవసరమైన వివరాన్ని మాత్రమే అడుగుతుంది.' : 'Say what you need naturally. ASKODOX asks only for the details that are still needed.',
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
          _sectionLabel(te ? 'మీరు అడిగింది' : 'YOU ASKED'),
          const SizedBox(height: 7),
          _userBubble(deal.rawText),
          if (_lastAnswer != null) ...[
            const SizedBox(height: 10),
            _sectionLabel(te ? 'మీరు ఇచ్చిన తాజా వివరము' : 'YOUR LATEST DETAIL'),
            const SizedBox(height: 7),
            _userBubble(_lastAnswer!),
          ],
          const SizedBox(height: 18),
          _sectionLabel(te ? 'ASKODOX సమాధానం' : 'ASKODOX REPLY'),
          const SizedBox(height: 8),
          if (!session.completed)
            _replyCard(
              title: te ? 'అర్థం చేసుకున్నాను' : 'Got it',
              message: _questionFor(deal, te),
              helper: te ? 'ఇంకో వివరమే కావాలి. క్రింద సమాధానం ఇవ్వండి.' : 'I only need one more detail. Reply below.',
            )
          else
            _replyCard(
              title: te ? 'అన్ని అవసరమైన వివరాలు వచ్చాయి' : 'I have everything I need',
              message: te ? 'ఇప్పుడు మీకు సరిపోయే మ్యాచ్‌లను చూడవచ్చు.' : 'You can now check the best available matches.',
              helper: te ? 'కింద ఉన్న “మ్యాచ్‌లు కనుగొను” బటన్ నొక్కండి.' : 'Tap “Find my best matches” below.',
              success: true,
            ),
          const SizedBox(height: 14),
          _understoodCard(deal, te),
          const SizedBox(height: 14),
          if (!session.completed) ...[
            _answerBox(te),
          ] else ...[
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
              label: Text(te ? 'వివరాలు మార్చాలి' : 'Change details'),
            ),
          ],
          const SizedBox(height: 24),
          _historyHint(te),
        ],
      );

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
          color: Color(0xFF667085),
        ),
      );

  Widget _userBubble(String text) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Text(text, style: const TextStyle(color: Color(0xFF14213D), fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _replyCard({required String title, required String message, required String helper, bool success = false}) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: success ? const Color(0xFFEAFBF0) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: success ? const Color(0xFFA9E5BB) : const Color(0xFFCFE0FF), width: 1.4),
          boxShadow: const [
            BoxShadow(color: Color(0x0D14213D), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: success ? const Color(0xFFDDF7E5) : const Color(0xFFE8F8ED),
              child: Icon(success ? Icons.check_rounded : Icons.smart_toy_rounded, color: const Color(0xFF10A53A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                  const SizedBox(height: 8),
                  Text(message, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35, color: Color(0xFF14213D))),
                  const SizedBox(height: 8),
                  Text(helper, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF667085))),
                ],
              ),
            ),
          ],
        ),
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
                te ? 'ఇప్పటివరకు గుర్తించిన వివరాలు' : 'Details captured so far',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF14213D)),
              ),
            ),
          ]),
          const SizedBox(height: 13),
          if (rows.isEmpty)
            Text(te ? 'ఇంకా వివరాలు సేకరిస్తున్నాను.' : 'Still collecting the details.', style: const TextStyle(color: Color(0xFF667085)))
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF10A53A))),
                  const SizedBox(width: 9),
                  Expanded(child: Text(row, style: const TextStyle(fontSize: 15, color: Color(0xFF344054)))),
                ]),
              ),
        ],
      ),
    );
  }

  Widget _answerBox(bool te) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF14213D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF6F8FFF), width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(te ? 'మీ సమాధానం' : 'YOUR REPLY', style: const TextStyle(color: Color(0xFFB8C7E8), fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: .6)),
            TextField(
              key: const Key('askodoxClarificationField'),
              controller: _answer,
              focusNode: _focusNode,
              textInputAction: TextInputAction.send,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              onSubmitted: (_) => _sendAnswer(),
              decoration: InputDecoration(
                hintText: te ? 'ఉదా: వుయ్యూరు' : 'Example: Vuyyuru',
                hintStyle: const TextStyle(color: Color(0xFFAAB5CF)),
                suffixIcon: IconButton(
                  tooltip: te ? 'పంపండి' : 'Send',
                  onPressed: _sendAnswer,
                  icon: const CircleAvatar(
                    backgroundColor: Color(0xFF1769FF),
                    child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
                  ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: 12),
              ),
            ),
          ],
        ),
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
        'location' => 'ఏ ప్రాంతంలో కావాలి?',
        'timing' => 'ఎప్పుడు కావాలి?',
        'from' => 'ఎక్కడి నుంచి ప్రారంభం?',
        'to' => 'ఎక్కడికి వెళ్లాలి?',
        'skill' => 'ఏ పని లేదా స్కిల్ కావాలి?',
        _ => 'మిగిలిన వివరాన్ని చెప్పండి.',
      };
    }
    return switch (field) {
      'subject' => 'What exactly do you need or offer?',
      'location' => 'Which area should I search in?',
      'timing' => 'When do you need this?',
      'from' => 'Where does it start from?',
      'to' => 'Where should it go to?',
      'skill' => 'What skill or work is required?',
      _ => 'Tell me the missing detail.',
    };
  }
}
