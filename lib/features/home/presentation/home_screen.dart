import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/localization/askodox_language_catalog.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/scheduled_task_coordinator.dart';
import '../../../services/vision_api_service.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../matching/data/demo_natural_match_catalog.dart';
import '../../matching/data/universal_match_repository.dart';
import 'askodox_orb.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF64748B);
const _blue = Color(0xFF1677FF);
const _green = Color(0xFF14A83B);
const _soft = Color(0xFFF4F8FF);
const _yellow = Color(0xFFFFC928);

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
    'en': {
      'morning': 'Good morning 👋',
      'afternoon': 'Good afternoon 👋',
      'evening': 'Good evening 👋',
      'night': 'Good night 👋',
    },
    'te': {
      'morning': 'శుభోదయం 👋',
      'afternoon': 'శుభ మధ్యాహ్నం 👋',
      'evening': 'శుభ సాయంత్రం 👋',
      'night': 'శుభ రాత్రి 👋',
    },
    'hi': {
      'morning': 'सुप्रभात 👋',
      'afternoon': 'शुभ दोपहर 👋',
      'evening': 'शुभ संध्या 👋',
      'night': 'शुभ रात्रि 👋',
    },
    'or': {
      'morning': 'ଶୁଭ ସକାଳ 👋',
      'afternoon': 'ଶୁଭ ଅପରାହ୍ନ 👋',
      'evening': 'ଶୁଭ ସନ୍ଧ୍ୟା 👋',
      'night': 'ଶୁଭ ରାତ୍ରି 👋',
    },
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
  static const _deviceChannel = MethodChannel('com.askodox.app/device');
  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');
  static final _hindi = RegExp(r'[\u0900-\u097F]');
  static final _odia = RegExp(r'[\u0B00-\u0B7F]');

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _capture = MultimodalCaptureService();
  final _scrollController = ScrollController();

  XFile? _attachment;
  UniversalMatchResult? _matchResult;
  bool _matching = false;
  String? _matchError;
  String? _lastUserMessage;
  String? _lastAssistantMessage;

  String _lang() {
    final manual = ref.read(appSettingsProvider).locale?.languageCode;
    if (manual != null) return AskodoxLanguageCatalog.normalize(manual);
    final device = Localizations.localeOf(context).languageCode;
    return AskodoxLanguageCatalog.normalize(device);
  }

  String _tr(String en, String te, String hi, String or) => switch (_lang()) {
        'te' => te,
        'hi' => hi,
        'or' => or,
        _ => en,
      };

  void _autoLanguage(String text) {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    } else if (_hindi.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('hi'));
    } else if (_odia.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('or'));
    }
  }

  Future<void> _startFlow(String text, {String source = 'text'}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    _autoLanguage(value);

    final taskResult = await const ScheduledTaskCoordinator().handle(value);
    if (!mounted) return;
    if (taskResult.handled) {
      setState(() {
        _lastUserMessage = value;
        _lastAssistantMessage = taskResult.message ??
            (taskResult.success ? 'Done.' : 'Please try again.');
      });
      if (taskResult.success) _controller.clear();
      return;
    }

    final dealController = ref.read(universalDealControllerProvider.notifier);
    dealController.start(value);

    final attachment = _attachment;
    if (attachment != null) {
      dealController.attachMedia(path: attachment.path, name: attachment.name);
      final analysis = await const VisionApiService().analyze(
        image: attachment,
        userText: value,
        language: _lang(),
      );
      if (!mounted) return;
      if (analysis != null) {
        dealController.mergeVisionAnalysis(analysis);
      } else {
        dealController.markVisionAnalysisFailed();
      }
    }

    final session = ref.read(universalDealControllerProvider);
    final sourceLabel = source == 'voice'
        ? _tr('Voice', 'వాయిస్', 'वॉइस', 'ଭଏସ୍')
        : source == 'image'
            ? _tr('Photo/OCR', 'ఫోటో/OCR', 'फ़ोटो/OCR', 'ଫଟୋ/OCR')
            : _tr('You', 'మీరు', 'आप', 'ଆପଣ');

    setState(() {
      _lastUserMessage = '$sourceLabel: $value';
      _lastAssistantMessage = session.completed
          ? _tr(
              'I kept this in the same active request. I can now show matches below.',
              'ఇదే active requestలో కొనసాగించాను. కింద matches చూపిస్తున్నాను.',
              'इसी active request में जारी रखा है। नीचे matches दिखा रहा हूँ।',
              'ଏହି active request ରେ ଜାରି ରଖିଛି। ତଳେ matches ଦେଖାଉଛି।',
            )
          : (session.lastQuestion ??
              _tr(
                'Tell me the next missing detail and I will keep it in the same request.',
                'మిగిలిన వివరాన్ని చెప్పండి; ఇదే requestలో కొనసాగిస్తాను.',
                'अगली ज़रूरी जानकारी बताइए; इसी request में जारी रखूँगा।',
                'ପରବର୍ତ୍ତୀ ଆବଶ୍ୟକ ତଥ୍ୟ କହନ୍ତୁ; ଏହି request ରେ ଜାରି ରଖିବି।',
              ));
      _attachment = null;
      _matchResult = null;
      _matchError = null;
      _controller.clear();
    });

    if (session.completed) {
      await _loadMatches();
    } else {
      _scrollToConversation();
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    _startFlow(text);
  }

  Future<void> _startVoice() async {
    try {
      final spoken = await _deviceChannel.invokeMethod<String>(
        'startVoiceSearch',
        <String, Object?>{'languageCode': _lang()},
      );
      if (!mounted) return;
      final text = spoken?.trim() ?? '';
      if (text.isEmpty) return;
      await _startFlow(text, source: 'voice');
      try {
        await _deviceChannel.invokeMethod<bool>('speakAcknowledgement');
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'Voice could not start. Check microphone permission and try again.',
            'వాయిస్ ప్రారంభం కాలేదు. Microphone permission చూసి మళ్లీ ప్రయత్నించండి.',
            'वॉइस शुरू नहीं हुआ। Microphone permission जाँचकर फिर कोशिश करें।',
            'ଭଏସ୍ ଆରମ୍ଭ ହେଲା ନାହିଁ। Microphone permission ଯାଞ୍ଚ କରି ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
          )),
        ),
      );
    }
  }

  Future<void> _pickImage({bool camera = false}) async {
    try {
      final picked = camera
          ? await _capture.captureCamera()
          : await _capture.chooseGallery();
      if (!mounted || picked == null) return;

      final activeDeal = ref.read(universalDealControllerProvider).deal;
      if (activeDeal == null) {
        setState(() => _attachment = picked);
        _focusNode.requestFocus();
        return;
      }

      final controller = ref.read(universalDealControllerProvider.notifier);
      controller.attachMedia(path: picked.path, name: picked.name);
      final analysis = await const VisionApiService().analyze(
        image: picked,
        userText: activeDeal.rawText,
        language: _lang(),
      );
      if (!mounted) return;
      if (analysis != null) {
        controller.mergeVisionAnalysis(analysis);
      } else {
        controller.markVisionAnalysisFailed();
      }

      final session = ref.read(universalDealControllerProvider);
      setState(() {
        _lastUserMessage = _tr(
          'Photo/OCR added to this request',
          'ఈ requestకి Photo/OCR జోడించాను',
          'इस request में Photo/OCR जोड़ा',
          'ଏହି request ରେ Photo/OCR ଯୋଡାଗଲା',
        );
        _lastAssistantMessage = _tr(
          'I kept the photo in the same active deal. Any detected details are merged here.',
          'ఫోటోను ఇదే active dealలో ఉంచాను. గుర్తించిన వివరాలు ఇక్కడే merge అయ్యాయి.',
          'फ़ोटो इसी active deal में रखा है। पहचानी गई जानकारी यहीं merge हुई है।',
          'ଫଟୋଟି ଏହି active deal ରେ ରହିଛି। ଚିହ୍ନଟ ତଥ୍ୟ ଏଠି merge ହୋଇଛି।',
        );
      });
      if (session.completed) await _loadMatches();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'Could not open or analyze the photo. Please try again.',
            'ఫోటో తెరవడం లేదా analyze చేయడం కాలేదు. మళ్లీ ప్రయత్నించండి.',
            'फ़ोटो खोल या analyze नहीं कर सके। फिर कोशिश करें।',
            'ଫଟୋ ଖୋଲିବା କିମ୍ବା analyze କରିହେଲା ନାହିଁ। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
          )),
        ),
      );
    }
  }

  Future<void> _loadMatches() async {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null) return;

    if (!deal.readyToMatch) {
      setState(() {
        _matchError = ref.read(universalDealControllerProvider).lastQuestion;
      });
      return;
    }

    setState(() {
      _matching = true;
      _matchError = null;
    });

    try {
      final liveResult =
          await ref.read(universalMatchRepositoryProvider).createAndMatch(deal);
      if (!mounted) return;
      if (liveResult.matches.isNotEmpty) {
        setState(() => _matchResult = liveResult);
      } else {
        _useDemoMatches(deal);
      }
    } catch (error) {
      if (!mounted) return;
      _useDemoMatches(deal, liveError: error.toString());
    } finally {
      if (mounted) {
        setState(() => _matching = false);
        _scrollToConversation();
      }
    }
  }

  void _useDemoMatches(UniversalDeal deal, {String? liveError}) {
    final demo = DemoNaturalMatchCatalog.forDeal(deal, enabled: true);
    setState(() {
      _matchResult = UniversalMatchResult(
        dealId: 'local-demo-${DateTime.now().millisecondsSinceEpoch}',
        matches: demo,
      );
      _matchError = liveError == null
          ? _tr(
              'No live seller returned yet, so sandbox demo matches are shown for this test.',
              'Live seller ఇంకా రాలేదు కాబట్టి ఈ test కోసం sandbox demo matches చూపిస్తున్నాను.',
              'Live seller अभी नहीं मिला, इसलिए इस test के लिए sandbox demo matches दिख रहे हैं।',
              'Live seller ଏଯାଏଁ ମିଳିନାହିଁ, ତେଣୁ test ପାଇଁ sandbox demo matches ଦେଖାଯାଉଛି।',
            )
          : _tr(
              'Live matching is unavailable right now; sandbox demo matches are shown so the end-to-end UI can be tested.',
              'Live matching ప్రస్తుతం unavailable. End-to-end UI test కోసం sandbox demo matches చూపిస్తున్నాను.',
              'Live matching अभी unavailable है। End-to-end UI test के लिए sandbox demo matches दिख रहे हैं।',
              'Live matching ବର୍ତ୍ତମାନ unavailable। End-to-end UI test ପାଇଁ sandbox demo matches ଦେଖାଯାଉଛି।',
            );
    });
  }

  void _scrollToConversation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                _tr('Add to your request', 'మీ requestకి జోడించండి',
                    'अपनी request में जोड़ें', 'ଆପଣଙ୍କ request ରେ ଯୋଡନ୍ତୁ'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            ListTile(
              key: const Key('askodoxPlusCameraAction'),
              leading: const Icon(Icons.photo_camera_outlined, color: _blue),
              title: Text(_tr('Take a photo', 'ఫోటో తీయండి', 'फ़ोटो लें', 'ଫଟୋ ନିଅନ୍ତୁ')),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              key: const Key('askodoxPlusPhotosAction'),
              leading: const Icon(Icons.photo_library_outlined, color: _blue),
              title: Text(_tr('Choose a photo', 'ఫోటో ఎంచుకోండి', 'फ़ोटो चुनें', 'ଫଟୋ ବାଛନ୍ତୁ')),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              key: const Key('askodoxPlusVoiceAction'),
              leading: const Icon(Icons.mic_none_rounded, color: _blue),
              title: Text(_tr('Use voice', 'వాయిస్ ఉపయోగించండి', 'वॉइस इस्तेमाल करें', 'ଭଏସ୍ ବ୍ୟବହାର କରନ୍ତୁ')),
              onTap: () => Navigator.pop(context, 'voice'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'camera') await _pickImage(camera: true);
    if (action == 'photo') await _pickImage();
    if (action == 'voice') await _startVoice();
  }

  Future<void> _pickLanguage() async {
    final settings = ref.read(appSettingsProvider);
    final selected = settings.locale == null ? 'system' : settings.locale!.languageCode;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              const ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(0xFFE8F1FF),
                  child: Icon(Icons.language_rounded, color: _blue),
                ),
                title: Text('ASKODOX Language',
                    style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                subtitle: Text('Auto follows your device. Change anytime.',
                    style: TextStyle(color: _muted)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    RadioListTile<String>(
                      value: 'system',
                      groupValue: selected,
                      activeColor: _blue,
                      onChanged: (value) => Navigator.pop(context, value),
                      title: const Text('Auto / Device language'),
                    ),
                    for (final language in AskodoxLanguageCatalog.all)
                      RadioListTile<String>(
                        value: language.code,
                        groupValue: selected,
                        activeColor: _blue,
                        onChanged: (value) => Navigator.pop(context, value),
                        title: Text(language.name),
                        subtitle: Text(language.code.toUpperCase()),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final session = ref.watch(universalDealControllerProvider);
    final deal = session.deal;
    final languageLabel = settings.locale == null
        ? 'Auto'
        : AskodoxLanguageCatalog.byCode(settings.locale!.languageCode).name;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.menu_rounded, color: _ink),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ASKODOX',
                style: TextStyle(
                    color: _ink, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            Text(
              _tr('Find Local • Buy Local • Support Local',
                  'లోకల్‌గా కనుగొను • లోకల్‌గా కొనండి',
                  'लोकल खोजें • लोकल खरीदें',
                  'ଲୋକାଲ୍ ଖୋଜନ୍ତୁ • ଲୋକାଲ୍ କିଣନ୍ତୁ'),
              style: const TextStyle(fontSize: 9.5, color: _muted),
            ),
          ],
        ),
        actions: [
          if (deal?.location.label case final location?)
            Tooltip(
              message: location,
              child: const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(Icons.location_on_rounded, color: _blue),
              ),
            ),
          TextButton(
            key: const Key('askodoxLanguageButton'),
            onPressed: _pickLanguage,
            child: Text(languageLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            const _PromoBanner(),
            const SizedBox(height: 18),
            if (deal == null) ...[
              Center(child: AskodoxVoiceOrb(onTap: _startVoice)),
              const SizedBox(height: 12),
              Text(
                askodoxGreetingForHour(DateTime.now().hour, _lang()),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _tr('How can I help you today?', 'ఈ రోజు నేను మీకు ఎలా సహాయం చేయాలి?',
                    'आज मैं आपकी कैसे मदद करूँ?', 'ଆଜି ମୁଁ କିପରି ସହାୟତା କରିପାରିବି?'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _ink, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _tr('Ask anything — shops, services, products, jobs, appointments or any local need.',
                    'షాపులు, సేవలు, ఉత్పత్తులు, ఉద్యోగాలు లేదా ఏ అవసరమైనా అడగండి.',
                    'दुकान, सेवा, उत्पाद, नौकरी या कोई भी ज़रूरत पूछें।',
                    'ଦୋକାନ, ସେବା, ପ୍ରୋଡକ୍ଟ, ଜବ୍ କିମ୍ବା ଯେକୌଣସି ଆବଶ୍ୟକତା ପଚାରନ୍ତୁ।'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.35),
              ),
              const SizedBox(height: 14),
              _QuickActions(onAsk: _startFlow),
            ] else ...[
              _ConversationHeader(deal: deal, tr: _tr),
              if (_lastUserMessage != null) ...[
                const SizedBox(height: 12),
                _UserBubble(text: _lastUserMessage!),
              ],
              if (_lastAssistantMessage != null) ...[
                const SizedBox(height: 10),
                _AssistantBubble(text: _lastAssistantMessage!),
              ],
              const SizedBox(height: 12),
              _ActiveDealCard(deal: deal, session: session, tr: _tr),
              if (_matching) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _tr('Finding the best matches…', 'సరైన matches వెతుకుతున్నాను…',
                        'सही matches खोज रहा हूँ…', 'ସଠିକ matches ଖୋଜୁଛି…'),
                    style: const TextStyle(color: _muted),
                  ),
                ),
              ],
              if (_matchError != null) ...[
                const SizedBox(height: 12),
                _InfoStrip(text: _matchError!),
              ],
              if (_matchResult case final result?) ...[
                const SizedBox(height: 14),
                _InlineMatches(result: result, tr: _tr),
              ],
              if (!_matching && session.completed && _matchResult == null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('askodoxFindMatchesButton'),
                  onPressed: _loadMatches,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(_tr('Find matches', 'మ్యాచ్‌లు కనుగొను',
                      'Matches खोजें', 'Matches ଖୋଜନ୍ତୁ')),
                ),
              ],
            ],
            const SizedBox(height: 18),
            _AskField(
              controller: _controller,
              focusNode: _focusNode,
              hint: _tr('Type or speak your request…', 'టైప్ చేయండి లేదా మాట్లాడండి…',
                  'टाइप करें या बोलें…', 'ଟାଇପ୍ କିମ୍ବା କହନ୍ତୁ…'),
              onSubmit: _submit,
              onVoice: _startVoice,
              onImage: _pickImage,
              onMore: _showActions,
            ),
            if (_attachment case final attachment?) ...[
              const SizedBox(height: 8),
              _AttachmentChip(
                name: attachment.name,
                onRemove: () => setState(() => _attachment = null),
              ),
            ],
            const SizedBox(height: 24),
            _SectionHeader(
              title: _tr('In Progress', 'ప్రస్తుతం జరుగుతున్నవి', 'चल रहा है', 'ଚାଲିଛି'),
              action: _tr('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ'),
              onTap: () => context.go('/activity'),
            ),
            const SizedBox(height: 10),
            _ProgressCard(
              title: deal == null
                  ? _tr('No active request yet', 'ఇంకా active request లేదు',
                      'अभी active request नहीं है', 'ଏଯାଏଁ active request ନାହିଁ')
                  : _tr('One active request is continuing here',
                      'ఒక active request ఇక్కడే కొనసాగుతోంది',
                      'एक active request यहीं जारी है',
                      'ଏକ active request ଏଠି ଜାରି ଅଛି'),
              subtitle: deal?.subject ??
                  _tr('Start above and ASKODOX will keep the context.',
                      'పై నుంచి ప్రారంభించండి; ASKODOX contextని కొనసాగిస్తుంది.',
                      'ऊपर शुरू करें; ASKODOX context बनाए रखेगा।',
                      'ଉପରୁ ଆରମ୍ଭ କରନ୍ତୁ; ASKODOX context ରଖିବ।'),
              onTap: _scrollToConversation,
            ),
            const SizedBox(height: 22),
            _SectionHeader(
              title: _tr('Continue your conversations', 'మీ సంభాషణలను కొనసాగించండి',
                  'अपनी बातचीत जारी रखें', 'ଆପଣଙ୍କ କଥୋପକଥନ ଜାରି ରଖନ୍ତୁ'),
              action: _tr('Same screen', 'ఇదే స్క్రీన్', 'यही स्क्रीन', 'ଏହି screen'),
              onTap: _scrollToConversation,
            ),
            const SizedBox(height: 12),
            _BottomNav(
              te: _lang() == 'te',
              hi: _lang() == 'hi',
              odia: _lang() == 'or',
              onAsk: _scrollToConversation,
              onActivity: () => context.go('/activity'),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Translator = String Function(String, String, String, String);

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF6C7), Color(0xFFFFFDF0)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFE58A)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              backgroundColor: _yellow,
              child: Icon(Icons.local_offer_rounded, color: _ink),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Local Deals & Offers',
                      style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                  SizedBox(height: 2),
                  Text('Promotions stay on Home — chat and results remain on this same screen.',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAsk});
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            label: const Text('Find chicken near me'),
            onPressed: () => onAsk('I need chicken near me'),
          ),
          ActionChip(
            label: const Text('Book a service'),
            onPressed: () => onAsk('I need a local service'),
          ),
          ActionChip(
            label: const Text('Find a job'),
            onPressed: () => onAsk('I need a computer operator job'),
          ),
          ActionChip(
            label: const Text('Today’s offers'),
            onPressed: () => onAsk('Show me useful local offers'),
          ),
        ],
      );
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.deal, required this.tr});
  final UniversalDeal deal;
  final _Translator tr;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE7F7)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFEAF8EF),
              child: Icon(Icons.smart_toy_rounded, color: _green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('ASKODOX is continuing the same request',
                        'ASKODOX ఇదే requestను కొనసాగిస్తోంది',
                        'ASKODOX इसी request को जारी रख रहा है',
                        'ASKODOX ଏହି request କୁ ଜାରି ରଖିଛି'),
                    style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${deal.subject ?? deal.rawText}${deal.location.label == null ? '' : ' • ${deal.location.label}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ActiveDealCard extends StatelessWidget {
  const _ActiveDealCard({required this.deal, required this.session, required this.tr});
  final UniversalDeal deal;
  final UniversalDealSession session;
  final _Translator tr;

  @override
  Widget build(BuildContext context) {
    final fields = <String>[
      if (deal.subject != null) deal.subject!,
      if (deal.location.label != null) deal.location.label!,
      if (deal.price != null) '₹${deal.price!.toStringAsFixed(0)}',
      if (deal.model != null) deal.model!,
      if (deal.variant != null) deal.variant!,
      if (deal.size != null) deal.size!,
    ];
    return Container(
      key: const Key('askodoxActiveDealCard'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCFE1FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('I understood', 'నేను అర్థం చేసుకున్నది', 'मैंने समझा', 'ମୁଁ ବୁଝିଲି'),
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(fields.isEmpty ? deal.rawText : fields.join(' • '),
              style: const TextStyle(color: _ink, height: 1.4)),
          if (!session.completed && session.lastQuestion != null) ...[
            const SizedBox(height: 8),
            Text(session.lastQuestion!,
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class _InlineMatches extends StatelessWidget {
  const _InlineMatches({required this.result, required this.tr});
  final UniversalMatchResult result;
  final _Translator tr;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Best matches', 'సరైన matches', 'बेहतरीन matches', 'ସର୍ବୋତ୍ତମ matches'),
            style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.matches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final match = result.matches[index];
                final demo = match.id.startsWith('demo-');
                return Container(
                  key: ValueKey('askodoxMatch-${match.id}'),
                  width: 220,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD9E5F6)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0D10204A), blurRadius: 14, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFEAF8EF),
                            child: Icon(Icons.storefront_rounded, color: _green),
                          ),
                          const Spacer(),
                          if (demo)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4C2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('DEMO',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(match.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(match.subtitle ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 11, height: 1.25)),
                      const Spacer(),
                      Row(
                        children: [
                          if (match.score != null)
                            Text('★ ${match.score!.toStringAsFixed(0)}',
                                style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          if (match.distanceKm != null)
                            Text('${match.distanceKm!.toStringAsFixed(1)} km',
                                style: const TextStyle(color: _muted, fontSize: 11)),
                        ],
                      ),
                      if (match.price != null) ...[
                        const SizedBox(height: 4),
                        Text('₹${match.price!.toStringAsFixed(0)}',
                            style: const TextStyle(color: _green, fontWeight: FontWeight.w900)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _blue,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, height: 1.35)),
        ),
      );
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE7F4)),
          ),
          child: Text(text, style: const TextStyle(color: _ink, height: 1.35)),
        ),
      );
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFB7791F), size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: _ink, fontSize: 12))),
          ],
        ),
      );
}

