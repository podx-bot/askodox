import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/scheduled_task_coordinator.dart';
import '../../../services/vision_api_service.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../catalog/presentation/deal_prompt_policy.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../matching/presentation/universal_match_screen.dart';
import 'askodox_orb.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF6B7280);
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
  final _capture = MultimodalCaptureService();
  final _conversationStore = ConversationTurnStore();
  final List<_Turn> _turns = [];
  XFile? _attachment;

  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');

  bool get _isTe => ref.read(appSettingsProvider).locale?.languageCode == 'te';

  @override
  void initState() {
    super.initState();
    unawaited(_restoreTurns());
  }

  Future<void> _restoreTurns() async {
    final records = await _conversationStore.load();
    if (!mounted || records.isEmpty) return;
    setState(() => _turns.addAll(records.map(_Turn.fromRecord)));
  }

  void _persistTurns() {
    unawaited(_conversationStore.save(_turns.map((e) => e.record).toList(growable: false)));
  }

  void _syncLanguage(String text) {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    }
  }

  Future<void> _submit([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _syncLanguage(text);

    final taskResult = await const ScheduledTaskCoordinator().handle(text);
    if (!mounted) return;
    if (taskResult.handled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(taskResult.message ?? (taskResult.success ? 'Done.' : 'Please try again.'))),
      );
      if (taskResult.success) _controller.clear();
      return;
    }

    final notifier = ref.read(universalDealControllerProvider.notifier);
    final current = ref.read(universalDealControllerProvider);
    setState(() => _turns.add(_Turn.user(text)));

    if (current.deal == null) {
      notifier.start(text);
      final attachment = _attachment;
      if (attachment != null) {
        notifier.attachMedia(path: attachment.path, name: attachment.name);
        unawaited(_analyzeAttachment(attachment, text));
      }
    } else {
      notifier.answer(text);
    }

    _controller.clear();
    FocusScope.of(context).unfocus();
    final next = ref.read(universalDealControllerProvider);
    setState(() => _turns.add(_Turn.assistant(_assistantText(next))));
    _persistTurns();
    _scrollToBottom();
  }

  Future<void> _analyzeAttachment(XFile attachment, String text) async {
    final language = ref.read(appSettingsProvider).locale?.languageCode ?? 'en';
    final analysis = await const VisionApiService().analyze(
      image: attachment,
      userText: text,
      language: language,
    );
    if (!mounted) return;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    if (analysis != null) {
      notifier.mergeVisionAnalysis(analysis);
    } else {
      notifier.markVisionAnalysisFailed();
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _capture.chooseGallery();
      if (!mounted || picked == null) return;
      setState(() => _attachment = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isTe ? 'ఫోటో తెరవలేకపోయాం. మళ్లీ ప్రయత్నించండి.' : 'Could not open the photo. Please try again.')),
      );
    }
  }

  void _newChat() {
    ref.read(universalDealControllerProvider.notifier).reset();
    setState(() {
      _turns.clear();
      _attachment = null;
    });
    unawaited(_conversationStore.clear());
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _assistantText(UniversalDealSession session) {
    final deal = session.deal;
    final te = _isTe || (deal != null && _telugu.hasMatch(deal.rawText));
    if (deal == null) return te ? 'మీకు ఏమి కావాలి?' : 'What can I help you find?';
    if (session.completed) {
      return te
          ? 'సరే. ముఖ్యమైన వివరాలు వచ్చాయి. ఇప్పుడు మీకు సరైన స్థానిక మ్యాచ్‌లను చూపిస్తాను.'
          : 'Got it. I have the important details. I can now show the best local matches.';
    }
    return DealPromptPolicy.questionFor(
      deal: deal,
      field: deal.missingForMatch.firstOrNull,
      telugu: te,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(universalDealControllerProvider);
    final active = session.deal != null;
    final te = _isTe;

    return ColoredBox(
      color: const Color(0xFFF8FBFF),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: active ? _chat(session, te) : _home(te),
            ),
            _composer(te, active),
          ],
        ),
      ),
    );
  }

  Widget _home(bool te) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        _PromoCard(te: te),
        const SizedBox(height: 22),
        const Center(child: AskodoxVoiceOrb()),
        const SizedBox(height: 14),
        Text(
          te ? 'ఈ రోజు మీకు ఎలా సహాయం చేయగలను?' : 'How can I help you today?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink),
        ),
        const SizedBox(height: 6),
        Text(
          te
              ? 'షాపులు, సర్వీసులు, ప్రోడక్ట్స్, ఉద్యోగాలు, అపాయింట్‌మెంట్స్ — ఏ అవసరమైనా అడగండి.'
              : 'Ask anything — shops, services, products, jobs, appointments, or any local need.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickChip(label: te ? 'దగ్గరలో చికెన్' : 'Find chicken near me', onTap: () => _submit(te ? 'నాకు దగ్గరలో చికెన్ కావాలి' : 'I need chicken near me')),
            _QuickChip(label: te ? 'సర్వీస్ బుక్ చేయండి' : 'Book a service', onTap: () => _submit(te ? 'నాకు ఒక లోకల్ సర్వీస్ కావాలి' : 'I need a local service')),
            _QuickChip(label: te ? 'ఉద్యోగం వెతకండి' : 'Find a job', onTap: () => _submit(te ? 'నాకు ఉద్యోగం కావాలి' : 'I need a job')),
            _QuickChip(label: te ? 'ఈరోజు ఆఫర్లు' : "Today's offers", onTap: () => _submit(te ? 'నా దగ్గరలో ఈరోజు ఆఫర్లు చూపించు' : 'Show today offers near me')),
          ],
        ),
        const SizedBox(height: 22),
        _LiveActivityRow(te: te),
      ],
    );
  }

  Widget _chat(UniversalDealSession session, bool te) {
    final deal = session.deal!;
    final missing = deal.missingForMatch.firstOrNull;
    final replies = DealPromptPolicy.suggestionsFor(deal: deal, field: missing, telugu: te);

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        _ChatTopBar(te: te, onNew: _newChat),
        const SizedBox(height: 12),
        if (_turns.isEmpty) ...[
          _Bubble.assistant(_assistantText(session)),
        ] else ...[
          for (final turn in _turns) ...[
            turn.isUser ? _Bubble.user(turn.text) : _Bubble.assistant(turn.text),
            const SizedBox(height: 10),
          ],
        ],
        if (_attachment != null) ...[
          _AttachmentPreview(file: _attachment!),
          const SizedBox(height: 10),
        ],
        if (session.completed) ...[
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UniversalMatchScreen()),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0DAA5B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(te ? 'సరే, మంచి మ్యాచ్‌లు చూపించు' : 'Show the best local matches'),
          ),
        ] else if (replies.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: replies.map((value) => ActionChip(label: Text(value), onPressed: () => _submit(value))).toList(),
          ),
        ],
      ],
    );
  }

  Widget _composer(bool te, bool active) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 9, 12, 9 + MediaQuery.viewPaddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5EAF2))),
      ),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: () => context.go('/discover/voice'),
            style: IconButton.styleFrom(backgroundColor: _accent),
            icon: const Icon(Icons.mic_rounded, color: _ink),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: te ? 'టైప్ చేయండి లేదా మాట్లాడండి…' : 'Type or speak your request…',
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(onPressed: _pickImage, icon: const Icon(Icons.image_outlined, color: _ink)),
          IconButton.filled(
            onPressed: _submit,
            style: IconButton.styleFrom(backgroundColor: active ? _blue : _accent),
            icon: Icon(Icons.arrow_upward_rounded, color: active ? Colors.white : _ink),
          ),
        ],
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4C7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFE08A)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: _accent,
              child: Icon(Icons.local_offer_rounded, color: _ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(te ? 'లోకల్ ఆఫర్' : 'Local offer', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                const SizedBox(height: 3),
                Text(te ? 'మీ దగ్గరలోని తాజా డీల్స్‌ను ASKODOX కనుగొంటుంది.' : 'ASKODOX can surface relevant nearby deals.', style: const TextStyle(color: _muted)),
              ]),
            ),
          ],
        ),
      );
}

