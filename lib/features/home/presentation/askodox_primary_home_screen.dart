import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/environment.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../services/in_app_assistant_service.dart';
import '../../../services/document_intelligence_service.dart';
import '../../../services/real_product_match_service.dart';
import '../../../services/vision_api_service.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/video_analysis_service.dart';
import '../../../services/reply_speech_service.dart';
import '../../../services/support_escalation_service.dart';
import '../../../services/voice_endpointing.dart';
import '../../../services/voice_transcription_service.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../location/application/location_controller.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../../selling/data/seller_listing_repository.dart';
import '../application/conversation_archive.dart';
import '../domain/active_role.dart';
import '../domain/chat_result_policy.dart';
import '../domain/need_clarification.dart';
import '../domain/home_request_routing.dart';
import '../domain/semantic_deal_input.dart';
import 'askodox_orb.dart';
import 'video_viewer_screen.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF667085);
const _accent = Color(0xFFFFC928);
const _blue = Color(0xFF1769FF);

String askodoxAttachmentMimeType(String filename) {
  final extension = filename.toLowerCase().split('.').last;
  return switch (extension) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'json' => 'application/json',
    _ => 'application/octet-stream',
  };
}

String askodoxContinuationReply({
  required String previousUserTurn,
  required bool telugu,
}) {
  final context = previousUserTurn.trim().replaceAll(RegExp(r'\s+'), ' ');
  final shortContext = context.length <= 72
      ? context
      : '${context.substring(0, 69)}…';
  return telugu
      ? 'మనం “$shortContext” నుంచి కొనసాగిద్దాం. ఇప్పుడు మొదటి పని: ఆ ప్లాన్‌లో ఇంకా పూర్తికాని మొదటి అంశాన్ని ఎంచుకుని దానికి కావాల్సిన ఒక చిన్న చర్యను పూర్తి చేద్దాం. అది పూర్తయ్యాక తదుపరి అంశానికి వెళ్దాం.'
      : 'Let’s continue from “$shortContext”. Next step: choose the first unfinished item in that plan and complete one small action for it. Then we’ll move to the next item.';
}

    bool askodoxIsGenericAssistantReply(String reply) {
      final normalized = reply.trim().toLowerCase();
      return normalized.isEmpty ||
      normalized == 'understood' ||
      normalized == 'got it' ||
      normalized == 'okay' ||
      normalized == 'ok' ||
      normalized == 'continuing your request.' ||
      normalized == 'understood. continuing your request.';
    }

// Injectable so widget tests can drive the whole chat → matching → results
// flow without the network. Production uses the same default instances the
// screen always constructed directly.
final askodoxAssistantServiceProvider =
    Provider<InAppAssistantService>((ref) => const InAppAssistantService());
final askodoxRealProductMatchServiceProvider =
    Provider<RealProductMatchService>((ref) => const RealProductMatchService());
final askodoxVisionServiceProvider =
    Provider<VisionApiService>((ref) => const VisionApiService());
final askodoxSupportEscalationServiceProvider =
    Provider<SupportEscalationService>((ref) => const SupportEscalationService());
final askodoxReplySpeechServiceProvider =
    Provider<ReplySpeechService>((ref) => const ReplySpeechService());
final askodoxVoiceTranscriptionServiceProvider =
    Provider<VoiceTranscriptionService>(
        (ref) => const VoiceTranscriptionService());

/// Main Chat voice state: Idle → Listening → Understanding (Sarvam STT)
/// → Thinking (ASKODOX AI) → Speaking (reply voice).
enum _VoicePhase { idle, recording, transcribing, thinking, speaking }

class AskodoxPrimaryHomeScreen extends ConsumerStatefulWidget {
  const AskodoxPrimaryHomeScreen({super.key});
  @override
  ConsumerState<AskodoxPrimaryHomeScreen> createState() =>
      _AskodoxPrimaryHomeScreenState();
}

