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

  String _tr(String en, String te, String hi, String or) => switch (_lang()) {
        'te' => te,
        'hi' => hi,
        'or' => or,
        _ => en,
      };

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(taskResult.message ?? (taskResult.success ? 'Done.' : 'Please try again.'))),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Something went wrong. Please try again.', 'ఏదో సమస్య వచ్చింది. మళ్లీ ప్రయత్నించండి.', 'कुछ गलत हुआ। फिर से कोशिश करें।', 'କିଛି ସମସ୍ୟା ହେଲା। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।'))),
      );
    });
  }

  Future<void> _setCapturedImage(Future<XFile?> Function() capture) async {
    try {
      final picked = await capture();
      if (!mounted || picked == null) return;
      setState(() => _attachment = picked);
    } catch (_) {}
  }

  Future<void> _pickImage() => _setCapturedImage(_capture.chooseGallery);
  Future<void> _takePhoto() => _setCapturedImage(_capture.captureCamera);

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(_tr('Add to your request', 'మీ అభ్యర్థనకు జోడించండి', 'अपनी रिक्वेस्ट में जोड़ें', 'ଆପଣଙ୍କ ଅନୁରୋଧରେ ଯୋଡନ୍ତୁ'), style: const TextStyle(fontWeight: FontWeight.w900))),
          ListTile(key: const Key('askodoxPlusCameraAction'), leading: const Icon(Icons.photo_camera_outlined), title: Text(_tr('Take a photo', 'ఫోటో తీయండి', 'फ़ोटो लें', 'ଫଟୋ ନିଅନ୍ତୁ')), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(key: const Key('askodoxPlusPhotosAction'), leading: const Icon(Icons.photo_library_outlined), title: Text(_tr('Choose a photo', 'ఫోటో ఎంచుకోండి', 'फ़ोटो चुनें', 'ଫଟୋ ବାଛନ୍ତୁ')), onTap: () => Navigator.pop(context, 'photo')),
          ListTile(key: const Key('askodoxPlusVoiceAction'), leading: const Icon(Icons.mic_none_rounded), title: Text(_tr('Use voice', 'వాయిస్ ఉపయోగించండి', 'वॉइस इस्तेमाल करें', 'ଭଏସ୍ ବ୍ୟବହାର କରନ୍ତୁ')), onTap: () => Navigator.pop(context, 'voice')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'camera') await _takePhoto();
    if (action == 'photo') await _pickImage();
    if (action == 'voice') context.go('/discover/voice');
  }

  Future<void> _pickLanguage() async {
    final settings = ref.read(appSettingsProvider);
    final selected = settings.locale?.languageCode ?? 'system';
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(children: [
            const ListTile(title: Text('ASKODOX Language', style: TextStyle(fontWeight: FontWeight.w900))),
            Expanded(
              child: ListView(children: [
                RadioListTile<String>(value: 'system', groupValue: selected, title: const Text('Auto / Device language'), onChanged: (v) => Navigator.pop(context, v)),
                for (final language in AskodoxLanguageCatalog.all)
                  RadioListTile<String>(value: language.code, groupValue: selected, title: Text(language.name), onChanged: (v) => Navigator.pop(context, v)),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'system') {
      ref.read(appSettingsProvider.notifier).useSystemLocale();
    } else {
      ref.read(appSettingsProvider.notifier).setLocale(Locale(choice));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final languageLabel = settings.locale == null ? 'Auto' : AskodoxLanguageCatalog.byCode(settings.locale!.languageCode).name;
    final te = _lang() == 'te';
    final hi = _lang() == 'hi';
    final odia = _lang() == 'or';
    String nav(String en, String tv, String hv, String ov) => te ? tv : hi ? hv : odia ? ov : en;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        title: const Text('ASKODOX', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
        actions: [TextButton(key: const Key('askodoxLanguageButton'), onPressed: _pickLanguage, child: Text(languageLabel))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Text(askodoxGreetingForHour(DateTime.now().hour, _lang()), style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 12),
            const Center(child: AskodoxOrb()),
            const SizedBox(height: 16),
            Container(
              key: const Key('askodoxAskField'),
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                IconButton(key: const Key('askodoxPlusButton'), onPressed: _taskBusy ? null : _showActions, icon: const Icon(Icons.add_rounded, color: _purple)),
                IconButton(key: const Key('askodoxMicButton'), onPressed: () => context.go('/discover/voice'), icon: const Icon(Icons.mic_none_rounded, color: _purple)),
                Expanded(child: TextField(controller: _controller, focusNode: _focusNode, textInputAction: TextInputAction.send, onSubmitted: (_) => _submit(), decoration: InputDecoration(hintText: _tr('Ask anything…', 'ఏదైనా అడగండి…', 'कुछ भी पूछें…', 'ଯେକୌଣସି କଥା ପଚାରନ୍ତୁ…'), border: InputBorder.none))),
                IconButton(key: const Key('askodoxImageButton'), onPressed: _pickImage, icon: const Icon(Icons.image_outlined, color: _muted)),
                _taskBusy
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(key: const Key('askodoxSendButton'), onPressed: _submit, icon: const Icon(Icons.arrow_upward_rounded, color: _purple)),
              ]),
            ),
            if (_attachment != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_attachment!.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 24),
            Text(_tr('In Progress', 'ప్రస్తుతం జరుగుతున్నవి', 'चल रहा है', 'ଚାଲିଛି'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text(_tr('ASKODOX is finding your best match', 'మీకు సరైన మ్యాచ్‌ను ASKODOX వెతుకుతోంది', 'ASKODOX आपका सही मैच ढूँढ रहा है', 'ASKODOX ଆପଣଙ୍କ ସର୍ବୋତ୍ତମ ମ୍ୟାଚ୍ ଖୋଜୁଛି')),
            const SizedBox(height: 28),
            Text(_tr('Continue your conversations', 'మీ సంభాషణలను కొనసాగించండి', 'अपनी बातचीत जारी रखें', 'ଆପଣଙ୍କ କଥୋପକଥନ ଜାରି ରଖନ୍ତୁ'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text(_tr('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ')),
            const SizedBox(height: 420),
            NavigationBar(
              selectedIndex: 1,
              onDestinationSelected: (i) {
                if (i == 0) context.go('/search');
                if (i == 2) context.go('/activity');
              },
              destinations: [
                NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), label: nav('Chats', 'చాట్స్', 'चैट्स', 'ଚାଟ୍ସ')),
                NavigationDestination(icon: const Icon(Icons.auto_awesome_rounded), label: nav('Ask', 'అడగండి', 'पूछें', 'ପଚାରନ୍ତୁ')),
                NavigationDestination(icon: const Icon(Icons.notifications_none_rounded), label: nav('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
