import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/localization/askodox_language_catalog.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/scheduled_task_coordinator.dart';
import '../../../services/vision_api_service.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import 'askodox_orb.dart';

const _ink = Color(0xFF111936);
const _muted = Color(0xFF6B7280);
const _purple = Color(0xFF7A4DFF);
const _soft = Color(0xFFF7F8FF);

String askodoxGreetingForHour(int hour, String languageCode) {
  final normalizedHour = hour.clamp(0, 23);
  final period = normalizedHour < 5
      ? 'night'
      : normalizedHour < 12
          ? 'morning'
          : normalizedHour < 17
              ? 'afternoon'
              : normalizedHour < 21
                  ? 'evening'
                  : 'night';

  const greetings = <String, Map<String, String>>{
    'en': {'morning': 'Good morning 👋', 'afternoon': 'Good afternoon 👋', 'evening': 'Good evening 👋', 'night': 'Good night 👋'},
    'te': {'morning': 'శుభోదయం 👋', 'afternoon': 'శుభ మధ్యాహ్నం 👋', 'evening': 'శుభ సాయంత్రం 👋', 'night': 'శుభ రాత్రి 👋'},
    'hi': {'morning': 'सुप्रभात 👋', 'afternoon': 'शुभ दोपहर 👋', 'evening': 'शुभ संध्या 👋', 'night': 'शुभ रात्रि 👋'},
    'or': {'morning': 'ଶୁଭ ସକାଳ 👋', 'afternoon': 'ଶୁଭ ଅପରାହ୍ନ 👋', 'evening': 'ଶୁଭ ସନ୍ଧ୍ୟା 👋', 'night': 'ଶୁଭ ରାତ୍ରି 👋'},
  };
  final language = greetings.containsKey(languageCode) ? languageCode : 'en';
  return greetings[language]![period]!;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _capture = MultimodalCaptureService();
  XFile? _attachment;
  bool _taskBusy = false;

  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');
  static final _hindi = RegExp(r'[\u0900-\u097F]');
  static final _odia = RegExp(r'[\u0B00-\u0B7F]');

  String _lang() {
    final manual = ref.read(appSettingsProvider).locale?.languageCode;
    if (manual != null) return AskodoxLanguageCatalog.normalize(manual);
    return AskodoxLanguageCatalog.normalize(Localizations.localeOf(context).languageCode);
  }

  String _tr(String en, String te, String hi, String or) => switch (_lang()) {'te' => te, 'hi' => hi, 'or' => or, _ => en};

  Future<void> _startFlow(String text) async {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    } else if (_hindi.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('hi'));
    } else if (_odia.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('or'));
    }

    final taskResult = await const ScheduledTaskCoordinator().handle(text);
    if (!mounted) return;
    if (taskResult.handled) {
      setState(() => _taskBusy = false);
      final message = taskResult.message ?? (taskResult.success ? 'Done.' : 'Please try again.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      if (taskResult.success) {
        _controller.clear();
        _focusNode.requestFocus();
      }
      return;
    }

    final deal = ref.read(universalDealControllerProvider.notifier);
    deal.start(text);
    final attachment = _attachment;
    if (attachment != null) deal.attachMedia(path: attachment.path, name: attachment.name);
    final language = _lang();
    setState(() => _taskBusy = false);
    context.go('/search');

    if (attachment != null) {
      final analysis = await const VisionApiService().analyze(image: attachment, userText: text, language: language);
      if (analysis != null) {
        deal.mergeVisionAnalysis(analysis);
      } else {
        deal.markVisionAnalysisFailed();
      }
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return _focusNode.requestFocus();
    if (_taskBusy) return;
    setState(() => _taskBusy = true);
    _startFlow(text).catchError((_) {
      if (!mounted) return;
      setState(() => _taskBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Something went wrong. Please try again.', 'ఏదో సమస్య వచ్చింది. మళ్లీ ప్రయత్నించండి.', 'कुछ गलत हुआ। फिर से कोशिश करें।', 'କିଛି ସମସ୍ୟା ହେଲା। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।'))));
    });
  }

  Future<void> _setCapturedImage(Future<XFile?> Function() capture) async {
    try {
      final picked = await capture();
      if (!mounted || picked == null) return;
      setState(() => _attachment = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Could not open the camera or photos. Please try again.', 'కెమెరా లేదా ఫోటోలు తెరవలేకపోయాం. మళ్లీ ప్రయత్నించండి.', 'कैमरा या फ़ोटो नहीं खुल सके। फिर से कोशिश करें।', 'କ୍ୟାମେରା କିମ୍ବା ଫଟୋ ଖୋଲିହେଲା ନାହିଁ। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।'))));
    }
  }

  Future<void> _pickImage() => _setCapturedImage(_capture.chooseGallery);
  Future<void> _takePhoto() => _setCapturedImage(_capture.captureCamera);

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFF0ECFF), child: Icon(Icons.add_rounded, color: _purple)), title: Text(_tr('Add to your request', 'మీ అభ్యర్థనకు జోడించండి', 'अपनी रिक्वेस्ट में जोड़ें', 'ଆପଣଙ୍କ ଅନୁରୋଧରେ ଯୋଡନ୍ତୁ'), style: const TextStyle(fontWeight: FontWeight.w900, color: _ink))),
        ListTile(key: const Key('askodoxPlusCameraAction'), leading: const Icon(Icons.photo_camera_outlined, color: _purple), title: Text(_tr('Take a photo', 'ఫోటో తీయండి', 'फ़ोटो लें', 'ଫଟୋ ନିଅନ୍ତୁ')), onTap: () => Navigator.pop(context, 'camera')),
        ListTile(key: const Key('askodoxPlusGalleryAction'), leading: const Icon(Icons.photo_library_outlined, color: _purple), title: Text(_tr('Choose a photo', 'ఫోటో ఎంచుకోండి', 'फ़ोटो चुनें', 'ଫଟୋ ବାଛନ୍ତୁ')), onTap: () => Navigator.pop(context, 'gallery')),
      ])),
    );
    if (!mounted) return;
    if (action == 'camera') await _takePhoto();
    if (action == 'gallery') await _pickImage();
  }

  @override
  void dispose() { _controller.dispose(); _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final lang = _lang();
    final greeting = askodoxGreetingForHour(DateTime.now().hour, lang);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 20), child: Column(children: [
        Row(children: [const AskodoxOrb(size: 48), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: const TextStyle(fontSize: 14, color: _muted, fontWeight: FontWeight.w700)), const Text('ASKODOX', style: TextStyle(fontSize: 22, color: _ink, fontWeight: FontWeight.w900))]))]),
        const Spacer(),
        Text(_tr('What can I help you with?', 'నేను మీకు ఏ విషయంలో సహాయం చేయాలి?', 'मैं आपकी किस चीज़ में मदद करूँ?', 'ମୁଁ ଆପଣଙ୍କୁ କେଉଁଥିରେ ସାହାଯ୍ୟ କରିପାରିବି?'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 12),
        Text(_tr('Ask naturally — local needs, services, jobs, reminders and more.', 'సహజంగా అడగండి — లోకల్ అవసరాలు, సర్వీసులు, ఉద్యోగాలు, రిమైండర్లు ఇంకా మరెన్నో.', 'स्वाभाविक रूप से पूछें — लोकल जरूरतें, सेवाएँ, नौकरियाँ, रिमाइंडर और भी बहुत कुछ।', 'ସ୍ୱାଭାବିକ ଭାବେ ପଚାରନ୍ତୁ — ଲୋକାଲ ଆବଶ୍ୟକତା, ସେବା, ଚାକିରି, ରିମାଇଣ୍ଡର ଏବଂ ଅଧିକ।'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: _muted)),
        const Spacer(),
        if (_attachment != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [const Icon(Icons.image_outlined, color: _purple), const SizedBox(width: 8), Expanded(child: Text(_attachment!.name, overflow: TextOverflow.ellipsis)), IconButton(onPressed: () => setState(() => _attachment = null), icon: const Icon(Icons.close))])),
        Container(decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(24)), padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(key: const Key('askodoxPlusButton'), onPressed: _taskBusy ? null : _showActions, icon: const Icon(Icons.add_circle_outline_rounded, color: _purple)),
          Expanded(child: TextField(key: const Key('askodoxHomeInput'), controller: _controller, focusNode: _focusNode, minLines: 1, maxLines: 5, textInputAction: TextInputAction.send, onSubmitted: (_) => _submit(), decoration: InputDecoration(hintText: _tr('Ask ASKODOX...', 'ASKODOXని అడగండి...', 'ASKODOX से पूछें...', 'ASKODOXକୁ ପଚାରନ୍ତୁ...'), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)))),
          _taskBusy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))) : IconButton(key: const Key('askodoxSendButton'), onPressed: _submit, icon: const Icon(Icons.arrow_upward_rounded, color: _purple)),
        ])),
      ]))),
    );
  }
}