class _AskodoxPrimaryHomeScreenState
    extends ConsumerState<AskodoxPrimaryHomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _store = ConversationTurnStore();
  final List<ConversationTurnRecord> _turns = [];

  // Rich results embedded in the conversation, keyed by the index of the
  // assistant turn they belong to. Earlier result sets stay in the history
  // while the user refines, like any other chat message.
  final Map<int, AskodoxChatResults> _resultsByTurn = {};
  final Map<int, UniversalDeal> _dealByTurn = {};
  final Map<int, String> _roleNoticeByTurn = {};
  DealIntent? _lastIntent;

  // History: every conversation is saved as a snapshot under this id.
  String _conversationId = _newConversationId();
  static String _newConversationId() =>
      'c-${DateTime.now().microsecondsSinceEpoch}';

  // AI-first deal flow: Send request / Connect appear on an option only
  // after the user discussed it with ASKODOX or asked for the seller.
  final Set<String> _actionableMatchKeys = {};
  final Set<String> _requestSentMatchKeys = {};
  String? _pendingAiContext;
  bool _pendingDiscussOnly = false;

  // One concise clarification for an ambiguous need, asked before search.
  AskodoxClarification? _pendingClarification;
  final Set<String> _clarifiedKeys = {};
  final Map<int, AskodoxClarification> _clarificationByTurn = {};

  // Active role question awaiting the user's answer, keyed by user turn.
  final Map<int, AskodoxUserRole> _roleQuestionByTurn = {};

  // First-line support: escalation offered under these assistant turns.
  final Map<int, AskodoxSupportAssessment> _supportByTurn = {};
  final Map<int, AskodoxSupportCase> _supportCaseByTurn = {};
  int _issueTurns = 0;
  bool _active = false;
  bool _sending = false;
  _VoicePhase _voicePhase = _VoicePhase.idle;
  XFile? _attachment;
  Uint8List? _attachmentPreviewBytes;
  String? _attachmentLabel;

  // Shown instead of `_matches` when the completed deal is a "sell" listing
  // rather than a buyer-side search -- see `_createRealListing`.
  String? _listingBanner;
  bool _listingBannerIsError = false;

  String? _lastGoodProductQuery;

  static const _searchQueryStopwords = {
    'yes',
    'no',
    'ok',
    'okay',
    'please',
    'show',
    'rate',
    'confirm',
    'nearby',
    'sure',
    'yeah',
    'yep',
    'nope',
    'first',
    'it',
    'each',
    'not',
    'and',
    'the',
    'price',
    'cost',
    'check',
    'quantity',
    'shop',
    'shops',
    'option',
    'options',
    'order',
    'buy',
    'need',
    'want',
    'budget',
    'rupees',
    'rs',
    'available',
    'availability',
    'proceed',
    'place',
    'kavali',
    'ready',
    'go',
    'ahead',
  };

  bool _looksLikeProductSubject(String value) {
    if (RegExp(r'\d').hasMatch(value)) return false;
    final words =
        value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 6) return false;
    return words.any((w) => !_searchQueryStopwords.contains(w.toLowerCase()));
  }

  void _trackSearchQuery(String? candidate) {
    final trimmed = (candidate ?? '').trim();
    if (trimmed.isNotEmpty && _looksLikeProductSubject(trimmed)) {
      _lastGoodProductQuery = trimmed;
    }
  }

  bool get _te => ref.read(appSettingsProvider).locale?.languageCode == 'te';

  static const _device = MethodChannel('com.askodox.app/device');
  static const _voiceSampleInterval = Duration(milliseconds: 200);
  Timer? _voiceTimer;
  AskodoxVoiceEndpointer? _endpointer;
  int _voiceTicks = 0;

  // Live microphone levels (0..1) from the same voiceRecordingLevel samples
  // the endpointer uses -- drives the Listening waveform.
  final List<double> _voiceLevels = [];
  static const _voiceLevelBars = 24;

  /// Which engine spoke the last reply: 'sarvam_bulbul_v3' or 'device'.
  String? lastReplyVoiceEngine;
  bool _voiceFinishing = false;

  /// Main Chat voice: record in-app, transcribe through the backend's
  /// Sarvam-first pipeline, then continue the same conversation. The app
  /// keeps recording while the user speaks and ends only on genuine silence
  /// ([AskodoxVoiceEndpointer]) or the user's Stop; the close button
  /// cancels. There is no fallback to the Android system recognizer.
  Future<void> _startVoice() async {
    if (_voicePhase == _VoicePhase.recording) {
      await _finishVoice(noSpeech: false);
      return;
    }
    if (_voicePhase == _VoicePhase.speaking) {
      // A new mic turn interrupts the reply ASKODOX is speaking.
      await _stopSpeaking();
    }
    if (_voicePhase != _VoicePhase.idle || _sending) return;
    final te = _te;
    setState(() {
      _voicePhase = _VoicePhase.recording;
      _voiceLevels.clear();
      _voiceTicks = 0;
    });
    bool? started;
    try {
      started = await _device.invokeMethod<bool>('startVoiceRecording', <String, Object?>{
        'languageCode': te ? 'te' : 'en',
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _voicePhase = _VoicePhase.idle);
        _voiceError(switch (error.code) {
          'mic_denied' => te
              ? 'మైక్రోఫోన్ అనుమతి లేదు. Settings లో అనుమతించి మళ్లీ ప్రయత్నించండి.'
              : 'Microphone permission is off. Allow it in Settings and try again.',
          _ => te
              ? 'వాయిస్ ప్రారంభం కాలేదు. మళ్లీ ప్రయత్నించండి.'
              : 'Voice could not start. Please try again.',
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _voicePhase = _VoicePhase.idle);
        _voiceError(te
            ? 'వాయిస్ ప్రారంభం కాలేదు. మళ్లీ ప్రయత్నించండి.'
            : 'Voice could not start. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    if (started != true) {
      // Cancelled before recording began (e.g. during the permission prompt).
      setState(() => _voicePhase = _VoicePhase.idle);
      return;
    }
    _endpointer = AskodoxVoiceEndpointer();
    _voiceFinishing = false;
    _voiceTicks = 0;
    _voiceTimer = Timer.periodic(_voiceSampleInterval, (_) => _sampleVoice());
  }

  Future<void> _sampleVoice() async {
    if (_voiceFinishing || _voicePhase != _VoicePhase.recording) return;
    int? level;
    try {
      level = await _device.invokeMethod<int>('voiceRecordingLevel');
    } catch (_) {
      level = 0;
    }
    if (!mounted || _voiceFinishing) return;
    if (level == null) {
      // Native recording ended outside the app's control (app backgrounded).
      _stopVoiceTimer();
      setState(() => _voicePhase = _VoicePhase.idle);
      return;
    }
    _voiceTicks++;
    setState(() {
      // Perceptual scale so normal speech visibly moves the bars.
      final normalized = (level! / 12000).clamp(0.0, 1.0);
      _voiceLevels.add(normalized <= 0 ? 0 : math.sqrt(normalized));
      if (_voiceLevels.length > _voiceLevelBars) _voiceLevels.removeAt(0);
    });
    final decision = _endpointer?.add(level, _voiceSampleInterval * _voiceTicks) ??
        VoiceEndpointDecision.keepRecording;
    switch (decision) {
      case VoiceEndpointDecision.keepRecording:
        return;
      case VoiceEndpointDecision.stopNoSpeech:
        await _finishVoice(noSpeech: true);
      case VoiceEndpointDecision.stopAfterSilence:
      case VoiceEndpointDecision.stopMaxDuration:
        await _finishVoice(noSpeech: false);
    }
  }

  void _stopVoiceTimer() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
  }

  /// Ends the recording (genuine silence, max duration or the user's Stop)
  /// and sends the Sarvam transcript into the chat.
  Future<void> _finishVoice({required bool noSpeech}) async {
    if (_voiceFinishing || _voicePhase != _VoicePhase.recording) return;
    _voiceFinishing = true;
    _stopVoiceTimer();
    final te = _te;
    if (noSpeech) {
      try {
        await _device.invokeMethod<Object?>('cancelVoiceRecording');
      } catch (_) {}
      if (!mounted) return;
      setState(() => _voicePhase = _VoicePhase.idle);
      _voiceError(te
          ? 'మీ మాట వినిపించలేదు. మళ్లీ మాట్లాడండి.'
          : 'I did not hear anything. Please try again.');
      return;
    }
    String? path;
    try {
      path = await _device.invokeMethod<String>('stopVoiceRecording');
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() => _voicePhase = _VoicePhase.idle);
      _voiceError(te
          ? 'మీ మాట వినిపించలేదు. మళ్లీ మాట్లాడండి.'
          : 'I did not hear anything. Please try again.');
      return;
    }
    setState(() => _voicePhase = _VoicePhase.transcribing);
    final transcript = await ref
        .read(askodoxVoiceTranscriptionServiceProvider)
        .transcribeFile(path, locale: te ? 'te' : 'en');
    if (!mounted) return;
    if (transcript == null) {
      setState(() => _voicePhase = _VoicePhase.idle);
      _voiceError(te
          ? 'మీ మాటను అర్థం చేసుకోలేకపోయాం. మళ్లీ ప్రయత్నించండి లేదా టైప్ చేయండి.'
          : 'I could not understand that. Please try again or type your message.');
      return;
    }
    setState(() => _voicePhase = _VoicePhase.thinking);
    await _send(transcript, true);
    if (mounted && _voicePhase == _VoicePhase.thinking) {
      setState(() => _voicePhase = _VoicePhase.idle);
    }
  }

  Future<void> _cancelVoice() async {
    _voiceFinishing = true;
    _stopVoiceTimer();
    try {
      await _device.invokeMethod<Object?>('cancelVoiceRecording');
    } catch (_) {}
    if (mounted) setState(() => _voicePhase = _VoicePhase.idle);
  }

  /// Interruption: typing/sending a new message or starting the mic stops
  /// any reply ASKODOX is still speaking.
  Future<void> _stopSpeaking() async {
    try {
      await _device.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
    if (mounted && _voicePhase == _VoicePhase.speaking) {
      setState(() => _voicePhase = _VoicePhase.idle);
    }
  }

  void _voiceError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }


  Future<void> _showAttachmentMenu() async {
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(_te ? 'కెమెరా' : 'Camera'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(_te ? 'ఫోటోలు' : 'Photos'),
            onTap: () => Navigator.pop(context, 'photos'),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: Text(_te ? 'వీడియో' : 'Video'),
            onTap: () => Navigator.pop(context, 'video'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_rounded),
            title: Text(_te ? 'ఫైల్స్' : 'Files'),
            onTap: () => Navigator.pop(context, 'files'),
          ),
        ]),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'camera' || choice == 'photos' || choice == 'video') {
      final capture = MultimodalCaptureService();
      final file = choice == 'camera'
          ? await capture.captureCamera()
          : choice == 'video'
              ? await capture.chooseVideo()
              : await capture.chooseGallery();
      if (file == null || !mounted) return;
      final previewBytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachment = file;
        _attachmentPreviewBytes = previewBytes;
        _attachmentLabel = file.name;
      });
        return;
      }
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;
      final file = picked.first;
      final bytes = await file.readAsBytes();
      final analyzed = await const DocumentIntelligenceService().analyzeBytes(
        bytes: bytes,
        filename: file.name,
        mimeType: askodoxAttachmentMimeType(file.name),
      );
      if (!mounted) return;
      setState(() {
        _attachmentPreviewBytes = null;
        _attachmentLabel = file.name;
      });
      if (analyzed == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'ఫైల్ తెరుచుకుంది, కానీ దాన్ని విశ్లేషించలేకపోయాం. మళ్లీ ప్రయత్నించండి.'
              : 'The file opened, but analysis failed. Please try again.'),
        ));
        return;
      }
      setState(() => _controller.text = analyzed.conversationSeed());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_te
            ? 'అటాచ్‌మెంట్‌ను తెరవడం లేదా విశ్లేషించడం సాధ్యం కాలేదు.'
            : 'The attachment could not be opened or analyzed. Please try again.'),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual<AskodoxChatRequest?>(askodoxChatRequestProvider,
        (previous, next) {
      if (next != null) unawaited(_handleChatRequest(next));
    }, fireImmediately: true);
    unawaited(_restore());
  }

  /// Requests from History ("open" / "New ask") and Explore ("ask this").
  Future<void> _handleChatRequest(AskodoxChatRequest request) async {
    Future.microtask(() {
      if (mounted) ref.read(askodoxChatRequestProvider.notifier).state = null;
    });
    if (request.newConversation) {
      await _startNewConversation();
      return;
    }
    final id = request.conversationId;
    if (id != null) {
      final archive = ref.read(askodoxConversationArchiveProvider.notifier);
      await archive.ready();
      final snapshot = archive.byId(id);
      if (snapshot != null) await _applySnapshot(snapshot);
      return;
    }
    final prompt = request.prompt;
    if (prompt != null && prompt.trim().isNotEmpty) await _send(prompt);
  }

  Future<void> _restore() async {
    // Reopen the exact last conversation (results, deal, role) when it was
    // archived; otherwise fall back to the legacy turn store.
    final archive = ref.read(askodoxConversationArchiveProvider.notifier);
    await archive.ready();
    final currentId = await archive.currentId();
    final snapshot = currentId == null ? null : archive.byId(currentId);
    if (!mounted) return;
    if (snapshot != null) {
      await _applySnapshot(snapshot);
      return;
    }
    final records = await _store.load();
    if (!mounted || records.isEmpty) return;
    final deal = ref.read(universalDealControllerProvider).deal;
    // Real seller-backed search replaces the old DemoNaturalMatchCatalog
    // sandbox data (which showed fake, sometimes domain-mismatched
    // placeholder businesses before the app had even finished asking for
    // required details). `readyToMatch` keeps the same "don't show anything
    // until the request is actually understood" gate the demo catalog used.
    AskodoxChatResults? results;
    String? listingBanner;
    var listingBannerIsError = false;
    if (deal != null) {
      _trackSearchQuery(deal.subject ?? deal.category);
      if (deal.readyToMatch &&
          AskodoxHomeRequestRouting.isTransactional(deal.rawText)) {
        if (deal.intent == DealIntent.sell) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          results = await _findUniversalMatches(deal);
        }
      }
      _lastIntent = deal.intent;
    }
    if (!mounted) return;
    setState(() {
      _turns.addAll(records);
      _active = true;
      final lastAssistant = _turns.lastIndexWhere((turn) => !turn.isUser);
      if (results != null && !results.isEmpty && lastAssistant >= 0) {
        _resultsByTurn[lastAssistant] = results;
        if (deal != null) _dealByTurn[lastAssistant] = deal;
      }
      _listingBanner = listingBanner;
      _listingBannerIsError = listingBannerIsError;
    });
    _scrollBottom();
  }

  // ----------------------------------------------------------- History --

  AskodoxConversationStatus get _conversationStatus {
    if (_requestSentMatchKeys.isNotEmpty) return AskodoxConversationStatus.completed;
    if (_resultsByTurn.values.any((results) => results.hasLocal)) {
      return AskodoxConversationStatus.matched;
    }
    return AskodoxConversationStatus.active;
  }

  String get _conversationTitle {
    final first = _turns.firstWhere((turn) => turn.isUser,
        orElse: () => const ConversationTurnRecord(text: 'ASKODOX', isUser: true));
    final line = first.text.split('\n').first.trim();
    return line.length <= 60 ? line : '${line.substring(0, 57)}…';
  }

  Map<String, Object?> _snapshotData() {
    final deals = ref.read(universalDealControllerProvider.notifier);
    return {
      'turns': [for (final turn in _turns) turn.toJson()],
      'results': {
        for (final entry in _resultsByTurn.entries)
          '${entry.key}': {
            'dealId': entry.value.dealId,
            'matches': [for (final m in entry.value.matches) m.toJson()],
            'failed': entry.value.failed,
            'signInRequired': entry.value.signInRequired,
            'missingFields': entry.value.missingFields,
          },
      },
      'deals': {
        for (final entry in _dealByTurn.entries)
          '${entry.key}': deals.encodeDeal(entry.value),
      },
      'roleNotices': {
        for (final entry in _roleNoticeByTurn.entries) '${entry.key}': entry.value,
      },
      'roleQuestions': {
        for (final entry in _roleQuestionByTurn.entries) '${entry.key}': entry.value.name,
      },
      'support': {
        for (final entry in _supportByTurn.entries)
          '${entry.key}': {'need': entry.value.need.name, 'category': entry.value.category},
      },
      'activeDeal': deals.snapshot(),
      'activeRole': ref.read(askodoxRoleProvider).active.name,
      'lastIntent': _lastIntent?.name,
      'actionable': _actionableMatchKeys.toList(),
      'requested': _requestSentMatchKeys.toList(),
      'issueTurns': _issueTurns,
      'clarified': _clarifiedKeys.toList(),
      'pendingClarification': _pendingClarification?.key,
      'clarifications': {
        for (final entry in _clarificationByTurn.entries) '${entry.key}': entry.value.key,
      },
      'lastQuery': _lastGoodProductQuery,
    };
  }

  Future<void> _saveSnapshot() async {
    if (_turns.isEmpty) return;
    await ref.read(askodoxConversationArchiveProvider.notifier).save(
          AskodoxConversationSnapshot(
            id: _conversationId,
            title: _conversationTitle,
            updatedAt: DateTime.now(),
            status: _conversationStatus,
            data: _snapshotData(),
          ),
        );
  }

  void _clearConversationState() {
    _turns.clear();
    _resultsByTurn.clear();
    _dealByTurn.clear();
    _roleNoticeByTurn.clear();
    _roleQuestionByTurn.clear();
    _supportByTurn.clear();
    _supportCaseByTurn.clear();
    _actionableMatchKeys.clear();
    _requestSentMatchKeys.clear();
    _issueTurns = 0;
    _pendingClarification = null;
    _clarifiedKeys.clear();
    _clarificationByTurn.clear();
    _lastIntent = null;
    _lastGoodProductQuery = null;
    _listingBanner = null;
    _listingBannerIsError = false;
  }

  /// "New ask": a clean conversation. The previous one stays in History.
  Future<void> _startNewConversation() async {
    await _saveSnapshot();
    if (!mounted) return;
    setState(() {
      _clearConversationState();
      _conversationId = _newConversationId();
      _active = false;
    });
    ref.read(universalDealControllerProvider.notifier).reset();
    await _store.clear();
    await ref.read(askodoxConversationArchiveProvider.notifier).setCurrent(null);
  }

  /// Reopens a History conversation exactly: turns, results, deals, role,
  /// questions/answers and which options were discussed or requested.
  Future<void> _applySnapshot(AskodoxConversationSnapshot snapshot) async {
    if (snapshot.id != _conversationId) await _saveSnapshot();
    if (!mounted) return;
    final data = snapshot.data;
    final deals = ref.read(universalDealControllerProvider.notifier);
    Map<String, dynamic> map(Object? raw) =>
        raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    AskodoxUserRole? role(Object? name) {
      for (final value in AskodoxUserRole.values) {
        if (value.name == name) return value;
      }
      return null;
    }

    setState(() {
      _clearConversationState();
      _conversationId = snapshot.id;
      _turns.addAll((data['turns'] as List? ?? const [])
          .map(ConversationTurnRecord.fromJson)
          .whereType<ConversationTurnRecord>());
      map(data['results']).forEach((key, raw) {
        final json = map(raw);
        _resultsByTurn[int.parse(key)] = AskodoxChatResults(
          dealId: json['dealId']?.toString(),
          matches: [
            for (final m in (json['matches'] as List? ?? const []))
              if (m is Map) UniversalMatch.fromJson(m.cast<String, Object?>()),
          ],
          failed: json['failed'] == true,
          signInRequired: json['signInRequired'] == true,
          missingFields: [
            for (final f in (json['missingFields'] as List? ?? const [])) '$f',
          ],
        );
      });
      map(data['deals']).forEach((key, raw) {
        final deal = deals.decodeDeal(map(raw));
        if (deal != null) _dealByTurn[int.parse(key)] = deal;
      });
      map(data['roleNotices']).forEach((key, raw) => _roleNoticeByTurn[int.parse(key)] = '$raw');
      map(data['roleQuestions']).forEach((key, raw) {
        final value = role(raw);
        if (value != null) _roleQuestionByTurn[int.parse(key)] = value;
      });
      map(data['support']).forEach((key, raw) {
        final json = map(raw);
        final need = AskodoxSupportNeed.values.firstWhere(
            (value) => value.name == json['need'],
            orElse: () => AskodoxSupportNeed.afterAiAttempt);
        _supportByTurn[int.parse(key)] = AskodoxSupportAssessment(need,
            category: json['category']?.toString() ?? 'GENERAL');
      });
      _actionableMatchKeys.addAll([for (final k in (data['actionable'] as List? ?? const [])) '$k']);
      _requestSentMatchKeys.addAll([for (final k in (data['requested'] as List? ?? const [])) '$k']);
      _issueTurns = (data['issueTurns'] as num?)?.toInt() ?? 0;
      _clarifiedKeys.addAll([for (final k in (data['clarified'] as List? ?? const [])) '$k']);
      map(data['clarifications']).forEach((key, raw) {
        final value = askodoxClarificationByKey('$raw');
        if (value != null) _clarificationByTurn[int.parse(key)] = value;
      });
      final pendingKey = data['pendingClarification']?.toString();
      if (pendingKey != null) {
        for (final value in _clarificationByTurn.values) {
          if (value.key == pendingKey) _pendingClarification = value;
        }
      }
      _lastGoodProductQuery = data['lastQuery']?.toString();
      final intentName = data['lastIntent'];
      for (final intent in DealIntent.values) {
        if (intent.name == intentName) _lastIntent = intent;
      }
      _active = _turns.isNotEmpty;
    });
    deals.restoreSnapshot(data['activeDeal'] is Map ? map(data['activeDeal']) : null);
    final activeRole = role(data['activeRole']);
    if (activeRole != null) ref.read(askodoxRoleProvider.notifier).setActive(activeRole);
    await _store.save(_turns);
    await ref.read(askodoxConversationArchiveProvider.notifier).setCurrent(snapshot.id);
    _scrollBottom();
  }

  // ---------------------------------------------------- AI-first options --

  static String _matchKey(String? dealId, UniversalMatch match) =>
      '${dealId ?? ''}::${match.id}';

  AskodoxChatResults? _latestResults() {
    if (_resultsByTurn.isEmpty) return null;
    final lastKey = _resultsByTurn.keys.reduce((a, b) => a > b ? a : b);
    return _resultsByTurn[lastKey];
  }

  String _resultsContext(AskodoxChatResults results) => [
        for (final match in results.matches.take(8)) '- ${askodoxOptionContext(match)}',
      ].join('\n');

  /// "Ask ASKODOX about this": keeps the user in the AI conversation about
  /// one option (price, distance, condition, reviews, availability). Only
  /// after this can the option's Send request / Connect be used.
  Future<void> _askAboutMatch(String? dealId, UniversalMatch match) async {
    setState(() => _actionableMatchKeys.add(_matchKey(dealId, match)));
    _pendingAiContext = 'Option the user is asking about: ${askodoxOptionContext(match)}';
    _pendingDiscussOnly = true;
    await _send(_te
        ? '"${match.title}" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు'
        : 'Tell me more about "${match.title}": price, distance, quality, availability and reviews');
  }

  void _onRequestSent(String? dealId, UniversalMatch match) {
    setState(() => _requestSentMatchKeys.add(_matchKey(dealId, match)));
    unawaited(_saveSnapshot());
  }

  // ------------------------------------------------------------- roles --

  void _switchRole(AskodoxUserRole to, {int? questionTurn}) {
    final from = ref.read(askodoxRoleProvider).active;
    ref.read(askodoxRoleProvider.notifier).setActive(to);
    setState(() {
      if (questionTurn != null) {
        _roleQuestionByTurn.remove(questionTurn);
        if (from != to) {
          _roleNoticeByTurn[questionTurn] =
              askodoxRoleChangedMessage(from, to, telugu: _te);
        }
      }
    });
    unawaited(_saveSnapshot());
  }

  void _keepRole(int questionTurn) {
    setState(() => _roleQuestionByTurn.remove(questionTurn));
    unawaited(_saveSnapshot());
  }

  // ----------------------------------------------------------- support --

  Future<void> _escalateToSupport(int assistantTurn) async {
    final assessment = _supportByTurn[assistantTurn];
    if (assessment == null) return;
    final userTurns = [for (final turn in _turns.take(assistantTurn)) if (turn.isUser) turn.text];
    final issue = userTurns.lastWhere(askodoxLooksLikeIssue,
        orElse: () => userTurns.isEmpty ? 'Support requested' : userTurns.last);
    final deal = ref.read(universalDealControllerProvider).deal;
    final latest = _latestResults();
    String? counterpart;
    for (final match in latest?.matches ?? const <UniversalMatch>[]) {
      if (_requestSentMatchKeys.contains(_matchKey(latest?.dealId, match)) ||
          _actionableMatchKeys.contains(_matchKey(latest?.dealId, match))) {
        counterpart = match.title;
        break;
      }
    }
    final session = ref.read(authSessionProvider);
    final supportCase = await ref.read(askodoxSupportEscalationServiceProvider).escalate(
          issue: issue,
          category: assessment.category,
          critical: assessment.critical,
          conversation: [
            for (final turn in _turns.take(assistantTurn + 1))
              {'role': turn.isUser ? 'user' : 'assistant', 'text': turn.text},
          ],
          requirement: deal == null
              ? const {}
              : {
                  'subject': deal.subject,
                  'category': deal.category,
                  'intent': deal.intent.name,
                  'quantity': deal.quantity,
                  'unit': deal.unit,
                  'price': deal.price,
                  'location': deal.location.label,
                  ...deal.dynamicFields,
                },
          dealId: latest?.dealId,
          counterpart: counterpart,
          actionsTried: [
            for (final turn in _turns.take(assistantTurn + 1))
              if (!turn.isUser) 'ASKODOX AI: ${turn.text}',
          ].reversed.take(5).toList().reversed.toList(),
          status: _conversationStatus.name,
          activeRole: askodoxUserRoleLabel(ref.read(askodoxRoleProvider).active),
          locale: _te ? 'te' : 'en',
          authToken: session.user == null ? null : session.tokenPlaceholder,
        );
    if (!mounted) return;
    if (supportCase == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_te
            ? 'సపోర్ట్‌ను చేరుకోలేకపోయాం. మళ్లీ ప్రయత్నించండి.'
            : 'Could not reach ASKODOX Support. Please try again.'),
      ));
      return;
    }
    setState(() => _supportCaseByTurn[assistantTurn] = supportCase);
  }

  Future<void> _openExternal(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    try {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Saves a completed "sell" deal as a real, searchable listing (via the
  /// self-service `/api/products/mine` endpoint) instead of only running a
  /// buyer-style search against it. Returns a user-facing confirmation or
  /// error message plus whether it represents a failure.
  Future<(String?, bool)> _createRealListing(UniversalDeal deal) async {
    try {
      final result =
          await ref.read(sellerListingRepositoryProvider).createListing(deal);
      if (result.success) {
        final subject = deal.subject ?? '';
        return (
          _te
              ? '“$subject” ఇప్పుడు లైవ్‌లో ఉంది -- కొనుగోలుదారులు దీన్ని ఇప్పుడు వెతికి కనుగొనవచ్చు.'
              : '“$subject” is now live -- buyers can search and find it right now.',
          false,
        );
      }
      return (
        result.message ??
            (_te
                ? 'లిస్టింగ్ సేవ్ చేయడం సాధ్యం కాలేదు.'
                : 'Unable to save this listing.'),
        true,
      );
    } catch (_) {
      return (
        _te
            ? 'లిస్టింగ్ సేవ్ చేయడం సాధ్యం కాలేదు.'
            : 'Unable to save this listing.',
        true
      );
    }
  }

  Future<AskodoxChatResults> _findUniversalMatches(
    UniversalDeal deal,
  ) async {
    try {
      final result = await ref
          .read(universalMatchRepositoryProvider)
          .createAndMatch(deal);
      final matches = [...result.matches]
        ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
      // Only real rows. With none, the chat says so (searched: true) --
      // never placeholder "Search online for …" cards.
      return AskodoxChatResults(
        dealId: result.dealId,
        matches: matches,
        sourceStatus: result.sourceStatus,
        searched: true,
      );
    } on DealNeedsDetailsException catch (error) {
      if (error.missingFields.isNotEmpty) {
        return AskodoxChatResults(missingFields: error.missingFields);
      }
      // 422 with nothing missing: the request could not be published, so
      // no search ran. Offer a retry rather than fake results.
      return const AskodoxChatResults(failed: true);
    } catch (error) {
      final signInRequired =
          error.toString().toLowerCase().contains('sign in');
      // Keep the real seller catalog useful for signed-out commerce searches
      // while universal backend matching is unavailable.
      final query = (_lastGoodProductQuery ?? deal.subject ?? '').trim();
      var local = const <UniversalMatch>[];
      if (deal.intent == DealIntent.buy && query.isNotEmpty) {
        local = await ref
            .read(askodoxRealProductMatchServiceProvider)
            .search(query);
      }
      return AskodoxChatResults(
        matches: local,
        failed: !signInRequired && local.isEmpty,
        signInRequired: signInRequired && local.isEmpty,
      );
    }
  }

  Future<void> _retryMatching(int turnIndex) async {
    final deal = _dealByTurn[turnIndex];
    if (deal == null || _sending) return;
    setState(() => _sending = true);
    final results = await _findUniversalMatches(deal);
    if (!mounted) return;
    setState(() {
      _resultsByTurn[turnIndex] = results;
      _sending = false;
    });
    unawaited(_saveSnapshot());
  }

  Future<void> _send([String? preset, bool speakResponse = false]) async {
    final attachment = _attachment;
    var text = (preset ?? _controller.text).trim();
    if (_sending ||
        (text.isEmpty && attachment == null && _attachmentLabel == null)) {
      return;
    }
    text = text.isEmpty ? 'Please inspect this attachment and help me.' : text;
    if (!speakResponse) unawaited(_stopSpeaking());

    if (attachment != null && !_isVideoAttachment(attachment)) {
      final analysis = await ref.read(askodoxVisionServiceProvider).analyze(
        image: attachment,
        userText: text,
        language: _te ? 'te' : 'en',
      );
      if (analysis == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'ఫోటోను విశ్లేషించలేకపోయాం. అటాచ్‌మెంట్ అలాగే ఉంది; మళ్లీ ప్రయత్నించండి.'
              : 'Photo analysis failed. The attachment is still here; please try again.'),
        ));
        return;
      }
      text = askodoxAttachmentRequest(
          text, analysis['summary'] ?? analysis['text']);
    } else if (attachment != null) {
      final analysis = await const VideoAnalysisService().analyze(
        video: attachment,
        userText: text,
        language: _te ? 'te' : 'en',
      );
      if (analysis == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'వీడియోను విశ్లేషించలేకపోయాం. అటాచ్‌మెంట్ అలాగే ఉంది; మళ్లీ ప్రయత్నించండి.'
              : 'Video analysis failed. The attachment is still here; please try again.'),
        ));
        return;
      }
      text = const VideoAnalysisService().combinedRequest(
        userText: text,
        visualSummary: analysis['visual_summary']?.toString(),
        spokenTranscript: analysis['spoken_transcript']?.toString(),
      );
    }

    setState(() {
      _sending = true;
      _active = true;
      _listingBanner = null;
      _listingBannerIsError = false;
      _turns.add(ConversationTurnRecord(
        text: _attachmentLabel == null ? text : '$text\n[Attachment: $_attachmentLabel]',
        isUser: true,
      ));
    });
    _controller.clear();
    _attachment = null;
    _attachmentPreviewBytes = null;
    _attachmentLabel = null;
    _scrollBottom();

    final history = _turns
        .take(_turns.length - 1)
        .map((turn) => InAppAssistantTurn(
              role: turn.isUser ? 'user' : 'assistant',
              text: turn.text,
            ))
        .toList(growable: false);

    // Resolve the saved/default location before asking the AI so it can be
    // told a location is already known and should not be asked for again.
    final locationState = ref.read(locationControllerProvider);
    final selectedLocation = locationState.defaultLocation;
    final knownLocationLabel = selectedLocation == null
        ? null
        : (selectedLocation.address.trim().isNotEmpty
            ? selectedLocation.address.trim()
            : selectedLocation.name.trim());

    final userTurnIndex = _turns.length - 1;

    // AI-first: questions about options already shown ("which is better?",
    // "reviews?") and requests for the seller ("contact the seller", "book
    // it") stay in the AI conversation instead of starting a new search.
    final latestResults = _latestResults();
    final explicitContext = _pendingAiContext;
    final wantsHuman = latestResults != null &&
        latestResults.hasLocal &&
        askodoxWantsHumanAction(text);
    final discussOnly = _pendingDiscussOnly ||
        wantsHuman ||
        (latestResults != null && askodoxIsResultsQuestion(text));
    _pendingAiContext = null;
    _pendingDiscussOnly = false;

    // The answer to a pending clarification refines the need, then the
    // normal flow continues (questions → matching).
    final pendingClarification = _pendingClarification;
    AskodoxClarificationOption? clarified;
    if (pendingClarification != null && !discussOnly) {
      clarified = askodoxResolveClarification(pendingClarification, text);
      _pendingClarification = null;
      if (clarified != null) _clarifiedKeys.add(pendingClarification.key);
    }
    final aiMessage = explicitContext != null
        ? '$text\n$explicitContext'
        : discussOnly && latestResults != null
            ? '$text\nOptions already shown to the user:\n${_resultsContext(latestResults)}'
            : text;
    if (wantsHuman) {
      setState(() {
        for (final match in latestResults.local) {
          _actionableMatchKeys.add(_matchKey(latestResults.dealId, match));
        }
      });
    }

    // First-line support: count problem messages so escalation is offered
    // only after ASKODOX AI tried (or at once for critical issues).
    final support = askodoxAssessSupport(text, previousIssueTurns: _issueTurns);
    if (askodoxLooksLikeIssue(text)) {
      _issueTurns++;
    } else if (AskodoxHomeRequestRouting.isTransactional(text)) {
      _issueTurns = 0; // back to normal commerce: the problem is behind us
    }

    final decision = await ref.read(askodoxAssistantServiceProvider).decide(
      message: aiMessage,
      locale: _te ? 'te' : 'en',
      history: history,
      location: knownLocationLabel,
    );
    final aiUsable = decision?.usable == true;
    // A short answer such as "curry cut", "1 kg" or "skinless" is not
    // transactional on its own, but it *is* transactional when ASKODOX is
    // already collecting details for an unfinished commerce request. Do not
    // let the assistant classifier drop that active deal and strand the user
    // in general chat just before matching. A real aside (a question or a
    // longer general message) still goes to general chat, and the unfinished
    // deal is kept so the user can resume it.
    final activeDealSession = ref.read(universalDealControllerProvider);
    final continuingActiveDeal =
        activeDealSession.deal != null && !activeDealSession.completed;
    final detailAnswer = !discussOnly &&
        clarified == null &&
        continuingActiveDeal &&
        AskodoxHomeRequestRouting.isShortDetailAnswer(text);
    final transactional = !discussOnly &&
        (clarified != null ||
            detailAnswer ||
            (aiUsable
                ? decision!.transactional
                : AskodoxHomeRequestRouting.isTransactional(text)));
    final routedText =
        aiUsable ? AskodoxSemanticDealInput.build(text, decision!) : text;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    AskodoxChatResults? results;
    UniversalDeal? matchedDeal;
    String? detailQuestion;
    AskodoxClarification? needClarification;
    String? roleNotice;
    AskodoxUserRole? roleQuestion;
    String? listingBanner;
    var listingBannerIsError = false;

    if (transactional) {
      final session = ref.read(universalDealControllerProvider);
      final shouldStartFresh = AskodoxHomeRequestRouting.shouldStartFresh(
        session.deal?.rawText,
        routedText,
      );

      if (clarified != null) {
        notifier.refineSubject(clarified.subject);
      } else if (detailAnswer) {
        // The user's own words, not the AI rewrite: a rewrite like
        // "i want to buy 1 kg" would look like a new retail request and
        // restart (drop) the active chicken deal.
        notifier.answer(text);
      } else if (shouldStartFresh && session.deal != null) {
        _lastGoodProductQuery = null;
        notifier.reset();
        notifier.start(routedText);
      } else if (session.deal == null || session.completed) {
        _lastGoodProductQuery = null;
        notifier.start(routedText);
      } else {
        notifier.answer(routedText);
      }

      if (selectedLocation != null) {
        notifier.applySelectedLocation(
          label: knownLocationLabel ?? '',
          latitude: selectedLocation.point.latitude,
          longitude: selectedLocation.point.longitude,
          radiusKm: locationState.radiusMetres / 1000,
        );
      }

      // Real seller-backed search replaces the old DemoNaturalMatchCatalog
      // sandbox data. `readyToMatch` keeps the same "don't show anything
      // until the request is actually understood" gate the demo catalog
      // used internally, now applied explicitly here.
      final dealSession = ref.read(universalDealControllerProvider);
      final deal = dealSession.deal;
      if (deal != null) {
        _trackSearchQuery(deal.subject ?? deal.category);
        _lastIntent = deal.intent;
        // Understand the actual product first: a genuinely ambiguous need
        // gets ONE concise question instead of a guessed search.
        if (clarified == null && !detailAnswer) {
          final candidate = askodoxClarificationFor(text);
          if (candidate != null && !_clarifiedKeys.contains(candidate.key)) {
            needClarification = candidate;
          }
        }
        if (!deal.readyToMatch) detailQuestion = dealSession.lastQuestion;
      }
      if (deal != null && deal.readyToMatch && needClarification == null) {
        if (deal.intent == DealIntent.sell) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          matchedDeal = deal;
          results = await _findUniversalMatches(deal);
        }
      }
    } else if (!continuingActiveDeal && !discussOnly) {
      notifier.reset();
    }

    // Dynamic active role: follows what the user is doing now. A clear
    // switch is applied and announced; an ambiguous, high-impact one is
    // asked first. Stored roles are never changed here.
    if (!discussOnly && !detailAnswer) {
      final detection = askodoxDetectRole(text);
      final dealRole = transactional
          ? askodoxRoleForIntent(ref.read(universalDealControllerProvider).deal?.intent ?? DealIntent.other)
          : null;
      // What people say about themselves ("I repair ACs") beats a
      // demand-side intent guess from a keyword like "repair".
      final detected = detection != null && detection.role != AskodoxUserRole.buyer
          ? detection.role
          : dealRole ?? detection?.role;
      final current = ref.read(askodoxRoleProvider).active;
      // A general (non-commerce) "I need ..." is not a buying intent.
      final generalBuyerHint = !transactional && detected == AskodoxUserRole.buyer;
      if (detected != null && detected != current && !generalBuyerHint) {
        final ambiguous = (detection?.ambiguous ?? false) ||
            (detection == null && aiUsable && decision!.confidence < 0.55);
        if (ambiguous && askodoxRoleSwitchIsHighImpact(detected)) {
          roleQuestion = detected;
        } else {
          ref.read(askodoxRoleProvider.notifier).setActive(detected);
          roleNotice = askodoxRoleChangedMessage(current, detected, telugu: _te);
        }
      }
    }

    final previous = _previousUserTurn();
    final isGeneralContinuation = !transactional &&
      previous != null &&
      (_isContinuation(text.toLowerCase()) ||
        _looksLikeGeneralFollowUp(text.toLowerCase()));
    final reply = needClarification != null
      ? (_te ? needClarification.teluguQuestion : needClarification.question)
      : aiUsable &&
        !(isGeneralContinuation &&
          askodoxIsGenericAssistantReply(decision!.reply))
      ? decision!.reply.trim()
      : wantsHuman
        ? askodoxHumanActionReply(telugu: _te)
      : discussOnly && explicitContext != null
        ? askodoxOptionReply(explicitContext.split(': ').skip(1).join(': '), telugu: _te)
      : isGeneralContinuation
        ? askodoxContinuationReply(
          previousUserTurn: previous,
          telugu: _te,
          )
        : detailQuestion != null && detailQuestion.trim().isNotEmpty
          ? askodoxDetailQuestionReply(detailQuestion, telugu: _te)
          : results != null
            ? askodoxResultsReply(results, telugu: _te)
            : _fallbackAssistantReply(text, _te);

    if (!mounted) return;
    setState(() {
      if (roleNotice != null) _roleNoticeByTurn[userTurnIndex] = roleNotice;
      if (roleQuestion != null) _roleQuestionByTurn[userTurnIndex] = roleQuestion;
      _listingBanner = listingBanner;
      _listingBannerIsError = listingBannerIsError;
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      final assistantIndex = _turns.length - 1;
      if (results != null && !results.isEmpty) {
        _resultsByTurn[assistantIndex] = results;
        if (matchedDeal != null) _dealByTurn[assistantIndex] = matchedDeal;
      }
      if (support.need != AskodoxSupportNeed.none) {
        _supportByTurn[assistantIndex] = support;
      }
      if (needClarification != null) {
        _clarificationByTurn[assistantIndex] = needClarification;
        _pendingClarification = needClarification;
      }
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(reply, userText: text);
  }

  /// Speaks the reply with the existing Sarvam Bulbul v3 pipeline
  /// (backend `/api/in-app/voice/speak`); only when Sarvam is unavailable or
  /// the device cannot play its audio does it fall back to device TTS.
  Future<void> _speakReply(String reply, {required String userText}) async {
    final language = askodoxSpeechLanguage(
      reply: reply,
      userText: userText,
      uiTelugu: _te,
    );
    if (mounted) setState(() => _voicePhase = _VoicePhase.speaking);
    try {
      final audio = await ref
          .read(askodoxReplySpeechServiceProvider)
          .sarvamAudio(reply, locale: language);
      if (!mounted || _voicePhase != _VoicePhase.speaking) return;
      if (audio != null) {
        final played = await _device.invokeMethod<bool>(
          'playReplyAudio',
          <String, Object?>{'bytes': audio, 'languageCode': language},
        );
        if (played == true) {
          lastReplyVoiceEngine = 'sarvam_bulbul_v3';
          return;
        }
      }
      if (!mounted || _voicePhase != _VoicePhase.speaking) return;
      lastReplyVoiceEngine = 'device';
      await _device.invokeMethod<bool>(
        'speakReply',
        <String, Object?>{
          'text': reply,
          'languageCode': language,
          'voicePreference': ref.read(appSettingsProvider).voicePreference.storageValue,
        },
      );
    } catch (_) {
      // The text reply remains available when no voice output works.
    } finally {
      if (mounted && _voicePhase == _VoicePhase.speaking) {
        setState(() => _voicePhase = _VoicePhase.idle);
      }
    }
  }


  bool _isVideoAttachment(XFile file) {
    final mime = file.mimeType?.toLowerCase() ?? '';
    final name = file.name.toLowerCase();
    return mime.startsWith('video/') ||
        name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.m4v') ||
        name.endsWith('.webm');
  }

  String _fallbackAssistantReply(String text, bool te) {
    final q = text.toLowerCase();
    if (_has(q, ['job', 'jobs', 'ఉద్యోగం', 'జాబ్', 'computer operator'])) {
      return te
          ? 'మీరు ఉద్యోగం కోసం చూస్తున్నారు. మీ అవసరానికి సరిపోయే స్థానిక ఉద్యోగ అవకాశాలను చూపిస్తున్నాను.'
          : 'You’re looking for a job. I’m showing local openings that match your request.';
    }
    if (_has(q, [
      'ac repair',
      'repair',
      'service provider',
      'plumber',
      'electrician',
      'మెకానిక్',
      'రిపేర్',
      'సర్వీస్ కావాలి'
    ])) {
      return te
          ? 'మీకు సర్వీస్ ప్రొవైడర్ కావాలి. దగ్గరలో అందుబాటులో ఉన్న సరైన ప్రొవైడర్లను చూపిస్తున్నాను.'
          : 'You need a service provider. Here are relevant nearby providers available to help.';
    }
    if (_has(q, ['ride', 'carpool', 'driver', 'passenger', 'రైడ్'])) {
      return te
          ? 'మీ రైడ్ అవసరాన్ని అర్థం చేసుకున్నాను. సరిపోయే డ్రైవర్ లేదా రైడ్ ఆప్షన్లను చూపిస్తున్నాను.'
          : 'I understand your ride request. Here are matching driver and ride options.';
    }
    if (_has(q, ['parcel', 'delivery', 'courier', 'పార్సెల్', 'డెలివరీ'])) {
      return te
          ? 'మీ పార్సెల్ లేదా డెలివరీ అవసరానికి సరిపోయే ఆప్షన్లను చూపిస్తున్నాను.'
          : 'Here are delivery and courier options that match your request.';
    }
    if (_has(q, ['chicken', 'చికెన్', 'కోడి', 'mutton', 'మటన్', 'meat'])) {
      return te
          ? 'మీకు చికెన్ లేదా మాంసం కావాలి. దగ్గరలో ఉన్న సంబంధిత విక్రేతలను మాత్రమే చూపిస్తున్నాను.'
          : 'You’re looking for chicken or meat. I’m showing only relevant nearby sellers.';
    }
    if (AskodoxHomeRequestRouting.isTransactional(text)) {
      return te
          ? 'మీ లావాదేవీ అవసరాన్ని అర్థం చేసుకున్నాను. దానికి సంబంధించిన ఎంపికలను మాత్రమే చూపిస్తున్నాను.'
          : 'I understand your transactional request. I’m showing only relevant options.';
    }

    final previous = _previousUserTurn();
    if (previous != null &&
        previous.trim().isNotEmpty &&
        (_isContinuation(q) || _looksLikeGeneralFollowUp(q))) {
      return askodoxContinuationReply(
        previousUserTurn: previous,
        telugu: te,
      );
    }

    return te
        ? 'సరే. దీనిలో నేను మీకు సహాయం చేస్తాను. ముందుగా మీకు ముఖ్యమైన లక్ష్యం లేదా చేయాల్సిన పనులు ఏమిటో చెప్పండి; తెలిసిన విషయాలను మళ్లీ అడగకుండా కలిసి ప్లాన్ చేద్దాం.'
        : 'Sure. I can help with that. Tell me the main goal or tasks you want to handle, and we’ll plan it together without forcing a shopping or local-matching flow.';
  }

  bool _isContinuation(String text) => _has(text, [
        'continue',
        'continue it',
        'next',
        'same plan',
        'అదే',
        'కొనసాగించు',
        'కొనసాగిద్దాం',
        'తర్వాత',
        'తదుపరి',
      ]);

  bool _looksLikeGeneralFollowUp(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty || compact.length > 140) return false;
    return _has(compact, [
      'now',
      'what next',
      'what should i do',
      'then',
      'after that',
      'ఇప్పుడు',
      'ఏం చేయాలి',
      'ఏమి చేయాలి',
      'తర్వాత ఏం',
      'మరి',
      'అప్పుడు',
      'ఎలా',
    ]);
  }

  String? _previousUserTurn() {
    var currentUserSeen = false;
    for (var i = _turns.length - 1; i >= 0; i--) {
      final turn = _turns[i];
      if (!turn.isUser) continue;
      if (!currentUserSeen) {
        currentUserSeen = true;
        continue;
      }
      return turn.text;
    }
    return null;
  }


  bool _has(String text, List<String> words) => words.any(text.contains);

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    return ColoredBox(
        color: const Color(0xFFF9FBFF),
        child: Column(children: [
          Expanded(child: _active ? _chat(te) : _home(te)),
          _composer(te)
        ]));
  }

  Widget _home(bool te) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          const SizedBox(height: 8),
          Center(
              child: AskodoxVoiceOrb(
                onTap: _startVoice)),
          const SizedBox(height: 16),
          Text(
              te ? 'మీకు ఏ విధంగా సహాయం చేయగలను?' : 'How can I help you today?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 27, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          Text(
              te
                  ? 'ఉద్యోగం, సర్వీస్, లోకల్ కొనుగోలు, రైడ్ లేదా డెలివరీ — మీ అవసరాన్ని సహజంగా చెప్పండి.'
                  : 'Jobs, services, local buying, rides or delivery — just tell me naturally what you need.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _muted,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _quick(te ? 'ఉద్యోగం కావాలి' : 'I need a job',
                  Icons.work_outline_rounded),
              _quick(te ? 'AC రిపేర్ కావాలి' : 'I need AC repair',
                  Icons.home_repair_service_outlined),
              _quick(te ? 'చికెన్ కొనాలి' : 'Buy chicken nearby',
                  Icons.storefront_outlined),
              _quick(te ? 'పార్సెల్ పంపాలి' : 'Send a parcel',
                  Icons.local_shipping_outlined),
            ],
          ),
          // Demo profiles are fake local businesses: only ever shown in the
          // mock/sandbox build, never against the live REST backend.
          if (ref.watch(appConfigProvider).backendProvider ==
              BackendProvider.mock) ...[
          const SizedBox(height: 24),
          Row(children: [
            Text(te ? 'డెమో లోకల్ ప్రొఫైల్స్' : 'Demo local profiles',
                style: const TextStyle(
                    color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFFEDEBFF),
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('DEMO',
                    style: TextStyle(
                        color: Color(0xFF5B4BFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 154,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _DemoProfileCard(
                    name: te ? 'శ్రీ మొబైల్స్' : 'Sri Mobiles',
                    category: te ? 'మొబైల్ విక్రేత' : 'Mobile seller',
                    meta: '★ 4.8  •  1.2 km',
                    icon: Icons.smartphone_rounded,
                    onTap: () => _send(te
                        ? 'నాకు మొబైల్ కొనాలి'
                        : 'I want to buy a mobile phone')),
                _DemoProfileCard(
                    name: te ? 'రవి AC సర్వీస్' : 'Ravi AC Service',
                    category: te ? 'AC టెక్నీషియన్' : 'AC technician',
                    meta: '★ 4.7  •  2.1 km',
                    icon: Icons.home_repair_service_rounded,
                    onTap: () => _send(
                        te ? 'నాకు AC రిపేర్ కావాలి' : 'I need AC repair')),
                _DemoProfileCard(
                    name: te ? 'విజయ జాబ్స్' : 'Vijaya Jobs',
                    category: te ? 'స్థానిక ఉద్యోగదాత' : 'Local employer',
                    meta: '★ 4.6  •  3 openings',
                    icon: Icons.badge_rounded,
                    onTap: () =>
                        _send(te ? 'నాకు ఉద్యోగం కావాలి' : 'I need a job')),
                _DemoProfileCard(
                    name: te ? 'సాయి డెలివరీ' : 'Sai Delivery',
                    category: te ? 'డెలివరీ రైడర్' : 'Delivery rider',
                    meta: '★ 4.9  •  0.9 km',
                    icon: Icons.local_shipping_rounded,
                    onTap: () => _send(te
                        ? 'నాకు పార్సెల్ పంపాలి'
                        : 'I need to send a parcel')),
              ],
            ),
          ),
          ],
        ],
      );

  Widget _quick(String text, IconData icon) => ActionChip(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFD7E3F5)),
        avatar: Icon(icon, size: 18, color: _blue),
        label: Text(text,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        onPressed: _sending ? null : () => _send(text),
      );

  Widget _chat(bool te) => ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          for (final (index, turn) in _turns.indexed) ...[
            Align(
              alignment:
                  turn.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 330),
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                    color: turn.isUser ? _blue : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: turn.isUser
                        ? null
                        : Border.all(color: const Color(0xFFE1E8F2))),
                child: Text(turn.text,
                    style: TextStyle(
                        color: turn.isUser ? Colors.white : _ink,
                        height: 1.35,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            if (_roleNoticeByTurn[index] case final notice?)
              _RoleNotice(text: notice),
            if (_roleQuestionByTurn[index] case final role?)
              _RoleQuestion(
                question: askodoxRoleSwitchQuestion(role, telugu: te),
                switchLabel: te ? 'మారండి' : 'Switch',
                keepLabel: te
                    ? '${askodoxUserRoleLabel(ref.watch(askodoxRoleProvider).active, telugu: true)}గానే ఉండండి'
                    : 'Stay ${askodoxUserRoleLabel(ref.watch(askodoxRoleProvider).active)}',
                onSwitch: () => _switchRole(role, questionTurn: index),
                onKeep: () => _keepRole(index),
              ),
            if (_resultsByTurn[index] case final results?)
              _ChatResultsView(
                key: ValueKey('askodoxChatResults-$index'),
                results: results,
                te: te,
                retrying: _sending,
                onRetry: _dealByTurn.containsKey(index)
                    ? () => _retryMatching(index)
                    : null,
                isActionable: (match) => _actionableMatchKeys
                    .contains(_matchKey(results.dealId, match)),
                wasRequested: (match) => _requestSentMatchKeys
                    .contains(_matchKey(results.dealId, match)),
                onAsk: _sending
                    ? null
                    : (match) => _askAboutMatch(results.dealId, match),
                onRequestSent: (match) => _onRequestSent(results.dealId, match),
              ),
            if (_clarificationByTurn[index] case final clarification?)
              if (identical(clarification, _pendingClarification) &&
                  index == _turns.length - 1)
                Padding(
                  key: const Key('askodoxClarificationOptions'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final option in clarification.options)
                      ActionChip(
                        label: Text(te ? option.teluguLabel : option.label,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        onPressed: _sending
                            ? null
                            : () => _send(te ? option.teluguLabel : option.label),
                      ),
                  ]),
                ),
            if (_supportByTurn[index] case final support?)
              _SupportCard(
                key: ValueKey('askodoxSupport-$index'),
                te: te,
                critical: support.critical,
                supportCase: _supportCaseByTurn[index],
                onChat: () => _escalateToSupport(index),
                onOpen: _openExternal,
              ),
          ],
          if (_sending)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          if (_listingBanner != null) ...[
            const SizedBox(height: 6),
            _ListingBanner(
                message: _listingBanner!, isError: _listingBannerIsError),
          ],
        ],
      );

  Widget _composer(bool te) => Container(
        padding: EdgeInsets.fromLTRB(
            10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE1E7F0)))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_voicePhase != _VoicePhase.idle) _voicePanel(te),
        if (_attachmentLabel != null) _attachmentPreview(te),
        Row(children: [
        if (_voicePhase == _VoicePhase.recording)
          IconButton(
            key: const Key('askodoxVoiceCancel'),
            onPressed: _cancelVoice,
            tooltip: te ? 'రద్దు చేయండి' : 'Cancel voice',
            icon: const Icon(Icons.close_rounded, color: _muted)),
        IconButton.filled(
          key: const Key('askodoxVoiceButton'),
          onPressed: _voicePhase == _VoicePhase.transcribing ||
                  _voicePhase == _VoicePhase.thinking
              ? null
              : _startVoice,
          tooltip: switch (_voicePhase) {
            _VoicePhase.recording => te ? 'ఆపండి' : 'Stop and send',
            _VoicePhase.transcribing => te ? 'అర్థం చేసుకుంటున్నాను…' : 'Transcribing…',
            _VoicePhase.thinking => te ? 'ఆలోచిస్తున్నాను…' : 'Thinking…',
            _VoicePhase.speaking || _VoicePhase.idle => te ? 'మాట్లాడండి' : 'Speak',
          },
          style: IconButton.styleFrom(
            backgroundColor: _voicePhase == _VoicePhase.recording
                ? const Color(0xFFE5484D)
                : _accent,
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero),
          icon: _voicePhase == _VoicePhase.transcribing ||
                  _voicePhase == _VoicePhase.thinking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _ink))
              : Icon(
                  _voicePhase == _VoicePhase.recording
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  color: _voicePhase == _VoicePhase.recording
                      ? Colors.white
                      : _ink)),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !_sending,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          cursorColor: const Color(0xFF5B4BFF),
          style: const TextStyle(
            color: _ink, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
          hintText:
            te ? 'మీకు ఏమి కావాలో చెప్పండి…' : 'Tell me what you need…',
          hintStyle: const TextStyle(
            color: Color(0xFF7B8496), fontWeight: FontWeight.w500),
          filled: true,
          fillColor: const Color(0xFFF8F9FC),
          contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: const BorderSide(
              color: Color(0xFFDDD9FF), width: 1.5)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: const BorderSide(
              color: Color(0xFF6C4DFF), width: 2)),
          ),
        )),
        IconButton(
          onPressed: _showAttachmentMenu,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          tooltip: te ? 'జోడించండి' : 'Add attachment',
          icon: const Icon(Icons.add_circle_outline_rounded, color: _ink)),
        IconButton.filled(
          onPressed: _sending ? null : _send,
          style: IconButton.styleFrom(
            backgroundColor: _blue,
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero),
          icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white)),
        ]),
      ]),
      );

  /// Proof ASKODOX is hearing: a pulsing mic and level bars driven by the
  /// real microphone amplitude, elapsed time, status and a separate Stop.
  Widget _voicePanel(bool te) {
    final listening = _voicePhase == _VoicePhase.recording;
    final current = _voiceLevels.isEmpty ? 0.0 : _voiceLevels.last;
    final elapsed = _voiceSampleInterval * _voiceTicks;
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final status = switch (_voicePhase) {
      _VoicePhase.recording => te ? 'వింటున్నాను…' : 'Listening…',
      _VoicePhase.transcribing => te ? 'అర్థం చేసుకుంటున్నాను…' : 'Understanding…',
      _VoicePhase.thinking => te ? 'ఆలోచిస్తున్నాను…' : 'Thinking…',
      _VoicePhase.speaking => te ? 'మాట్లాడుతున్నాను…' : 'Speaking…',
      _VoicePhase.idle => '',
    };
    return Container(
      key: const Key('askodoxVoicePanel'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
          color: const Color(0xFFF2F0FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDDD9FF))),
      child: Row(children: [
        AnimatedScale(
          key: const Key('askodoxVoicePulse'),
          scale: listening ? 1 + current * 0.45 : 1,
          duration: const Duration(milliseconds: 180),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: listening ? const Color(0xFFE5484D) : const Color(0xFF6C4DFF),
            child: Icon(
                _voicePhase == _VoicePhase.speaking
                    ? Icons.volume_up_rounded
                    : Icons.mic_rounded,
                color: Colors.white,
                size: 20),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(status,
                  key: const Key('askodoxVoiceStatus'),
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
              if (listening) ...[
                const Spacer(),
                Text('$mm:$ss',
                    key: const Key('askodoxVoiceElapsed'),
                    style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
              ],
            ]),
            if (listening) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 30,
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  for (var i = 0; i < _voiceLevelBars; i++)
                    Expanded(
                      child: Center(
                        child: AnimatedContainer(
                          key: ValueKey('askodoxLevelBar-$i'),
                          duration: const Duration(milliseconds: 150),
                          width: 3,
                          height: 3 + 27 * _barLevel(i),
                          decoration: BoxDecoration(
                              color: const Color(0xFF6C4DFF),
                              borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 6),
        if (listening)
          FilledButton.icon(
            key: const Key('askodoxVoiceStop'),
            onPressed: () => _finishVoice(noSpeech: false),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
            icon: const Icon(Icons.stop_rounded),
            label: Text(te ? 'ఆపండి' : 'Stop'),
          )
        else if (_voicePhase == _VoicePhase.speaking)
          TextButton(
            key: const Key('askodoxStopSpeaking'),
            onPressed: _stopSpeaking,
            child: Text(te ? 'ఆపండి' : 'Stop'),
          ),
      ]),
    );
  }

  /// Level for bar [i]; the newest sample is the right-most bar.
  double _barLevel(int i) {
    final offset = _voiceLevelBars - _voiceLevels.length;
    final index = i - offset;
    return index < 0 ? 0 : _voiceLevels[index];
  }

    Widget _attachmentPreview(bool te) => Container(
      key: const Key('askodoxAttachmentPreview'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E3F5))),
        child: Row(children: [
        if (_attachmentPreviewBytes != null && !_isVideoName(_attachmentLabel))
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(_attachmentPreviewBytes!,
            width: 48, height: 48, fit: BoxFit.cover))
        else
          SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              _isVideoName(_attachmentLabel)
                  ? Icons.video_file_outlined
                  : Icons.insert_drive_file_outlined,
              color: _blue,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_attachmentLabel!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink, fontWeight: FontWeight.w700))),
        IconButton(
          tooltip: te ? 'తొలగించండి' : 'Remove attachment',
          onPressed: _sending
            ? null
            : () => setState(() {
              _attachment = null;
              _attachmentPreviewBytes = null;
              _attachmentLabel = null;
              }),
          icon: const Icon(Icons.close_rounded, color: _muted)),
      ]),
      );

  bool _isVideoName(String? name) {
    final value = (name ?? '').toLowerCase();
    return value.endsWith('.mp4') ||
        value.endsWith('.mov') ||
        value.endsWith('.m4v') ||
        value.endsWith('.webm');
  }

  @override
  void dispose() {
    _stopVoiceTimer();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _DemoProfileCard extends StatelessWidget {
  const _DemoProfileCard(
      {required this.name,
      required this.category,
      required this.meta,
      required this.icon,
      required this.onTap});
  final String name;
  final String category;
  final String meta;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE6F4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFEAF2FF),
                child: Icon(icon, color: _blue, size: 21)),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFF2F0FF),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('DEMO',
                    style: TextStyle(
                        color: Color(0xFF5B4BFF),
                        fontSize: 9,
                        fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 10),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _ink, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(meta,
              style: const TextStyle(
                  color: _ink, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _ListingBanner extends StatelessWidget {
  const _ListingBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB3261E) : const Color(0xFF1B8A3B);
    final background =
        isError ? const Color(0xFFFDECEA) : const Color(0xFFE9F7EE);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, height: 1.3))),
      ]),
    );
  }
}