class _LiveActivityRow extends StatelessWidget {
  const _LiveActivityRow({required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(te ? 'ASKODOX లో ఇప్పుడు' : 'ASKODOX Live', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 10),
          SizedBox(
            height: 116,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ActivityCard(icon: Icons.storefront_rounded, title: te ? 'కొత్త బిజినెస్' : 'New businesses', subtitle: te ? 'మీ దగ్గరలో' : 'Nearby'),
                _ActivityCard(icon: Icons.groups_rounded, title: te ? 'కమ్యూనిటీ' : 'Community', subtitle: te ? 'లోకల్ యాక్టివిటీ' : 'Local activity'),
                _ActivityCard(icon: Icons.sell_rounded, title: te ? 'డీల్స్ & ఆఫర్లు' : 'Deals & Offers', subtitle: te ? 'ప్రస్తుత ఆఫర్లు' : 'Current offers'),
                _ActivityCard(icon: Icons.home_repair_service_rounded, title: te ? 'కొత్త సర్వీసులు' : 'New services', subtitle: te ? 'ఇప్పుడే జాయిన్' : 'Recently joined'),
              ],
            ),
          ),
        ],
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3E8F2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _blue),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
      );
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: onTap,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE0E6F0)),
      );
}

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({required this.te, required this.onNew});
  final bool te;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE9F8EE),
            child: Icon(Icons.smart_toy_rounded, color: Color(0xFF0DAA5B)),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(te ? 'ASKODOX సంభాషణ' : 'ASKODOX conversation', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink))),
          IconButton(onPressed: onNew, tooltip: te ? 'కొత్త చాట్' : 'New chat', icon: const Icon(Icons.add_circle_outline_rounded, color: _blue)),
        ],
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble._(this.text, this.user);
  factory _Bubble.user(String text) => _Bubble._(text, true);
  factory _Bubble.assistant(String text) => _Bubble._(text, false);
  final String text;
  final bool user;

  @override
  Widget build(BuildContext context) => Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: user ? _blue : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: user ? null : Border.all(color: const Color(0xFFE0E6F0)),
          ),
          child: Text(text, style: TextStyle(color: user ? Colors.white : _ink, height: 1.4, fontWeight: FontWeight.w600)),
        ),
      );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.file});
  final XFile file;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 180,
            height: 120,
            child: Image.file(File(file.path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE9EDF5), child: Icon(Icons.image_not_supported_outlined))),
          ),
        ),
      );
}

class _Turn {
  const _Turn(this.text, this.isUser);
  factory _Turn.user(String text) => _Turn(text, true);
  factory _Turn.assistant(String text) => _Turn(text, false);
  factory _Turn.fromRecord(ConversationTurnRecord record) => _Turn(record.text, record.isUser);
  final String text;
  final bool isUser;
  ConversationTurnRecord get record => ConversationTurnRecord(text: text, isUser: isUser);
}