class _AskField extends StatelessWidget {
  const _AskField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmit,
    required this.onVoice,
    required this.onImage,
    required this.onMore,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;
  final VoidCallback onVoice;
  final VoidCallback onImage;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxAskField'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFD8E4F3)),
          boxShadow: const [
            BoxShadow(color: Color(0x0D10204A), blurRadius: 16, offset: Offset(0, 7)),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              key: const Key('askodoxPlusButton'),
              tooltip: 'More actions',
              onPressed: onMore,
              icon: const Icon(Icons.add_circle_outline_rounded, color: _blue),
            ),
            IconButton(
              key: const Key('askodoxMicButton'),
              onPressed: onVoice,
              icon: const Icon(Icons.mic_rounded, color: _green),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: _muted),
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              key: const Key('askodoxImageButton'),
              tooltip: 'Add image',
              onPressed: onImage,
              icon: const Icon(Icons.image_outlined, color: _ink),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: IconButton.filled(
                key: const Key('askodoxSendButton'),
                tooltip: 'Send',
                onPressed: onSubmit,
                style: IconButton.styleFrom(backgroundColor: _yellow),
                icon: const Icon(Icons.arrow_upward_rounded, color: _ink),
              ),
            ),
          ],
        ),
      );
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxAttachmentChip'),
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_rounded, color: _blue, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
            ),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE7F5)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF8EF),
                child: Icon(Icons.auto_awesome_rounded, color: _green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_up_rounded, color: _muted),
            ],
          ),
        ),
      );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.te,
    required this.hi,
    required this.odia,
    required this.onAsk,
    required this.onActivity,
  });
  final bool te;
  final bool hi;
  final bool odia;
  final VoidCallback onAsk;
  final VoidCallback onActivity;

  String t(String en, String tv, String hv, String ov) => te ? tv : hi ? hv : odia ? ov : en;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (i) {
          if (i == 0 || i == 1) onAsk();
          if (i == 2) onActivity();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: t('Chats', 'చాట్స్', 'चैट्स', 'ଚାଟ୍ସ'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_rounded),
            label: t('Ask', 'అడగండి', 'पूछें', 'ପଚାରନ୍ତୁ'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none_rounded),
            label: t('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ'),
          ),
        ],
      );
}