class _RoleNotice extends StatelessWidget {
  const _RoleNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: Container(
          key: const Key('askodoxRoleNotice'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0xFFEDEBFF),
              borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.swap_horiz_rounded,
                size: 16, color: Color(0xFF5B4BFF)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFF3B2FCC),
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

/// Rich result cards embedded directly under an assistant reply -- local
/// matches first, then online options, then videos. Not a separate page.
class _RoleQuestion extends StatelessWidget {
  const _RoleQuestion({
    required this.question,
    required this.switchLabel,
    required this.keepLabel,
    required this.onSwitch,
    required this.onKeep,
  });

  final String question;
  final String switchLabel;
  final String keepLabel;
  final VoidCallback onSwitch;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: Container(
          key: const Key('askodoxRoleQuestion'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
              color: const Color(0xFFEDEBFF),
              borderRadius: BorderRadius.circular(14)),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(question,
                  style: const TextStyle(
                      color: Color(0xFF3B2FCC), fontWeight: FontWeight.w800)),
              TextButton(onPressed: onSwitch, child: Text(switchLabel)),
              TextButton(onPressed: onKeep, child: Text(keepLabel)),
            ],
          ),
        ),
      );
}

/// "Need more help? Contact ASKODOX Support" -- shown only after ASKODOX AI
/// tried (or at once for critical issues). The case carries the whole
/// conversation so the user never repeats themselves.
class _SupportCard extends StatefulWidget {
  const _SupportCard({
    super.key,
    required this.te,
    required this.critical,
    required this.onChat,
    required this.onOpen,
    this.supportCase,
  });

