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

  void _useSuggestedAnswer(String value) {
    _answer.text = value;
    _answer.selection = TextSelection.collapsed(offset: value.length);
    _focusNode.requestFocus();
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
            tooltip: te ? 'కొత్త అవసరం' : 'New request',
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
            te ? 'మీకు కావాల్సింది సహజంగా చెప్పండి. ASKODOX అవసరమైన వివరాలను ఒక్కొక్కటిగా తీసుకుంటుంది.' : 'Say what you need naturally. ASKODOX will collect only the details needed.',
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

  Widget _conversation(UniversalDealSession session, UniversalDeal deal, bool te) {
    final missing = deal.missingForMatch.isEmpty ? null : deal.missingForMatch.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _flowCard(
          number: 1,
          tint: const Color(0xFFEAF1FF),
          numberColor: const Color(0xFF1769FF),
          title: te ? 'మీరు అడిగింది' : 'You asked',
          icon: Icons.person_rounded,
          child: _messageBubble(deal.rawText, const Color(0xFFF4F7FF)),
        ),
        const SizedBox(height: 12),
        _flowCard(
          number: 2,
          tint: const Color(0xFFEAFBF0),
          numberColor: const Color(0xFF10A53A),
          title: te ? 'ఇప్పటివరకు గుర్తించిన వివరాలు' : 'Details captured so far',
          icon: Icons.location_on_outlined,
          child: _capturedDetails(deal, te),
        ),
        const SizedBox(height: 12),
        _flowCard(
          number: 3,
          tint: const Color(0xFFF3EEFF),
          numberColor: const Color(0xFF6A3FD6),
          title: te ? 'ASKODOX సమాధానం' : 'ASKODOX reply',
          icon: Icons.smart_toy_rounded,
          child: _assistantReply(session, deal, te),
        ),
        if (!session.completed) ...[
          const SizedBox(height: 12),
          _flowCard(
            number: 4,
            tint: const Color(0xFFFFF4E8),
            numberColor: const Color(0xFFF57C00),
            title: te ? 'ఇంకా కావాల్సిన వివరము' : 'One detail still needed',
            icon: Icons.help_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _questionFor(deal, te),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF14213D), height: 1.35),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestionsFor(missing, te)
                      .map(
                        (value) => ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 17),
                          label: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () => _useSuggestedAnswer(value),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _flowCard(
            number: 5,
            tint: const Color(0xFFE9FAFA),
            numberColor: const Color(0xFF0F9C9C),
            title: te ? 'మీ సమాధానం ఇవ్వండి' : 'Send your reply',
            icon: Icons.mic_none_rounded,
            child: _answerBox(te),
          ),
        ] else ...[
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
            label: Text(te ? 'మ్యాచ్‌లు కనుగొను' : 'Find my best matches', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
        const SizedBox(height: 18),
        _historyHint(te),
      ],
    );
  }

  Widget _flowCard({
    required int number,
    required Color tint,
    required Color numberColor,
    required String title,
    required IconData icon,
    required Widget child,
  }) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: numberColor.withValues(alpha: .18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: numberColor,
                  child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: numberColor))),
                Icon(icon, color: numberColor),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _messageBubble(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF14213D), height: 1.35)),
      );

  Widget _capturedDetails(UniversalDeal deal, bool te) {
    final rows = <String>[
      if (deal.subject != null && deal.subject!.trim().isNotEmpty) '${te ? 'అవసరం' : 'Need'}: ${deal.subject}',
      if (_lastAnswer != null) '${te ? 'తాజా వివరము' : 'Latest detail'}: $_lastAnswer',
      if (deal.quantity != null) '${te ? 'పరిమాణం' : 'Quantity'}: ${deal.quantity} ${deal.unit ?? ''}',
      if (deal.price != null) '${te ? 'బడ్జెట్' : 'Budget'}: ₹${deal.price}',
      if (deal.location.isKnown) '${te ? 'స్థలం' : 'Location'}: ${deal.location.label ?? '${deal.location.latitude}, ${deal.location.longitude}'}',
      if (deal.timing != null) '${te ? 'సమయం' : 'Timing'}: ${deal.timing}',
    ];

    if (rows.isEmpty) {
      return Text(te ? 'ఇంకా వివరాలు సేకరిస్తున్నాను.' : 'Still collecting details.', style: const TextStyle(color: Color(0xFF667085)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle_rounded, size: 17, color: Color(0xFF10A53A)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(row, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF344054)))),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _assistantReply(UniversalDealSession session, UniversalDeal deal, bool te) {
    final message = session.completed
        ? (te ? 'సరే! అవసరమైన వివరాలు వచ్చాయి. ఇప్పుడు సరైన మ్యాచ్‌లను వెతుకుతాను.' : 'Great. I have the required details and can now find the best matches.')
        : (te ? 'సరే, అర్థమైంది. ఇప్పుడు ఒక చిన్న వివరమే కావాలి.' : 'Got it. I only need one more detail.');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(Icons.smart_toy_rounded, color: Color(0xFF6A3FD6)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF14213D), height: 1.4)),
          ),
        ),
      ],
    );
  }

  List<String> _suggestionsFor(String? field, bool te) {
    return switch (field) {
      'location' => te ? ['నా ప్రస్తుత స్థానం', 'వుయ్యూరు'] : ['My current area', 'Vuyyuru'],
      'timing' => te ? ['ఇప్పుడే', 'ఈ రోజు', 'రేపు'] : ['Now', 'Today', 'Tomorrow'],
      'quantity' => te ? ['1 kg', '2 kg', '5 kg'] : ['1 kg', '2 kg', '5 kg'],
      _ => const <String>[],
    };
  }

  Widget _answerBox(bool te) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 7, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF14213D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF6F8FFF), width: 1.3),
        ),
        child: TextField(
          key: const Key('askodoxClarificationField'),
          controller: _answer,
          focusNode: _focusNode,
          textInputAction: TextInputAction.send,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          onSubmitted: (_) => _sendAnswer(),
          decoration: InputDecoration(
            hintText: te ? 'మీ సమాధానం టైప్ చేయండి…' : 'Type your reply…',
            hintStyle: const TextStyle(color: Color(0xFFAAB5CF)),
            prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6F8FFF)),
            suffixIcon: IconButton(
              tooltip: te ? 'పంపండి' : 'Send',
              onPressed: _sendAnswer,
              icon: const CircleAvatar(backgroundColor: Color(0xFF6A3FD6), child: Icon(Icons.arrow_upward_rounded, color: Colors.white)),
            ),
            border: InputBorder.none,
          ),
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
            Expanded(child: Text(te ? 'ఈ అవసరాన్ని History లో తర్వాత కూడా కొనసాగించవచ్చు' : 'Continue this later from History', style: const TextStyle(fontWeight: FontWeight.w800))),
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