  final bool te;
  final bool critical;
  final AskodoxSupportCase? supportCase;
  final Future<void> Function() onChat;
  final Future<void> Function(String uri) onOpen;

  @override
  State<_SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<_SupportCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final supportCase = widget.supportCase;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: widget.critical ? const Color(0xFFFFF1F0) : const Color(0xFFF2F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: widget.critical ? const Color(0xFFFFC9C4) : const Color(0xFFD7E3F5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.support_agent_rounded, color: _blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                te ? 'ఇంకా సహాయం కావాలా? ASKODOX సపోర్ట్‌ను సంప్రదించండి'
                    : 'Need more help? Contact ASKODOX Support',
                style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 8),
        if (supportCase == null)
          FilledButton.icon(
            key: const Key('askodoxSupportChat'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await widget.onChat();
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.chat_rounded),
            label: Text(te ? 'సపోర్ట్‌తో చాట్ చేయండి' : 'Chat with Support'),
          )
        else ...[
          Text(
            te
                ? 'సపోర్ట్ కేసు #${supportCase.caseId} సృష్టించబడింది. మీ సంభాషణ మొత్తం వారికి చేరింది -- మళ్లీ వివరించాల్సిన అవసరం లేదు.'
                : 'Support case #${supportCase.caseId} created. ASKODOX Support has this whole conversation -- no need to explain again.',
            key: const Key('askodoxSupportCaseCreated'),
            style: const TextStyle(color: Color(0xFF1B8A3B), fontWeight: FontWeight.w700),
          ),
          Wrap(spacing: 8, children: [
            if (supportCase.whatsappUrl case final url?)
              OutlinedButton.icon(
                onPressed: () => widget.onOpen(url),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(te ? 'వాట్సాప్ సపోర్ట్' : 'WhatsApp Support'),
              ),
            if (supportCase.callUri case final uri?)
              OutlinedButton.icon(
                onPressed: () => widget.onOpen(uri),
                icon: const Icon(Icons.call_rounded),
                label: Text(te ? 'సపోర్ట్‌కు కాల్' : 'Call Support'),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Rich result cards embedded directly under an assistant reply, grouped by
/// source (ASKODOX sellers, individual, used, surplus, deals, nearby shops,
/// online, videos). Not a separate page; empty sections are never shown.
class _ChatResultsView extends StatelessWidget {
  const _ChatResultsView({
    super.key,
    required this.results,
    required this.te,
    required this.retrying,
    required this.isActionable,
    required this.wasRequested,
    required this.onRequestSent,
    this.onAsk,
    this.onRetry,
  });

  final AskodoxChatResults results;
  final bool te;
  final bool retrying;
  final VoidCallback? onRetry;
  final bool Function(UniversalMatch match) isActionable;
  final bool Function(UniversalMatch match) wasRequested;
  final void Function(UniversalMatch match)? onAsk;
  final void Function(UniversalMatch match) onRequestSent;

  @override
  Widget build(BuildContext context) {
    final hasLocal = results.hasLocal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (results.failed)
          _notice(
            key: const Key('askodoxResultsFailed'),
            icon: Icons.cloud_off_rounded,
            text: te
                ? 'మ్యాచింగ్ ఇప్పుడు అందుబాటులో లేదు.'
                : 'Matching is unavailable right now.',
            action: onRetry == null
                ? null
                : TextButton.icon(
                    key: const Key('askodoxResultsRetry'),
                    onPressed: retrying ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(te ? 'మళ్లీ ప్రయత్నించండి' : 'Retry'),
                  ),
          ),
        if (results.signInRequired)
          _notice(
            key: const Key('askodoxResultsSignIn'),
            icon: Icons.lock_outline_rounded,
            text: te
                ? 'స్థానిక అభ్యర్థనలు పంపడానికి సైన్ ఇన్ చేయండి.'
                : 'Sign in to send requests to local sellers and providers.',
          ),
        if (results.searched && results.matches.isEmpty)
          _notice(
            key: const Key('askodoxResultsNone'),
            icon: Icons.search_off_rounded,
            text: te
                ? 'ASKODOX విక్రేతలు, దగ్గరలోని షాపులు, ఆన్‌లైన్ లేదా వీడియోల్లో ఇంకా నిజమైన ఫలితాలు దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను.'
                : 'No real results yet from ASKODOX sellers, nearby shops, online stores or videos. I saved your need.',
          ),
        for (final (segment, rows) in askodoxGroupResults(results.matches)) ...[
          _heading(askodoxSegmentTitle(segment, telugu: te, hasLocal: hasLocal),
              _segmentIcon(segment)),
          for (final match in rows)
            _MatchCard(
              match: match,
              dealId: results.dealId,
              te: te,
              actionable: isActionable(match),
              alreadySent: wasRequested(match),
              onAsk: onAsk == null ? null : () => onAsk!(match),
              onRequestSent: () => onRequestSent(match),
            ),
        ],
        if (_sourceNote(te) case final note?)
          Padding(
            key: const Key('askodoxSourceStatus'),
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(note,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.3)),
          ),
      ]),
    );
  }

  /// One honest line about sources that returned nothing or are down, so
  /// no section is ever faked.
  String? _sourceNote(bool te) {
    String label(String key) => switch (key) {
          'askodox' => te ? 'ASKODOX విక్రేతలు' : 'ASKODOX sellers',
          'nearby' => te ? 'దగ్గరలోని షాపులు' : 'nearby shops',
          'used_deals' => te ? 'వాడినవి / డీల్స్' : 'used & deals',
          'online' => te ? 'ఆన్‌లైన్ స్టోర్లు' : 'online stores',
          'videos' => te ? 'వీడియోలు' : 'videos',
          _ => key,
        };
    final none = results.sourcesWith('no_results').map(label).toList();
    final down = results.sourcesWith('unavailable').map(label).toList();
    if (none.isEmpty && down.isEmpty) return null;
    final parts = [
      if (none.isNotEmpty) (te ? 'ఫలితాలు లేవు: ' : 'No results from: ') + none.join(', '),
      if (down.isNotEmpty) (te ? 'ప్రస్తుతం అందుబాటులో లేదు: ' : 'Not available right now: ') + down.join(', '),
    ];
    return parts.join(' · ');
  }

  IconData _segmentIcon(AskodoxResultSegment segment) => switch (segment) {
        AskodoxResultSegment.askodoxMatches ||
        AskodoxResultSegment.registered =>
          Icons.verified_rounded,
        AskodoxResultSegment.individual => Icons.person_rounded,
        AskodoxResultSegment.used => Icons.recycling_rounded,
        AskodoxResultSegment.surplus => Icons.inventory_2_rounded,
        AskodoxResultSegment.deals => Icons.local_offer_rounded,
        AskodoxResultSegment.nearbyExternal ||
        AskodoxResultSegment.widerLocal =>
          Icons.near_me_rounded,
        AskodoxResultSegment.online => Icons.public_rounded,
        AskodoxResultSegment.video => Icons.play_circle_outline_rounded,
      };

  Widget _heading(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, color: _ink)),
          ),
        ]),
      );

  Widget _notice({
    required Key key,
    required IconData icon,
    required String text,
    Widget? action,
  }) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD8A8))),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF9A5B00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFF7A4A00), fontWeight: FontWeight.w700)),
          ),
          if (action != null) action,
        ]),
      );
}

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({
    required this.match,
    required this.te,
    required this.onRequestSent,
    this.dealId,
    this.actionable = false,
    this.alreadySent = false,
    this.onAsk,
  });
  final UniversalMatch match;
  final String? dealId;
  final bool te;

  /// AI-first: Send request / Connect is exposed only once the user has
  /// discussed this option with ASKODOX or asked for the seller.
  final bool actionable;
  final bool alreadySent;
  final VoidCallback? onAsk;
  final VoidCallback onRequestSent;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  bool _placing = false;
  bool _orderFailed = false;
  String? _orderStatusMessage;

  UniversalMatch get _match => widget.match;
  bool get _te => widget.te;
  ChatResultAction get _action => chatResultActionFor(_match);

  /// Videos play inside ASKODOX; back returns to this exact chat position.
  Future<void> _openVideo() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => AskodoxVideoViewerScreen(video: _match, telugu: _te),
    ));
    if (result == askodoxVideoAskResult) widget.onAsk?.call();
  }

  Future<void> _openDestination() async {
    final raw = _match.destinationUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    var opened = false;
    try {
      opened = uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_te
            ? 'లింక్ తెరవడం సాధ్యం కాలేదు.'
            : 'This destination could not be opened.'),
      ));
    }
  }

  /// Party A asks this Party B to connect (existing consent-first
  /// `/deals/{id}/accept-match` flow). Contact stays hidden until both
  /// sides have accepted.
  Future<OrderActionResult> _connect() async {
    final dealId = widget.dealId;
    if (dealId == null || dealId.isEmpty) {
      return OrderActionResult(
        success: false,
        message: _te
            ? 'ఈ అభ్యర్థనను ఇప్పుడు పంపలేము. మళ్లీ ప్రయత్నించండి.'
            : 'This request cannot be sent right now. Please retry.',
      );
    }
    await ref
        .read(universalMatchRepositoryProvider)
        .acceptMatch(dealId: dealId, matchId: _match.id);
    return const OrderActionResult(success: true);
  }

  Future<void> _sendRequest() async {
    if (_placing) return;
    setState(() {
      _placing = true;
      _orderStatusMessage = null;
      _orderFailed = false;
    });
    OrderActionResult result;
    try {
      result = _action == ChatResultAction.connect
          ? await _connect()
          : await ref
              .read(orderRepositoryProvider)
              .placeOrder(productId: _match.id);
    } catch (error) {
      final message = error is StateError ? error.message : null;
      result = OrderActionResult(
        success: false,
        message: message ??
            (_te
                ? 'అభ్యర్థన పంపడం సాధ్యం కాలేదు.'
                : 'Unable to send this request.'),
      );
    }
    if (!mounted) return;
    if (result.success) widget.onRequestSent();
    setState(() {
      _placing = false;
      _orderFailed = !result.success;
      _orderStatusMessage = result.success
          ? (_te
              ? 'అభ్యర్థన పంపబడింది. వారు అంగీకరించిన తర్వాతే ఇది నిర్ధారిత డీల్ అవుతుంది, కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
              : 'Request sent. It becomes a confirmed deal -- and contact details are shared -- only after they accept.')
          : (result.message ??
              (_te
                  ? 'అభ్యర్థన పంపడం సాధ్యం కాలేదు.'
                  : 'Unable to send this request.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final te = _te;
    final action = _action;
    final distance = match.distanceKm == null
        ? null
        : '${match.distanceKm!.toStringAsFixed(1)} km';
    final price =
        match.price == null ? null : '₹${match.price!.toStringAsFixed(0)}';
    final score = match.score == null
        ? null
        : (match.score! <= 1 ? match.score! * 100 : match.score!);
    final placed = widget.alreadySent ||
        (_orderStatusMessage != null && !_orderFailed);
    final requestable = action == ChatResultAction.connect ||
        action == ChatResultAction.sendRequest;
    final showRequest = requestable && (widget.actionable || placed);
    return Container(
      key: ValueKey('askodoxResultCard-${match.source}-${match.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (action == ChatResultAction.watchVideo &&
            match.imageUrl?.trim().isNotEmpty == true) ...[
          GestureDetector(
            key: ValueKey('askodoxVideoThumb-${match.id}'),
            onTap: _openVideo,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(match.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFF10204A))),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        size: 56, color: Colors.white),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 64,
              height: 64,
              child: _match.imageUrl?.trim().isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_match.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _sourceIcon()))
                  : _sourceIcon()),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(match.title,
                    style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w900, fontSize: 16)),
                if (match.subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(match.subtitle!,
                      style: const TextStyle(
                          color: _muted,
                          height: 1.35,
                          fontWeight: FontWeight.w500))
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _meta(_sourceLabel(_match.source)),
                  if (match.sourceName?.trim().isNotEmpty == true)
                    _meta(match.sourceName!.trim()),
                  if (match.duration?.trim().isNotEmpty == true)
                    _meta(match.duration!.trim()),
                  if (score != null) _meta('${score.toStringAsFixed(0)}% match'),
                  if (match.ratingAverage != null)
                    _meta(
                        '★ ${match.ratingAverage!.toStringAsFixed(1)} (${match.reviewCount})'),
                  if (distance != null) _meta(distance),
                  if (price != null) _meta(price),
                  if (match.locationLabel?.trim().isNotEmpty == true)
                    _meta(match.locationLabel!),
                  if (match.availability?.trim().isNotEmpty == true)
                    _meta(match.availability!),
                ]),
              ])),
        ]),
        const SizedBox(height: 12),
        if (_orderStatusMessage != null) ...[
          Text(
            _orderStatusMessage!,
            style: TextStyle(
                color: _orderFailed
                    ? const Color(0xFFB3261E)
                    : const Color(0xFF1B8A3B),
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
          const SizedBox(height: 8),
        ],
        if (requestable && !showRequest)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: ValueKey('askodoxAsk-${match.id}'),
              onPressed: widget.onAsk,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(te ? 'దీని గురించి ASKODOXని అడగండి' : 'Ask ASKODOX about this'),
            ),
          ),
        if (showRequest) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_placing || placed) ? null : _sendRequest,
              style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: _placing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      placed
                          ? (te ? 'అభ్యర్థన పంపబడింది' : 'Request sent')
                          : _orderFailed
                              ? (te ? 'మళ్లీ ప్రయత్నించండి' : 'Retry request')
                              : action == ChatResultAction.connect
                                  ? (te ? 'కనెక్ట్ అభ్యర్థన పంపండి' : 'Connect')
                                  : (te ? 'అభ్యర్థన పంపండి' : 'Send request'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: _muted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                te
                    ? 'వారు అంగీకరించే వరకు ఫోన్/కాంటాక్ట్ దాచబడి ఉంటుంది.'
                    : 'Phone/contact stays hidden until they accept.',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ]),
        ],
        if (!requestable && widget.onAsk != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: ValueKey('askodoxAsk-${match.id}'),
              onPressed: widget.onAsk,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(te ? 'దీని గురించి ASKODOXని అడగండి' : 'Ask ASKODOX about this'),
            ),
          ),
        if (match.destinationUrl?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey('askodoxOpen-${match.id}'),
              onPressed: action == ChatResultAction.watchVideo
                  ? _openVideo
                  : _openDestination,
              icon: Icon(action == ChatResultAction.watchVideo
                  ? Icons.play_arrow_rounded
                  : Icons.open_in_new_rounded),
              label: Text(action == ChatResultAction.watchVideo
                  ? (te ? 'వీడియో చూడండి' : 'Watch')
                  : action == ChatResultAction.openLink
                      ? (te ? 'తెరవండి' : 'Open')
                      : (te ? 'వివరాలు చూడండి' : 'View details')),
            ),
          ),
          if (match.disclosure?.trim().isNotEmpty == true || match.affiliate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  match.disclosure?.trim().isNotEmpty == true
                      ? match.disclosure!
                      : 'Affiliate link',
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ),
        ],
      ]),
    );
  }

  Widget _sourceIcon() => Container(
      decoration: BoxDecoration(
          color: const Color(0xFFF0EFFF),
          borderRadius: BorderRadius.circular(14)),
      child: Icon(
          switch (_action) {
            ChatResultAction.watchVideo => Icons.smart_display_rounded,
            ChatResultAction.openLink => Icons.public_rounded,
            _ => _match.source.toLowerCase() == 'nearby'
                ? Icons.near_me_rounded
                : Icons.storefront_rounded,
          },
          color: const Color(0xFF5B4BFF)));

  String _sourceLabel(String source) => switch (source.toLowerCase()) {
        'online' => _te ? 'ఆన్‌లైన్' : 'Online',
        'video' => _te ? 'వీడియో' : 'Video',
        'external' => _te ? 'దగ్గరలోని షాప్' : 'Nearby shop',
        'nearby' => _te ? 'దగ్గరలో' : 'Nearby',
        'demo_discovery' => _te ? 'డెమో' : 'Demo',
        _ => _te ? 'లోకల్' : 'Local',
      };

  Widget _meta(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFF6F7FA),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              color: _ink, fontSize: 12, fontWeight: FontWeight.w700)));
}
