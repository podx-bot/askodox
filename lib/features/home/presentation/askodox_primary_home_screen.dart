import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/environment.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../services/in_app_assistant_service.dart';
import '../../../services/real_product_match_service.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/reply_speech_service.dart';
import '../../../services/support_escalation_service.dart';
import '../../../services/voice_endpointing.dart';
import '../../../services/voice_transcription_service.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/data/listed_brands.dart';
import '../../deal_brain/domain/brand_lexicon.dart';
import '../../deal_brain/application/universal_deal_brain.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../location/application/location_controller.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../../selling/data/seller_listing_repository.dart';
import '../application/conversation_archive.dart';
import '../application/match_action_executor.dart';
import '../../companion/companion_hub.dart';
import '../application/saved_options.dart';
import '../domain/place_phrase.dart';
import '../../profile/data/user_profile_repository.dart';
import '../../selling/data/catalogue_repository.dart';
import '../../selling/domain/seller_catalogue.dart';
import '../../selling/presentation/catalogue_widgets.dart';
import '../../growth/data/growth_repository.dart';
import '../../growth/data/partner_tracking.dart';
import '../../growth/presentation/benefits_widgets.dart';
import '../../../services/chat_attachment_service.dart';
import '../../../services/media_picker.dart';
import '../../location/presentation/map_pin_picker.dart';
import '../domain/active_role.dart';
import '../domain/chat_action_intent.dart';
import '../domain/chat_result_policy.dart';
import '../domain/conversation_language.dart';
import '../domain/need_clarification.dart';
import '../domain/need_state.dart';
import '../domain/home_request_routing.dart';
import '../domain/semantic_deal_input.dart';
import '../../companion/askodox_companion.dart';
import '../../companion/companion_voice.dart';
import 'deal_lifecycle_panel.dart';
import '../data/askodox_video_service.dart';
import 'video_viewer_screen.dart';

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF667085);
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
  // A ready-made seller catalogue open in the conversation.
  AskodoxCatalogueTemplate? _catalogue;

  /// Something the user just tried failed (attachment, publish): the
  /// companion shows recovery until the next message.
  bool _companionError = false;
  final Set<String> _catalogueSelected = {};
  int? _catalogueTurn;
  DealIntent? _lastIntent;

  // History: every conversation is saved as a snapshot under this id.
  String _conversationId = _newConversationId();
  static String _newConversationId() =>
      'c-${DateTime.now().microsecondsSinceEpoch}';

  // AI-first deal flow: Send request / Connect appear on an option only
  // after the user discussed it with ASKODOX or asked for the seller.
  final Set<String> _actionableMatchKeys = {};
  final Set<String> _requestSentMatchKeys = {};

  /// The option the customer most recently asked about -- the default
  /// target of a typed "yes / order it".
  UniversalMatch? _focusedMatch;

  /// A typed "yes / order it" that needed sign-in: after the user signs in
  /// the SAME action runs (no need to repeat it).
  ({String text, AskodoxChatResults results, UniversalMatch target})? _pendingSignInAction;
  int? _signInTurn;

  /// The chosen location last applied to a deal ("lat,lng").
  String? _appliedLocationKey;

  /// A catalog draft (from photo/video/text) waiting for the seller's review.
  AskodoxCatalogDraft? _pendingDraft;

  /// Customer requests broadcast to me as a registered provider.
  List<AskodoxLead> _leads = const [];
  final Set<String> _leadReplies = {};
  /// Real orders/bookings created from this conversation (match key → id),
  /// in creation order: the deal panel and seller relay use them.
  final Map<String, String> _orderByMatchKey = {};
  /// A seller-only question asked before any request exists; it travels
  /// with the next Send request so the customer never retypes it.
  String? _pendingSellerQuestion;
  int _dealRefreshTick = 0;
  /// Each category's own unfinished requirement (subject → encoded deal):
  /// switching needs never mixes slots, and returning restores answers.
  final Map<String, Map<String, Object?>> _parkedDeals = {};
  InAppAssistantDecision? _lastDecision;
  bool _showNowAfterClarification = false;

  /// A request/order was really sent (backend confirmed) -> happy companion.
  bool _actionConfirmed = false;
  String? _lastAskedQuestion;
  List<String> _lastMissing = const [];
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
  // Real attachments waiting in the composer (bytes + MIME), analyzed by
  // the backend when sent -- never reduced to a file name.
  final List<ChatAttachment> _attachments = [];
  bool _analyzingAttachments = false;
  int _attachmentJob = 0;
  static const _maxAttachments = 4;

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

  /// The ONE conversation language (Preferred Language, else what the
  /// customer is speaking) -- replies, headings and actions all follow it.
  String get _lang => ref.read(askodoxReplyLanguageProvider);
  bool get _te => _lang == 'te';

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
    ref.read(askodoxCompanionVoiceProvider).setMicLevel(_voiceLevels.last);
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
    if (mounted) ref.read(askodoxCompanionVoiceProvider).setMicLevel(0);
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
        .transcribeFile(path, locale: _lang);
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


  /// Camera / Photos / Video / Files from the companion -> the ONE
  /// attachment pipeline (real bytes, analyzed on Send).
  Future<void> _pickAttachment(String choice) async {
    try {
      final picked = await ref.read(askodoxMediaPickerProvider).pick(choice);
      for (final attachment in picked) {
        if (!mounted || !_addAttachment(attachment)) break;
      }
    } on MultimodalCaptureException {
      if (!mounted) return;
      _attachmentNotice('attach_permission');
    } catch (_) {
      if (!mounted) return;
      _attachmentNotice('attach_open_failed');
    }
  }

  /// Adds a picked attachment; false when no more can be added.
  bool _addAttachment(ChatAttachment attachment) {
    if (attachment.bytes.isEmpty) {
      _attachmentNotice('attach_open_failed');
      return true;
    }
    if (attachment.kind == 'unsupported') {
      _attachmentNotice('attach_unsupported');
      return true;
    }
    if (_attachments.length >= _maxAttachments) {
      _attachmentNotice('attach_limit');
      return false;
    }
    setState(() => _attachments.add(attachment));
    return true;
  }

  void _attachmentNotice(String key, {VoidCallback? retry, String? diagnostic}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: ValueKey('askodoxAttachmentNotice-$key'),
      content: Text([
        askodoxChatLabel(key, _lang),
        // Safe diagnostic (error code + HTTP status only) so a real-phone
        // failure can be told apart without the logs.
        if (diagnostic != null && diagnostic.isNotEmpty) '($diagnostic)',
      ].join(' ')),
      action: retry == null
          ? null
          : SnackBarAction(label: askodoxChatLabel('retry', _lang), onPressed: retry),
    ));
  }

  /// Stops waiting for an attachment analysis; the attachments stay.
  void _cancelAttachmentAnalysis() {
    setState(() {
      _attachmentJob++;
      _analyzingAttachments = false;
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual<AskodoxChatRequest?>(askodoxChatRequestProvider,
        (previous, next) {
      if (next != null) unawaited(_handleChatRequest(next));
    }, fireImmediately: true);
    _restoring = _restore();
    unawaited(_loadLeads());
    // Native speech events (device TTS word ranges) drive the friend's
    // lip-sync; everything else on this channel is Dart -> native.
    _device.setMethodCallHandler(_onDeviceEvent);
  }

  Future<Object?> _onDeviceEvent(MethodCall call) async {
    if (!mounted) return null;
    final voice = ref.read(askodoxCompanionVoiceProvider);
    if (call.method == 'speechRange') {
      final args = Map<Object?, Object?>.from(call.arguments as Map? ?? const {});
      voice.speechRange((args['start'] as num?)?.toInt() ?? 0, (args['end'] as num?)?.toInt() ?? 0);
    }
    return null;
  }

  Future<void> _loadLeads() async {
    try {
      final leads = await ref.read(growthRepositoryProvider).leads();
      if (mounted) setState(() => _leads = leads.where((l) => !l.responded).toList());
    } catch (_) {
      // Leads are a bonus surface; chat never depends on them.
    }
  }

  Future<void> _replyToLead(AskodoxLead lead) async {
    final ok = await ref.read(growthRepositoryProvider).expressInterest(lead.requestId);
    if (!mounted) return;
    setState(() {
      if (ok) _leadReplies.add(lead.requestId);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (_te ? 'మీ ఆసక్తి పంపబడింది. కస్టమర్ అంగీకరిస్తే డీల్ ప్రారంభమవుతుంది.' : 'Sent. If the customer accepts, the deal starts here.')
          : (_te ? 'ఇప్పుడు పంపలేకపోయాం.' : 'Could not send right now.')),
    ));
  }

  /// Completes once launch handling (fresh ask or same-session restore) is
  /// done, so a History tap can never be overwritten by it.
  Future<void> _restoring = Future<void>.value();

  /// Requests from History ("open" / "New ask") and Explore ("ask this").
  Future<void> _handleChatRequest(AskodoxChatRequest request) async {
    Future.microtask(() {
      if (mounted) ref.read(askodoxChatRequestProvider.notifier).state = null;
    });
    await _restoring;
    if (!mounted) return;
    if (request.newConversation) {
      await _startNewConversation();
      return;
    }
    if (request.voice) {
      if (!_sending) await _startVoice();
      return;
    }
    if (request.hubAction case final action?) {
      await _companionAction(action);
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
    final archive = ref.read(askodoxConversationArchiveProvider.notifier);
    if (ref.read(askodoxFreshLaunchProvider).consumeFreshLaunch()) {
      // A genuine app launch opens Main Chat as a new, clean ask. The last
      // conversation is not deleted -- it stays in History.
      await _beginFreshLaunch(archive);
      return;
    }
    // Same app session (Main Chat remounted): reopen the exact current
    // conversation (results, deal, role); else the legacy turn store.
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
        if (deal.intent == DealIntent.sell && _userMeansToSell(deal.rawText, deal)) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          results = await _findUniversalMatches(
              deal.intent == DealIntent.sell ? deal.copyWith(intent: DealIntent.buy) : deal);
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

  /// Fresh launch: make sure the previous conversation is safely in History
  /// (also after a crash, when only the per-turn store was written), then
  /// reset only the temporary chat context. Owned roles, profile and
  /// settings are untouched.
  Future<void> _beginFreshLaunch(AskodoxConversationArchive archive) async {
    await archive.ready();
    final previousId = await archive.currentId();
    final records = await _store.load();
    if (records.isNotEmpty && (previousId == null || archive.byId(previousId) == null)) {
      final first = records.firstWhere((turn) => turn.isUser, orElse: () => records.first);
      final line = first.text.split('\n').first.trim();
      await archive.save(AskodoxConversationSnapshot(
        id: previousId ?? _newConversationId(),
        title: line.length <= 60 ? line : '${line.substring(0, 57)}…',
        updatedAt: DateTime.now(),
        status: AskodoxConversationStatus.active,
        data: {'turns': [for (final turn in records) turn.toJson()]},
      ));
    }
    await _store.clear();
    await archive.setCurrent(null);
    if (!mounted) return;
    ref.read(universalDealControllerProvider.notifier).reset();
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
      'orders': Map<String, String>.from(_orderByMatchKey),
      'parked': Map<String, Object?>.from(_parkedDeals),
      'pendingSellerQuestion': _pendingSellerQuestion,
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
    _orderByMatchKey.clear();
    _pendingSellerQuestion = null;
    _parkedDeals.clear();
    _lastDecision = null;
    _lastAskedQuestion = null;
    _lastMissing = const [];
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
      map(data['orders']).forEach((key, value) => _orderByMatchKey[key] = '$value');
      map(data['parked']).forEach((key, value) {
        if (value is Map) _parkedDeals[key] = Map<String, Object?>.from(value);
      });
      _pendingSellerQuestion = data['pendingSellerQuestion']?.toString();
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

  /// The most recent results that have options ASKODOX can act on (a
  /// registered seller / interested provider). A newer turn that only
  /// showed online links or a per-need segment must not hide them from
  /// "yes / order it / contact seller".
  AskodoxChatResults? _latestActionableResults() {
    final keys = _resultsByTurn.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final key in keys.take(4)) {
      final results = _resultsByTurn[key];
      if (results != null && results.hasLocal) return results;
    }
    return null;
  }

  /// Append what happened after results to the admin flow trace (fire and
  /// forget -- tracing never affects the user).
  void _traceEvent(AskodoxChatResults? results, String event, Map<String, Object?> detail) {
    final key = results?.traceKey;
    if (key == null || key.isEmpty) return;
    unawaited(ref.read(apiClientProvider).post<Map<String, Object?>>(
      '/deals/trace-event',
      body: {'trace_key': key, 'event': event, 'detail': detail},
    ).then((_) {}, onError: (_) {}));
  }

  AskodoxChatResults? _resultsContaining(UniversalMatch match) {
    for (final results in _resultsByTurn.values) {
      if (results.matches.any((m) => identical(m, match) || m.id == match.id)) return results;
    }
    return null;
  }

  String _resultsContext(AskodoxChatResults results) => [
        for (final match in results.matches.take(8)) '- ${askodoxOptionContext(match)}',
      ].join('\n');

  /// "Ask ASKODOX about this": keeps the user in the AI conversation about
  /// one option (price, distance, condition, reviews, availability). Only
  /// after this can the option's Send request / Connect be used.
  Future<void> _askAboutMatch(String? dealId, UniversalMatch match) async {
    _focusedMatch = match;
    _traceEvent(_resultsContaining(match), 'result_selected',
        {'title': match.title, 'source': match.source, 'segment': match.segment});
    setState(() => _actionableMatchKeys.add(_matchKey(dealId, match)));
    // A reviewed video: ground the answer on what ASKODOX actually knows
    // about it (analyzed transcript lines, or honestly only its title).
    var videoFacts = '';
    final videoId = match.videoId;
    if (videoId != null && videoId.isNotEmpty) {
      final explanation = await ref
          .read(askodoxVideoServiceProvider)
          .explain(videoId, question: match.title, language: _te ? 'te' : 'en');
      if (!mounted) return;
      if (explanation != null) videoFacts = '\n${explanation.groundingContext()}';
    }
    _pendingAiContext = 'Option the user is asking about: ${askodoxOptionContext(match)}$videoFacts\n'
        '$askodoxGroundingRule';
    _pendingDiscussOnly = true;
    await _send(_te
        ? '"${match.title}" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు'
        : 'Tell me more about "${match.title}"');
  }

  void _onRequestSent(String? dealId, UniversalMatch match, String? orderId) {
    setState(() {
      _requestSentMatchKeys.add(_matchKey(dealId, match));
      if (orderId != null && orderId.isNotEmpty) _orderByMatchKey[_matchKey(dealId, match)] = orderId;
      _pendingSellerQuestion = null;
      _actionConfirmed = true; // the companion is happy until the next message
    });
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
    final userTurns = [for (final turn in _turns.take(assistantTurn)) if (turn.isUser) turn.reasoningText];
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
              {'role': turn.isUser ? 'user' : 'assistant', 'text': turn.reasoningText},
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
          locale: _lang,
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
  /// True when a reply changed none of the deal's details.
  static bool _sameDetails(UniversalDeal a, UniversalDeal b) =>
      a.subject == b.subject &&
      a.quantity == b.quantity &&
      a.price == b.price &&
      a.variant == b.variant &&
      a.size == b.size &&
      a.model == b.model &&
      a.quality == b.quality &&
      a.timing == b.timing &&
      a.location.label == b.location.label &&
      a.dynamicFields.toString() == b.dynamicFields.toString();

  /// A real listing is created only when the user said they sell / the
  /// active role is Seller -- never from an AI guess while browsing.
  bool _userMeansToSell(String text, UniversalDeal deal) {
    if (ref.read(askodoxRoleProvider).active == AskodoxUserRole.seller) return true;
    for (final said in [text, deal.rawText]) {
      final detection = askodoxDetectRole(said);
      if (detection?.role == AskodoxUserRole.seller && !detection!.ambiguous) return true;
    }
    return false;
  }

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
    UniversalDeal deal, {
    List<String>? categories,
  }) async {
    try {
      final result = await ref
          .read(universalMatchRepositoryProvider)
          .createAndMatch(deal, trace: _traceFor(deal, categories: categories));
      final matches = [...result.matches]
        ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
      // Only real rows. With none, the chat says so (searched: true) --
      // never placeholder "Search online for …" cards.
      return AskodoxChatResults(
        dealId: result.dealId,
        matches: matches,
        sourceStatus: result.sourceStatus,
        searched: true,
        broadcastSent: result.broadcastSent,
        scopeMessage: result.scopeMessage,
        advice: result.advice,
        nextActions: result.nextActions,
        traceKey: result.traceKey,
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
    final attachments = List<ChatAttachment>.of(_attachments);
    final typed = (preset ?? _controller.text).trim();
    if (_sending || _analyzingAttachments || (typed.isEmpty && attachments.isEmpty)) {
      return;
    }
    var text = typed;
    _companionError = false;
    if (!speakResponse) unawaited(_stopSpeaking());
    // Automatic language: follow the language the customer is actually
    // writing in. Attachments (and an empty caption) inherit it.
    if (typed.isNotEmpty && (preset == null || speakResponse)) {
      await ref.read(askodoxConversationLanguageProvider.notifier).observe(typed);
    }

    var attachmentContext = '';
    final sentAttachments = <Map<String, String>>[];
    if (attachments.isNotEmpty) {
      // The ACTUAL bytes go to the backend (image / video / document
      // processor by MIME type); the facts it returns join the request.
      final job = ++_attachmentJob;
      setState(() => _analyzingAttachments = true);
      final facts = <String>[];
      Map<String, Object?>? imageAnalysis;
      Map<String, Object?>? videoAnalysis;
      try {
        for (final attachment in attachments) {
          final result = await ref.read(chatAttachmentServiceProvider).analyze(
                attachment,
                userText: typed,
                language: _lang,
              );
          if (job != _attachmentJob || !mounted) return; // cancelled
          facts.add(attachments.length > 1 ? '${attachment.name}: ${result.facts}' : result.facts);
          sentAttachments.add({'name': attachment.name, 'kind': result.kind, 'id': result.id});
          if (result.kind == 'image') imageAnalysis ??= result.analysis;
          if (result.kind == 'video') videoAnalysis ??= result.analysis;
        }
      } on ChatAttachmentException catch (error) {
        if (job != _attachmentJob || !mounted) return;
        setState(() {
          _analyzingAttachments = false;
          _companionError = true;
        });
        debugPrint('ASKODOX attachment analysis failed: ${error.diagnostic}');
        _attachmentNotice(
          switch (error.code) {
            'unsupported' => 'attach_unsupported',
            'too_large' => error.kind == 'video' ? 'attach_video_too_large' : 'attach_too_large',
            'unavailable' => 'attach_unavailable',
            'not_understood' => 'attach_not_understood',
            _ => 'attach_failed',
          },
          retry: error.retryable ? () => _send(preset, speakResponse) : null,
          diagnostic: error.diagnostic,
        );
        return;
      }
      if (!mounted) return;
      setState(() => _analyzingAttachments = false);
      attachmentContext = 'Attachment facts: ${facts.join('\n')}';
      if (typed.isNotEmpty && askodoxWantsToList(typed) && (imageAnalysis != null || videoAnalysis != null)) {
        await _draftFromMedia(typed,
            imageAnalysis: imageAnalysis,
            videoAnalysis: videoAnalysis,
            speakResponse: speakResponse,
            attachments: sentAttachments);
        return;
      }
      text = askodoxAttachmentRequest(typed.isEmpty ? askodoxAttachmentOnlyAsk : typed, facts.join('\n'));
    }

    setState(() {
      _sending = true;
      _active = true;
      _actionConfirmed = false;
      _listingBanner = null;
      _listingBannerIsError = false;
      _turns.add(ConversationTurnRecord(
        text: typed,
        isUser: true,
        attachments: sentAttachments,
        context: attachmentContext,
      ));
      _attachments.clear();
    });
    _controller.clear();
    _scrollBottom();

    final history = _turns
        .take(_turns.length - 1)
        .map((turn) => InAppAssistantTurn(
              role: turn.isUser ? 'user' : 'assistant',
              text: turn.reasoningText,
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
    if (_pendingDraft != null && !askodoxWantsToList(text)) {
      await _reviewDraft(text, speakResponse);
      return;
    }
    // Seller catalogue ("ready-made grocery catalogue", "all", "yes"): the
    // seller's own task -- never a buyer search, never a role flip.
    if (await _handleSellerCatalogue(text, speakResponse)) return;
    final latestResults = _latestResults();
    final actionable = _latestActionableResults();
    final explicitContext = _pendingAiContext;
    // "yes" / "order it" / "I want this" / "contact seller" with real
    // options on screen performs the SAME backend action as the card's
    // Send request button -- it is never answered with text alone.
    if (explicitContext == null && actionable != null && askodoxConfirmsAction(text)) {
      await _actOnConfirmation(text, actionable, speakResponse);
      return;
    }
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
            ? '$text\nOptions already shown to the user:\n${_resultsContext(latestResults)}\n$askodoxGroundingRule'
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

    // Universal routing: a seller-only question (stock, final price,
    // delivery/appointment commitment) about a request already with a
    // seller/provider is relayed through ASKODOX -- AI never guesses it.
    final openOrderId = _orderByMatchKey.isEmpty ? null : _orderByMatchKey.values.last;
    if (openOrderId != null &&
        explicitContext == null &&
        askodoxRouteMessage(text, hasOpenDeal: true, previousIssueTurns: _issueTurns - 1) ==
            AskodoxRoute.seller) {
      await _relayToSeller(openOrderId, text, speakResponse);
      return;
    }

    // Several needs in one message ("fridge ₹30–40k, TV ₹20–30k, car ₹10
    // lakh"): each becomes its own requirement with its own slots and its
    // own real results -- nothing is mixed between categories.
    final needs = explicitContext == null && !discussOnly
        ? askodoxSplitNeeds(text)
        : const <AskodoxNeedSegment>[];
    if (needs.isNotEmpty) {
      await _searchSeveralNeeds(needs, speakResponse, text);
      return;
    }

    final decision = await ref.read(askodoxAssistantServiceProvider).decide(
      message: aiMessage,
      locale: _lang,
      history: history,
      location: knownLocationLabel,
    );
    final aiUsable = decision?.usable == true;
    if (aiUsable) {
      _lastDecision = decision;
      // The same brain decision dresses the companion in Automatic mode (a
      // generic domain; follow-ups keep it). No separate avatar logic.
      final domain = decision!.domain.toUpperCase();
      if (domain != 'UNKNOWN') ref.read(askodoxCompanionDomainProvider.notifier).state = domain;
    }
    // "show me / results / options" = search now with what is known.
    // A "show me" said before a clarification question still counts once the
    // customer picks what they meant.
    // "X review videos" is a search even when the AI files it as general
    // chat, and it searches NOW with what is known: someone asking for
    // videos is not asked purchase details first.
    final videoAsk = !discussOnly && explicitContext == null && askodoxAsksForVideos(text);
    final showNow = askodoxWantsResultsNow(text) || videoAsk || (clarified != null && _showNowAfterClarification);
    final showOnly = showNow && askodoxNeedSubject(text).isEmpty;
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
    // "Tata" / "only Voltas" after (or during) a search refines THAT search
    // -- even when its results are already shown -- instead of starting a
    // new request or going to general chat. Any category, no brand list.
    final listedBrands = ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{};
    // (A reply to a pending question goes through answer() first and is a
    // brand only if it filled nothing -- "curry cut" stays a detail.)
    final brandRefinement = !discussOnly &&
        clarified == null &&
        !detailAnswer &&
        activeDealSession.deal != null &&
        text.trim().split(RegExp(r'\s+')).length <= 4 &&
        askodoxDetectRole(text) == null &&
        (askodoxQualifierReply(text) != null || askodoxDetectBrand(text, known: listedBrands) != null);
    final transactional = !discussOnly &&
        (clarified != null ||
            videoAsk ||
            detailAnswer ||
            brandRefinement ||
            (showNow && activeDealSession.deal != null) ||
            (aiUsable
                ? (decision!.transactional || AskodoxSemanticDealInput.isConcreteNeed(decision))
                : AskodoxHomeRequestRouting.isTransactional(text) || askodoxStatesANeed(text)));
    // A Seller / Provider describing what they offer ("grocery", "fashion
    // items") is never rewritten into a purchase; only an explicit "I want
    // to buy" is.
    final actsAsSupplier = askodoxActsAsSupplier(ref.read(askodoxRoleProvider).active, text);
    final routedText =
        aiUsable ? AskodoxSemanticDealInput.build(text, decision!, supplySide: actsAsSupplier) : text;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    AskodoxChatResults? results;
    UniversalDeal? matchedDeal;
    String? detailQuestion;
    AskodoxClarification? needClarification;
    if (clarified != null) _showNowAfterClarification = false;
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

      final aiSubject = aiUsable ? decision!.entityText('subject') : null;
      final parked = _parkedFor(aiSubject ?? (showNow || askodoxBudgetRange(text).isEmpty == false ? askodoxNeedSubject(text) : null));
      // The active deal just before a reply is applied: a short reply that
      // filled nothing ("Tata") is a brand refinement (see brand_lexicon).
      UniversalDeal? dealBeforeAnswer;
      if (clarified != null) {
        notifier.refineSubject(clarified.subject);
      } else if (brandRefinement && session.deal != null) {
        // Same need, new brand: keep every answer (budget, new/used, place).
        dealBeforeAnswer = session.deal;
        notifier.adopt(session.deal!);
      } else if (showOnly && session.deal != null) {
        // "show me" alone: keep every answer, just search.
      } else if (parked != null && !askodoxSameNeed(session.deal?.subject, parked.subject)) {
        // Back to an earlier category: its own answers, not the current one's.
        if (session.deal != null) _parkDeal(session.deal!);
        notifier.reset();
        notifier.adopt(parked);
        if (!showOnly) notifier.answer(text);
      } else if (session.deal != null &&
          !session.completed &&
          !detailAnswer &&
          aiSubject != null &&
          session.deal!.subject != null &&
          !askodoxSameNeed(session.deal!.subject, aiSubject)) {
        // A different need while one is unfinished: park it (kept for when
        // the customer returns) instead of writing the new need into its slots.
        _parkDeal(session.deal!);
        _lastGoodProductQuery = null;
        notifier.reset();
        notifier.start(routedText);
      } else if (detailAnswer) {
        // The user's own words, not the AI rewrite: a rewrite like
        // "i want to buy 1 kg" would look like a new retail request and
        // restart (drop) the active chicken deal.
        dealBeforeAnswer = session.deal;
        final brandLike = askodoxQualifierReply(text) ??
            askodoxDetectBrand(text, known: ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{});
        if (brandLike != null) {
          notifier.answerOrBrand(text,
              brand: brandLike, known: ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{});
        } else {
          notifier.answer(text);
        }
      } else if (shouldStartFresh && session.deal != null) {
        _lastGoodProductQuery = null;
        notifier.reset();
        notifier.start(routedText);
      } else if (session.deal == null || session.completed) {
        _lastGoodProductQuery = null;
        notifier.start(routedText);
      } else {
        dealBeforeAnswer = session.deal;
        notifier.answer(routedText);
      }

      if (selectedLocation != null) {
        final key = '${selectedLocation.point.latitude},${selectedLocation.point.longitude}';
        final dealLocation = ref.read(universalDealControllerProvider).deal?.location;
        // The deal took the PREVIOUS chosen location (not a place the user
        // typed): a newly chosen location replaces it.
        final fromOldDefault = _appliedLocationKey != null &&
            _appliedLocationKey != key &&
            dealLocation?.latitude != null &&
            '${dealLocation!.latitude},${dealLocation.longitude}' == _appliedLocationKey;
        notifier.applySelectedLocation(
          label: knownLocationLabel ?? '',
          latitude: selectedLocation.point.latitude,
          longitude: selectedLocation.point.longitude,
          radiusKm: locationState.radiusMetres / 1000,
          replace: fromOldDefault,
        );
        _appliedLocationKey = key;
      }
      final budget = askodoxBudgetRange(text);
      if (!budget.isEmpty) notifier.applyBudget(min: budget.min, max: budget.max);
      // "Tata" / "show Samsung instead": the named brand replaces the old
      // one in the active search (constraints persist, brand updates).
      // No fixed brand list: phrasing ("only Tata"), brands real listings
      // carry, or a short reply that answered no other question.
      final known = ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{};
      final afterAnswer = ref.read(universalDealControllerProvider).deal;
      // The AI names the brand in any category (it knows every maker);
      // phrasing, listed brands and a short reply cover the offline case.
      final aiBrand = aiUsable ? decision!.entityText('brand') : null;
      final brand = (aiBrand != null && aiBrand.length <= 40 ? aiBrand : null) ??
          askodoxDetectBrand(text, known: known) ??
          (dealBeforeAnswer != null && afterAnswer != null && _sameDetails(dealBeforeAnswer, afterAnswer)
              ? askodoxQualifierReply(text)
              : null);
      if (brand != null) notifier.applyBrand(brand, known: known);
      // The AI's category (any category, any language) travels with the
      // requirement: it shapes follow-up questions and the Admin trace
      // instead of fixed English keyword lists.
      final aiCategory = aiUsable ? decision!.entityText('category') : null;
      if (aiCategory != null && aiCategory.trim().isNotEmpty && aiCategory.length <= 60) {
        notifier.applyAiCategory(aiCategory);
      }
      // A subject polluted by budget/filler words ("TV ₹20,000 లో కావాలి")
      // is cleaned once, universally.
      // The place is the deal's location, never part of WHAT is wanted.
      final placed = ref.read(universalDealControllerProvider).deal;
      final placeLabel = placed?.location.label ?? knownLocationLabel ?? '';
      if (placed?.subject != null && placeLabel.trim().isNotEmpty) {
        final without = askodoxWithoutPlace(placed!.subject!, placeLabel);
        if (without.isNotEmpty && without != placed.subject!.trim()) notifier.refineSubject(without);
      }
      final rawSubject = ref.read(universalDealControllerProvider).deal?.subject;
      if (rawSubject != null && RegExp(r'₹|\d{4,}|కావాలి|show me|చూపించ|^(a|an|the)\s', caseSensitive: false).hasMatch(rawSubject)) {
        final clean = askodoxNeedSubject(rawSubject);
        if (clean.isNotEmpty) notifier.refineSubject(clean);
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
          // The AI flags genuine ambiguity for any category; the fixed
          // rules only cover the offline case.
          final aiOptions = aiUsable && decision!.action == 'clarify_need'
              ? [for (final o in (decision.entities['clarify_options'] as List? ?? const [])) '$o']
              : const <String>[];
          final candidate = askodoxDynamicClarification(options: aiOptions, question: decision?.reply) ??
              askodoxClarificationFor(text);
          if (candidate != null && !_clarifiedKeys.contains(candidate.key)) {
            needClarification = candidate;
            _showNowAfterClarification = showNow;
          }
        }
        if (!deal.readyToMatch) detailQuestion = dealSession.lastQuestion;
      }
      // Never loop on the same question: once asked and answered, or when
      // the customer says "show me", search with what is known.
      // A loop = the same question again AND the answer filled nothing.
      final missingNow = deal?.missingForMatch ?? const <String>[];
      final repeating = detailQuestion != null &&
          clarified == null &&
          detailQuestion == _lastAskedQuestion &&
          missingNow.join('|') == _lastMissing.join('|');
      final searchNow = deal != null &&
          (deal.readyToMatch ||
              ((showNow || repeating) && (deal.subject?.trim().isNotEmpty ?? false)));
      if (searchNow && !deal.readyToMatch) detailQuestion = repeating || videoAsk ? null : detailQuestion;
      if (deal != null && searchNow && needClarification == null) {
        if (deal.intent == DealIntent.sell && _userMeansToSell(text, deal)) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          // A "sell" guess the user never said is a buyer search.
          final searchDeal = deal.intent == DealIntent.sell ? deal.copyWith(intent: DealIntent.buy) : deal;
          matchedDeal = searchDeal;
          results = await _findUniversalMatches(searchDeal);
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
      // demand-side intent guess from a keyword like "repair", and a guessed
      // supply intent never flips a Buyer (role scoped to this request).
      final current = ref.read(askodoxRoleProvider).active;
      final detected = askodoxContextRole(spoken: detection, fromIntent: dealRole, current: current);
      // A general (non-commerce) "I need ..." is not a buying intent.
      final generalBuyerHint = !transactional && detected == AskodoxUserRole.buyer;
      if (detected != null && detected != current && !generalBuyerHint) {
        final ambiguous = (detection?.ambiguous ?? false) ||
            (detection == null && aiUsable && decision!.confidence < 0.55);
        if (ambiguous && askodoxRoleSwitchIsHighImpact(detected, from: current)) {
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
    var reply = needClarification != null
      ? (_te ? needClarification.teluguQuestion : needClarification.question)
      // A video ask answers from the REAL results (or the next detail it
      // needs), never with an AI claim of results / specs it did not fetch.
      : videoAsk && results != null
        ? askodoxResultsReply(results, telugu: _te)
      : videoAsk && detailQuestion != null && detailQuestion.trim().isNotEmpty
        ? askodoxDetailQuestionReply(detailQuestion, telugu: _te)
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

    // Dynamic questions: an unfinished requirement always ends with the NEXT
    // question it needs (e.g. area for local results), even when the AI's
    // own reply is an explanation -- otherwise the app waits silently and
    // the customer only ever sees text.
    final nextQuestion = detailQuestion?.trim();
    if (transactional &&
        needClarification == null &&
        nextQuestion != null &&
        nextQuestion.isNotEmpty &&
        !reply.trim().endsWith('?') &&
        !reply.contains(nextQuestion)) {
      final ask = askodoxDetailQuestionReply(nextQuestion, telugu: _te);
      reply = reply.trim().isEmpty || reply == ask ? ask : '${reply.trim()}\n\n$ask';
    }

    // A clarification turn did not actually ask the detail question.
    _lastAskedQuestion = transactional && results == null && needClarification == null ? detailQuestion : null;
    _lastMissing = transactional && results == null
        ? (ref.read(universalDealControllerProvider).deal?.missingForMatch ?? const [])
        : const [];

    final sellerOnly = openOrderId == null &&
        latestResults != null &&
        latestResults.hasLocal &&
        askodoxNeedsSeller(text);
    if (sellerOnly) {
      // ASKODOX answers what it can; the seller-only part rides along with
      // the next Send request.
      _pendingSellerQuestion = text;
      reply = '$reply${askodoxSellerQuestionHint(telugu: _te)}';
    }

    if (!mounted) return;
    setState(() {
      if (sellerOnly) {
        for (final match in latestResults.local) {
          _actionableMatchKeys.add(_matchKey(latestResults.dealId, match));
        }
      }
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

  void _parkDeal(UniversalDeal deal) {
    final key = deal.subject?.trim();
    if (key == null || key.isEmpty) return;
    _parkedDeals[key] = ref.read(universalDealControllerProvider.notifier).encodeDeal(deal);
  }

  UniversalDeal? _parkedFor(String? subject) {
    if (subject == null || subject.trim().isEmpty) return null;
    for (final entry in _parkedDeals.entries) {
      if (askodoxSameNeed(entry.key, subject)) {
        return ref.read(universalDealControllerProvider.notifier).decodeDeal(Map<String, dynamic>.from(entry.value));
      }
    }
    return null;
  }

  /// App-side facts for the admin flow trace (no personal data beyond what
  /// the customer typed): query, AI intent, categories, questions asked and
  /// the answers remembered.
  Map<String, Object?> _traceFor(UniversalDeal deal, {List<String>? categories}) {
    final questions = <String>[];
    final answers = <String>[];
    for (var i = 0; i < _turns.length; i++) {
      final turn = _turns[i];
      if (!turn.isUser && turn.text.trim().endsWith('?')) {
        questions.add(turn.text.trim());
        if (i + 1 < _turns.length && _turns[i + 1].isUser) answers.add(_turns[i + 1].text.trim());
      }
    }
    final lastUser = _turns.lastWhere((t) => t.isUser, orElse: () => ConversationTurnRecord(text: deal.rawText, isUser: true));
    return {
      'query': lastUser.text,
      // The conversation language (admin traces + Revenue Center breakdown).
      'language': _lang,
      // Attachments on the latest customer turn: kind + backend reference only.
      'attachments': [
        for (final a in lastUser.attachments) {'kind': a['kind'] ?? '', 'id': a['id'] ?? ''},
      ],
      'intent': _lastDecision?.action.isNotEmpty == true ? _lastDecision!.action : deal.intent.name,
      'domain': _lastDecision?.domain ?? deal.category,
      'categories': categories ?? [if (deal.subject != null) deal.subject!],
      'questions': questions.reversed.take(10).toList().reversed.toList(),
      'answers': answers.reversed.take(10).toList().reversed.toList(),
      // Context-scoped role, what is still unknown, and the place used.
      'active_role': ref.read(askodoxRoleProvider).active.name,
      'ui_language': Localizations.localeOf(context).languageCode,
      'missing_slots': deal.missingForMatch,
      'location_used': deal.location.label?.trim().isNotEmpty == true
          ? deal.location.label
          : (deal.location.latitude != null ? 'GPS point (not named)' : 'none'),
    };
  }

  Future<void> _searchSeveralNeeds(List<AskodoxNeedSegment> needs, bool speakResponse, String text) async {
    const brain = UniversalDealBrain();
    final notifier = ref.read(universalDealControllerProvider.notifier);
    final location = ref.read(locationControllerProvider).defaultLocation;
    final deals = [
      for (final need in needs)
        brain.capture('i want to buy ${need.subject}').copyWith(
          subject: need.subject,
          price: need.budget.max ?? need.budget.min,
          dynamicFields: {
            if (need.budget.min != null) 'budget_min': need.budget.min,
            if (need.budget.max != null) 'budget_max': need.budget.max,
          },
          location: location == null
              ? null
              : DealLocation(
                  label: location.address.trim().isNotEmpty ? location.address.trim() : location.name.trim(),
                  latitude: location.point.latitude,
                  longitude: location.point.longitude,
                ),
        ),
    ];
    final subjects = [for (final n in needs) n.subject];
    final results = await Future.wait([
      for (final deal in deals) _findUniversalMatches(deal, categories: subjects),
    ]);
    if (!mounted) return;
    final intro = _te
        ? 'మీ ${needs.length} అవసరాలను వేర్వేరుగా వెతికాను — ప్రతి దానికి దాని బడ్జెట్‌తో:'
        : 'I searched your ${needs.length} needs separately, each with its own budget:';
    setState(() {
      _turns.add(ConversationTurnRecord(text: intro, isUser: false));
      for (var i = 0; i < needs.length; i++) {
        _turns.add(ConversationTurnRecord(
          text: '${needs[i].subject} · ${needs[i].budget.label()}',
          isUser: false,
        ));
        final index = _turns.length - 1;
        _resultsByTurn[index] = results[i];
        _dealByTurn[index] = deals[i];
        _parkedDeals[needs[i].subject] = notifier.encodeDeal(deals[i]);
      }
      _sending = false;
    });
    // No single active deal: a follow-up names the category it is about.
    notifier.reset();
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(intro, userText: text);
  }

  /// The seller's catalogue task. Returns true when this message belonged
  /// to it (a catalogue request, or a short reply while one is open).
  Future<bool> _handleSellerCatalogue(String text, bool speakResponse) async {
    final open = _catalogue;
    String? reply;
    var openEditor = false;
    if (open != null) {
      final short = askodoxCatalogueReply(text);
      final named = [
        for (final c in open.categories)
          if (c.names.values.any((n) => n.trim().isNotEmpty && text.toLowerCase().contains(n.toLowerCase()))) c.key,
      ];
      if (short == AskodoxCatalogueReply.all) {
        _catalogueSelected
          ..clear()
          ..addAll(open.categories.map((c) => c.key));
        reply = askodoxCatalogueSelectedReply(open, _catalogueSelected, _lang);
        openEditor = true;
      } else if (short == AskodoxCatalogueReply.yes) {
        if (_catalogueSelected.isEmpty) _catalogueSelected.addAll(open.categories.map((c) => c.key));
        reply = askodoxCatalogueSelectedReply(open, _catalogueSelected, _lang);
        openEditor = true;
      } else if (short == AskodoxCatalogueReply.no) {
        reply = askodoxCatalogueClosedReply(_lang);
        _catalogue = null;
        _catalogueTurn = null;
        _catalogueSelected.clear();
      } else if (named.isNotEmpty) {
        _catalogueSelected.addAll(named);
        reply = askodoxCatalogueSelectedReply(open, _catalogueSelected, _lang);
      }
    }
    final active = ref.read(askodoxRoleProvider).active;
    String? roleNotice;
    if (reply == null) {
      if (!askodoxWantsSellerCatalogue(text, active)) return false;
      setState(() => _sending = true);
      final repo = ref.read(askodoxCatalogueRepositoryProvider);
      final key = askodoxCatalogueTemplateFor(text) ??
          ref.read(askodoxUserProfileProvider).valueOrNull?.businessCategory;
      final template = key == null ? null : await repo.template(key);
      if (!mounted) return true;
      if (template == null) {
        final available = await repo.templates();
        if (!mounted) return true;
        reply = askodoxCatalogueNoTemplateReply([for (final t in available) t.names[_lang] ?? t.names['en'] ?? t.key],
            _lang, asked: key != null);
      } else {
        _catalogue = template;
        _catalogueSelected.clear();
        reply = askodoxCatalogueOfferReply(template, _lang);
      }
      // Asking for a catalogue for one's own shop IS acting as a Seller.
      if (!askodoxSupplyRoles.contains(active)) {
        ref.read(askodoxRoleProvider.notifier).setActive(AskodoxUserRole.seller);
        roleNotice = askodoxRoleChangedMessage(active, AskodoxUserRole.seller, telugu: _te);
      }
    }
    if (!mounted) return true;
    setState(() {
      if (roleNotice != null) _roleNoticeByTurn[_turns.length - 1] = roleNotice;
      _turns.add(ConversationTurnRecord(text: reply!, isUser: false));
      if (_catalogue != null && open == null) _catalogueTurn = _turns.length - 1;
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(reply, userText: text);
    if (openEditor) unawaited(_openCatalogueEditor());
    return true;
  }

  Future<void> _openCatalogueEditor() async {
    final template = _catalogue;
    if (template == null || _catalogueSelected.isEmpty) return;
    if (ref.read(authSessionProvider).user == null) {
      await context.push<bool>('/onboarding?signin=1');
      if (!mounted || ref.read(authSessionProvider).user == null) return;
    }
    AskodoxUserProfile? profile;
    try {
      profile = await ref.read(askodoxUserProfileProvider.future);
    } catch (_) {
      profile = null; // offline: the seller types the shop details
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<AskodoxCataloguePublishResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskodoxCatalogueEditorSheet(
        template: template,
        categoryKeys: Set.of(_catalogueSelected),
        lang: _lang,
        shopName: profile?.businessName ?? profile?.name,
        shopAddress: profile?.businessAddress ?? profile?.address ?? ref.read(locationControllerProvider).headerLocation,
      ),
    );
    if (result == null || !mounted) return;
    ref.invalidate(askodoxUserProfileProvider);
    setState(() {
      _turns.add(ConversationTurnRecord(text: askodoxCataloguePublishedReply(result, _lang), isUser: false));
      _companionError = !result.ok;
      _actionConfirmed = result.ok && result.published > 0;
      if (result.ok) {
        _catalogue = null;
        _catalogueTurn = null;
        _catalogueSelected.clear();
      }
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
  }

  /// Typed confirmation -> the shared executor (same endpoint, same order
  /// id as the button). The reply states the real outcome only.
  Future<void> _actOnConfirmation(String text, AskodoxChatResults results, bool speakResponse) async {
    final target = askodoxPickTarget(text, results.local, focused: _focusedMatch);
    String reply;
    if (target == null) {
      reply = _te ? 'పంపడానికి ASKODOX ఎంపిక ఏదీ లేదు.' : 'There is no ASKODOX option to send a request to.';
    } else if (_requestSentMatchKeys.contains(_matchKey(results.dealId, target))) {
      final orderId = _orderByMatchKey[_matchKey(results.dealId, target)];
      reply = _te
          ? '"${target.title}" కి అభ్యర్థన ఇప్పటికే పంపబడింది${orderId == null ? '' : ' (#$orderId)'}. వారి సమాధానం కోసం వేచి ఉన్నాం.'
          : 'Your request to "${target.title}" was already sent${orderId == null ? '' : ' (#$orderId)'}. Waiting for their reply.';
    } else {
      _traceEvent(results, 'action_attempted',
          {'action': chatResultActionFor(target).name, 'title': target.title, 'via': 'chat'});
      final result = await askodoxExecuteMatchAction(
        ref,
        match: target,
        dealId: results.dealId,
        telugu: _te,
        requestContext: _requestContextFor(results.dealId),
        question: _pendingSellerQuestion,
      );
      _traceEvent(results, 'action_result', {
        'action': chatResultActionFor(target).name,
        'ok': result.success,
        if (result.order?.id != null) 'order_id': result.order!.id,
        if (!result.success) 'reason': result.needsSignIn ? 'sign_in_required' : (result.message ?? 'failed'),
      });
      if (result.needsSignIn) {
        _pendingSignInAction = (text: text, results: results, target: target);
      }
      if (result.success) {
        _focusedMatch = target; // "order it" next time means this option
        _onRequestSent(results.dealId, target, result.order?.id);
        final id = result.order?.id;
        reply = _te
            ? '"${target.title}" కి అభ్యర్థన పంపబడింది${id == null ? '' : ' (#$id)'}. వారు అంగీకరించిన తర్వాతే డీల్ నిర్ధారితమవుతుంది, కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
            : 'Request sent to "${target.title}"${id == null ? '' : ' (#$id)'}. It becomes a confirmed deal -- and contact details are shared -- only after they accept.';
      } else {
        reply = result.message ?? (_te ? 'అభ్యర్థన పంపడం సాధ్యం కాలేదు.' : 'Unable to send this request.');
      }
    }
    if (!mounted) return;
    setState(() {
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      if (_pendingSignInAction != null) _signInTurn = _turns.length - 1;
      _dealRefreshTick++;
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(reply, userText: text);
  }

  /// Phone + OTP sign-in, then the pending action runs exactly as asked.
  Future<void> _signInAndRetry() async {
    final pending = _pendingSignInAction;
    if (pending == null) return;
    await context.push<bool>('/onboarding?signin=1');
    if (!mounted || ref.read(authSessionProvider).user == null) return;
    setState(() {
      _pendingSignInAction = null;
      _signInTurn = null;
      _sending = true;
    });
    _focusedMatch = pending.target;
    _traceEvent(pending.results, 'auth_resumed', {'title': pending.target.title, 'via': 'sign_in'});
    await _actOnConfirmation(pending.text, pending.results, false);
  }

  /// No ASKODOX provider has this yet: create a real referral invite (code
  /// + share text with the benefits of joining) the customer can forward.
  Future<void> _referProvider(int turnIndex, AskodoxChatResults results, {bool afterSignIn = false}) async {
    final deal = _dealByTurn[turnIndex] ?? ref.read(universalDealControllerProvider).deal;
    final referral = await ref.read(growthRepositoryProvider).refer(
          category: deal?.subject ?? deal?.category ?? '',
          area: deal?.location.label ?? '',
          dealId: results.dealId,
        );
    // A guest signs in (real OTP), then the SAME referral continues with the
    // same category/place/request -- never a dead end.
    if (referral == null &&
        !afterSignIn &&
        ref.read(authSessionProvider).user == null &&
        mounted &&
        GoRouter.maybeOf(context) != null) {
      await context.push<bool>('/onboarding?signin=1');
      if (mounted && ref.read(authSessionProvider).user != null) {
        return _referProvider(turnIndex, results, afterSignIn: true);
      }
      if (!mounted) return;
    }
    String reply;
    if (referral == null) {
      reply = _te
          ? 'ఎవరినైనా సూచించడానికి సైన్ ఇన్ చేయండి (రిఫరల్ మీ పేరుతో నమోదవుతుంది).'
          : 'Sign in to refer someone (the referral is recorded in your name).';
    } else {
      unawaited(Clipboard.setData(ClipboardData(text: referral.shareText)).catchError((_) {}));
      // WhatsApp (or the phone's share/browser) opens with the invite ready;
      // the reply never waits on the other app.
      unawaited(launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(referral.shareText)}'),
              mode: LaunchMode.externalApplication)
          .then((_) {}, onError: (_) {}));
      reply = _te
          ? 'రిఫరల్ కోడ్ ${referral.code} సిద్ధం -- WhatsAppలో పంపండి. సందేశం కాపీ అయింది.'
          : 'Referral code ${referral.code} is ready -- send it on WhatsApp. The message is copied too.';
    }
    if (!mounted) return;
    setState(() => _turns.add(ConversationTurnRecord(text: reply, isUser: false)));
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
  }

  /// "Seller/provider? Join ASKODOX": continue IN THIS chat as the supply
  /// side of the same need -- category and place prefilled, the Buyer role
  /// kept (roles are additive), sign-in only when the listing is saved.
  Future<void> _joinAsProvider(int turnIndex, AskodoxChatResults results) async {
    final deal = _dealByTurn[turnIndex] ?? ref.read(universalDealControllerProvider).deal;
    final subject = (deal?.subject ?? deal?.category ?? '').trim();
    final place = (deal?.location.label ?? ref.read(locationControllerProvider).headerLocation ?? '').trim();
    final service = deal?.intent == DealIntent.needService || deal?.intent == DealIntent.bookAppointment;
    // One composition rule for "<thing> in <place>" -- never repeated, never
    // mixed connectors (real-phone: "Vuyyuru, Andhra Pradeshలో in Vuyyuru...").
    final what = askodoxWithPlace(subject, place, _te ? 'te' : 'en');
    final text = _te
        ? (service ? 'నేను $what సర్వీస్ ఇస్తాను' : 'నేను $what అమ్ముతాను')
        : (service ? 'I provide ${askodoxWithoutPlace(subject, place)} service'
                '${place.isEmpty ? '' : ' in ${askodoxShortPlace(place)}'}' : 'I sell $what');
    await _send(text.replaceAll(RegExp(r'\s+'), ' ').trim());
  }

  Future<void> _replyAndSave(String reply, bool speakResponse, String userText) async {
    if (!mounted) return;
    setState(() {
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(reply, userText: userText);
  }

  /// Photo/video + "sell this": a real catalog draft built only from what
  /// the analysis and the seller said; missing details are asked, never
  /// invented.
  Future<void> _draftFromMedia(String text,
      {Map<String, Object?>? imageAnalysis,
      Map<String, Object?>? videoAnalysis,
      required bool speakResponse,
      List<Map<String, String>> attachments = const []}) async {
    setState(() {
      _sending = true;
      _active = true;
      _turns.add(ConversationTurnRecord(text: text, isUser: true, attachments: attachments));
      _attachments.clear();
    });
    _controller.clear();
    final draft = await ref.read(growthRepositoryProvider).draftListing(
          text: text, imageAnalysis: imageAnalysis, videoAnalysis: videoAnalysis);
    String reply;
    if (draft == null) {
      reply = _te
          ? 'లిస్టింగ్ డ్రాఫ్ట్ చేయడానికి సైన్ ఇన్ చేయండి, లేదా వస్తువు గురించి ఒక చిన్న వివరణ ఇవ్వండి.'
          : 'Sign in to draft a listing, or add a short description of the item.';
    } else {
      _pendingDraft = draft;
      final missing = draft.missing.where((m) => m != 'subject').map(_draftFieldLabel).join(', ');
      // The example uses the seller's own active place, never a fixed city.
      final area = ref.read(locationControllerProvider).headerLocation;
      reply = _te
          ? 'డ్రాఫ్ట్ సిద్ధం: "${draft.title}". ${missing.isEmpty ? '' : 'ఇంకా కావాలి: $missing. '}ధర చెప్పండి (ఉదా: ₹3200, స్టాక్‌లో ఉంది${area == null ? '' : ', $area'}).'
          : 'Draft ready: "${draft.title}". ${missing.isEmpty ? '' : 'Still needed: $missing. '}Tell me the price (e.g. "₹3200, in stock${area == null ? '' : ', $area'}") to publish.';
    }
    await _replyAndSave(reply, speakResponse, text);
  }

  String _draftFieldLabel(String field) => switch (field) {
        'price' => _te ? 'ధర' : 'price',
        'stock_status' => _te ? 'స్టాక్' : 'stock',
        'location_label' => _te ? 'స్థలం' : 'location',
        _ => field,
      };

  /// The seller's review answer ("₹3200, in stock, Vijayawada") publishes
  /// the draft through the SAME listing creation as "list my product".
  Future<void> _reviewDraft(String text, bool speakResponse) async {
    final draft = _pendingDraft!;
    final lower = text.toLowerCase();
    if (RegExp(r'\b(cancel|discard|stop)\b|వద్దు').hasMatch(lower)) {
      _pendingDraft = null;
      await _replyAndSave(_te ? 'డ్రాఫ్ట్ రద్దు చేశాను.' : 'Draft discarded.', speakResponse, text);
      return;
    }
    final budget = askodoxBudgetRange(text);
    final price = budget.max ?? budget.min ?? (draft.draft['price'] as num?)?.toDouble();
    if (price == null) {
      await _replyAndSave(
          _te ? 'ప్రచురించడానికి ధర చెప్పండి (ఉదా: ₹3200).' : 'Tell me the price to publish (e.g. ₹3200).',
          speakResponse, text);
      return;
    }
    final place = RegExp(r'\b(?:in|at)\s+([A-Za-z][A-Za-z ]{2,40})').firstMatch(text)?.group(1)?.trim();
    final stock = RegExp(r'out of stock|sold out', caseSensitive: false).hasMatch(text)
        ? 'OUT_OF_STOCK'
        : RegExp(r'in stock|available|ఉంది', caseSensitive: false).hasMatch(text)
            ? 'IN_STOCK'
            : null;
    final location = place ?? ref.read(locationControllerProvider).defaultLocation?.name;
    final listingId = await ref.read(growthRepositoryProvider).publishDraft(draft.id, {
      'price': price,
      if (stock != null) 'stock_status': stock,
      if (location != null && location.trim().isNotEmpty) 'location_label': location.trim(),
    });
    _pendingDraft = null;
    await _replyAndSave(
        listingId == null
            ? (_te ? 'ఇప్పుడు ప్రచురించలేకపోయాను; మళ్లీ ప్రయత్నించండి.' : 'Could not publish right now; please try again.')
            : (_te
                ? '"${draft.title}" ₹${price.toStringAsFixed(0)} కి లిస్ట్ అయింది (#$listingId). కొనుగోలుదారులు ఇప్పుడు దీన్ని చూడగలరు.'
                : 'Listed "${draft.title}" at ₹${price.toStringAsFixed(0)} (#$listingId). Buyers can now find it.'),
        speakResponse,
        text);
  }

  /// A route need (parcel / ride) that still misses its pickup or drop.
  bool _routePinsNeeded() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null) return false;
    final missing = deal.missingForMatch;
    return missing.contains('from') || missing.contains('to');
  }

  /// Pickup/drop chosen on a real map pin: fills that end (label + real
  /// coordinates), then shows the real road distance and partner quotes
  /// once both ends are pinned. Nothing is asked twice.
  Future<void> _pickRoutePoint({required bool pickup}) async {
    final place = await AskodoxMapPinPicker.open(
      context,
      title: pickup ? (_te ? 'పికప్ ఎక్కడ?' : 'Pickup point') : (_te ? 'డ్రాప్ ఎక్కడ?' : 'Drop point'),
    );
    if (place == null || !mounted) return;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    notifier.setRoutePoint(pickup: pickup, label: place.label, latitude: place.latitude, longitude: place.longitude);
    final deal = ref.read(universalDealControllerProvider).deal;
    final fields = deal?.dynamicFields ?? const <String, Object?>{};
    final lines = <String>[
      pickup
          ? (_te ? 'పికప్: ${place.label}' : 'Pickup set: ${place.label}')
          : (_te ? 'డ్రాప్: ${place.label}' : 'Drop set: ${place.label}'),
    ];
    final hasBoth = fields['from_lat'] is num && fields['to_lat'] is num;
    if (hasBoth) {
      final quote = await ref.read(growthRepositoryProvider).routeQuote(
            AskodoxPlace(latitude: (fields['from_lat'] as num).toDouble(),
                longitude: (fields['from_lng'] as num).toDouble(), label: '${fields['from']}'),
            AskodoxPlace(latitude: (fields['to_lat'] as num).toDouble(),
                longitude: (fields['to_lng'] as num).toDouble(), label: '${fields['to']}'),
          );
      if (quote?.distanceKm != null) {
        lines.add(_te
            ? 'దూరం ~${quote!.distanceKm!.toStringAsFixed(1)} కి.మీ${quote.durationMinutes == null ? '' : ', ~${quote.durationMinutes} నిమి'}.'
            : 'Road distance ~${quote!.distanceKm!.toStringAsFixed(1)} km${quote.durationMinutes == null ? '' : ', ~${quote.durationMinutes} min'}.');
      }
      if (quote != null && quote.quotes.isNotEmpty) {
        final best = quote.quotes.first;
        lines.add(_te
            ? 'నమోదైన డెలివరీ భాగస్వామి రేటు: ₹${best.quote.toStringAsFixed(0)} (${best.title}).'
            : 'Registered delivery partner rate: ₹${best.quote.toStringAsFixed(0)} (${best.title}).');
      } else if (quote != null && quote.note.isNotEmpty) {
        lines.add(quote.note);
      }
    }
    final next = ref.read(universalDealControllerProvider);
    if (next.deal != null && !next.deal!.readyToMatch && next.lastQuestion != null) {
      lines.add(next.lastQuestion!);
    }
    if (!mounted) return;
    setState(() => _turns.add(ConversationTurnRecord(text: lines.join('\n'), isUser: false)));
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
  }

  Future<void> _relayToSeller(String orderId, String text, bool speakResponse) async {
    final amount = askodoxOfferAmount(text);
    String reply;
    try {
      await ref.read(orderLifecycleRepositoryProvider).message(
            orderId,
            amount != null ? 'OFFER' : 'QUESTION',
            text: text,
            amount: amount,
          );
      reply = askodoxSellerRelayReply(offer: amount != null, telugu: _te);
    } catch (error) {
      reply = _te
          ? 'ఇప్పుడు విక్రేతకు పంపలేకపోయాను. దయచేసి మళ్లీ ప్రయత్నించండి.'
          : 'I could not reach the seller right now. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      _dealRefreshTick++;
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) await _speakReply(reply, userText: text);
  }

  /// The structured requirement that travels with a request, so the seller
  /// / provider (and later Customer Care) never ask the customer again.
  Map<String, Object?> _requestContextFor(String? dealId) {
    UniversalDeal? deal;
    _resultsByTurn.forEach((turn, results) {
      if (results.dealId == dealId && _dealByTurn[turn] != null) deal = _dealByTurn[turn];
    });
    final d = deal ?? ref.read(universalDealControllerProvider).deal;
    if (d == null) return {if (dealId != null) 'deal_id': dealId};
    return {
      if (dealId != null) 'deal_id': dealId,
      'subject': d.subject,
      'category': d.category,
      'intent': d.intent.name,
      'quantity': d.quantity,
      'unit': d.unit,
      'budget': d.price,
      'size': d.size,
      'model': d.model,
      'variant': d.variant,
      'quality': d.quality,
      'timing': d.timing,
      'fulfilment': d.fulfilment,
      'location': d.location.label,
      ...d.dynamicFields,
    }..removeWhere((_, value) => value == null || (value is String && value.trim().isEmpty));
  }

  Future<void> _compareMatch(AskodoxChatResults results, UniversalMatch match) async {
    for (final option in results.local) {
      _actionableMatchKeys.add(_matchKey(results.dealId, option));
    }
    _pendingAiContext = 'Compare for the user. Selected: ${askodoxOptionContext(match)}\n'
        'Other options shown:\n${_resultsContext(results)}';
    _pendingDiscussOnly = true;
    await _send(_te
        ? '"${match.title}" ని మిగతా ఎంపికలతో పోల్చండి'
        : 'Compare "${match.title}" with the other options');
  }

  /// A declined request never dead-ends: the same need, other options.
  void _showAlternatives(String? dealId, List<Map<String, Object?>> rows) {
    final matches = [
      for (final row in rows) UniversalMatch.fromJson(row),
    ].where((m) => m.id.isNotEmpty).toList();
    setState(() {
      _turns.add(ConversationTurnRecord(
        text: matches.isEmpty
            ? (_te
                ? 'ఈ విక్రేత అంగీకరించలేదు. ఇదే అవసరానికి ఇప్పుడు ఇతర నమోదైన ఎంపికలు లేవు; మళ్లీ వెతకమంటారా?'
                : 'That seller declined. There are no other registered options for the same need right now -- shall I search again?')
            : (_te
                ? 'ఆ విక్రేత అంగీకరించలేదు. మీ అవసరం అలాగే ఉంది — ఇవి ఇతర ఎంపికలు:'
                : 'That seller declined. Your requirement is kept -- here are other options for the same need:'),
        isUser: false,
      ));
      if (matches.isNotEmpty) {
        _resultsByTurn[_turns.length - 1] = AskodoxChatResults(dealId: dealId, matches: matches, searched: true);
      }
    });
    unawaited(_saveSnapshot());
    _scrollBottom();
  }

  /// Seller not responding: Customer Care with the full context.
  Future<void> _dealSupport() async {
    final turn = _turns.lastIndexWhere((t) => !t.isUser);
    if (turn < 0) return;
    setState(() => _supportByTurn[turn] =
        const AskodoxSupportAssessment(AskodoxSupportNeed.immediate, category: 'SELLER_UNRESPONSIVE'));
    await _escalateToSupport(turn);
  }

  Timer? _lipSyncTimer;

  /// Sarvam audio: follow the player's real position so the friend's mouth
  /// stays on the words being heard.
  void _startLipSyncPolling(AskodoxCompanionVoice lips) {
    _lipSyncTimer?.cancel();
    _lipSyncTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      try {
        final progress = await _device.invokeMethod<Map<Object?, Object?>>('replyAudioProgress');
        final position = (progress?['position'] as num?)?.toInt();
        final duration = (progress?['duration'] as num?)?.toInt();
        if (position != null && duration != null && duration > 0) {
          lips.speechProgress(Duration(milliseconds: position), Duration(milliseconds: duration));
        }
      } catch (_) {
        _lipSyncTimer?.cancel();
      }
    });
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
    final lips = ref.read(askodoxCompanionVoiceProvider)..speechBegin(reply);
    try {
      final audio = await ref
          .read(askodoxReplySpeechServiceProvider)
          .sarvamAudio(reply, locale: language);
      if (!mounted || _voicePhase != _VoicePhase.speaking) return;
      if (audio != null) {
        lips.speechBegin(reply);
        _startLipSyncPolling(lips);
        final played = await _device.invokeMethod<bool>(
          'playReplyAudio',
          <String, Object?>{'bytes': audio, 'languageCode': language},
        );
        if (played == true) {
          lastReplyVoiceEngine = 'sarvam_bulbul_v3';
          return;
        }
      }
      _lipSyncTimer?.cancel();
      if (!mounted || _voicePhase != _VoicePhase.speaking) return;
      lastReplyVoiceEngine = 'device';
      lips.speechBegin(reply);
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
      _lipSyncTimer?.cancel();
      lips.speechEnd();
      if (mounted && _voicePhase == _VoicePhase.speaking) {
        setState(() => _voicePhase = _VoicePhase.idle);
      }
    }
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
    ref.watch(askodoxReplyLanguageProvider);
    final te = _te;
    _publishCompanion();
    final hubOpen = ref.watch(askodoxCompanionHubOpenProvider);
    return ColoredBox(
        color: const Color(0xFFF9FBFF),
        child: Stack(children: [
          Column(children: [
            // Results above, the companion in the middle, the current
            // conversation at the bottom next to the input (see _chat).
            Expanded(child: _active ? _chat(te) : _home(te)),
            _composer(te)
          ]),
          // The companion's actions appear only while the user is
          // interacting with it -- never as a permanent row of buttons.
          if (hubOpen)
            Positioned.fill(
              child: AskodoxCompanionHub(
                lang: _lang,
                onAction: _companionAction,
                onClose: () => ref.read(askodoxCompanionHubOpenProvider.notifier).state = false,
              ),
            ),
        ]));
  }

  /// The ONE companion state, shared with the nav avatar and the floating
  /// companion (same assistant, same conversation).
  void _publishCompanion() {
    final live = AskodoxCompanionLive(
      mood: _companionMood,
      listening: _voicePhase == _VoicePhase.recording,
      line: _companionGuidance(),
    );
    if (ref.read(askodoxCompanionLiveProvider) == live) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(askodoxCompanionLiveProvider.notifier).state = live;
    });
  }

  /// A tap on the companion: while listening it stops listening ("tap
  /// again to stop"); otherwise it opens / closes its actions.
  void _onCompanionTap() {
    if (_voicePhase == _VoicePhase.recording) {
      unawaited(_startVoice()); // stop and send
      return;
    }
    final hub = ref.read(askodoxCompanionHubOpenProvider.notifier);
    hub.state = !hub.state;
  }

  /// Voice, Chat, Camera, Photos, Video, Files, Location -- from the ring,
  /// the nav avatar or the floating companion -- into THIS conversation.
  Future<void> _companionAction(AskodoxHubAction action) async {
    ref.read(askodoxCompanionHubOpenProvider.notifier).state = false;
    switch (action) {
      case AskodoxHubAction.voice:
        if (!_sending) await _startVoice();
      case AskodoxHubAction.chat:
        _focusNode.requestFocus();
      case AskodoxHubAction.camera:
        await _pickAttachment('camera');
      case AskodoxHubAction.photos:
        await _pickAttachment('photos');
      case AskodoxHubAction.video:
        await _pickAttachment('video');
      case AskodoxHubAction.files:
        await _pickAttachment('files');
      case AskodoxHubAction.location:
        if (mounted) await context.push('/location');
    }
  }

  /// What the companion says right now, from the real conversation state
  /// (null = its normal line for the mood). Never a generic tip.
  String? _companionGuidance() {
    String pick({required String en, required String te, required String hi}) =>
        switch (_lang) { 'te' => te, 'hi' => hi, _ => en };
    if (_voicePhase == _VoicePhase.recording) {
      return pick(en: 'Listening… tap me again to stop.', te: 'వింటున్నాను… ఆపడానికి నన్ను మళ్లీ నొక్కండి.',
          hi: 'सुन रहे हैं… रोकने के लिए मुझे फिर से दबाएँ।');
    }
    if (_sending || _analyzingAttachments || _voicePhase != _VoicePhase.idle) return null;
    if (_catalogue != null) {
      return pick(en: 'Pick the categories you sell, or say "all".', te: 'మీరు అమ్మే విభాగాలు ఎంచుకోండి, లేదా "అన్నీ" అనండి.',
          hi: 'जो श्रेणियाँ आप बेचते हैं चुनें, या "सब" कहें।');
    }
    if (_pendingSignInAction != null) {
      return pick(en: 'Sign in once and I will send it for you.', te: 'ఒకసారి సైన్ ఇన్ చేయండి, నేను పంపుతాను.',
          hi: 'एक बार साइन इन करें, मैं भेज दूँगा।');
    }
    final results = _turns.isNotEmpty && !_turns.last.isUser ? _resultsByTurn[_turns.length - 1] : null;
    if (results == null) return null;
    if (results.sourcesWith('needs_location').isNotEmpty && results.matches.isEmpty) {
      return pick(en: 'Set your location and I will show shops near you.', te: 'మీ లొకేషన్ సెట్ చేయండి, దగ్గరి షాపులు చూపిస్తాను.',
          hi: 'अपनी लोकेशन सेट करें, पास की दुकानें दिखाऊँगा।');
    }
    final summary = AskodoxLocalOnlineSummary.of(results.matches);
    if (summary != null && summary.localPrice != null && summary.onlinePrice != null) {
      final local = '₹${summary.localPrice!.toStringAsFixed(0)}', online = '₹${summary.onlinePrice!.toStringAsFixed(0)}';
      return pick(
          en: 'Nearby from $local, online from $online. Tap a card and I will help with the next step.',
          te: 'దగ్గరలో $local నుండి, ఆన్‌లైన్ $online నుండి. ఒక కార్డ్ నొక్కండి, తర్వాత దశలో సహాయం చేస్తాను.',
          hi: 'पास में $local से, ऑनलाइन $online से। कोई कार्ड दबाएँ, आगे मैं मदद करूँगा।');
    }
    return null;
  }

  /// The friend's mood comes from what ASKODOX is actually doing (voice,
  /// sending, results) -- one conversation, one state.
  AskodoxCompanionMood get _companionMood {
    switch (_voicePhase) {
      case _VoicePhase.recording:
        return AskodoxCompanionMood.listening;
      case _VoicePhase.transcribing:
        return AskodoxCompanionMood.understanding;
      case _VoicePhase.thinking:
        return AskodoxCompanionMood.thinking;
      case _VoicePhase.speaking:
        return AskodoxCompanionMood.speaking;
      case _VoicePhase.idle:
        break;
    }
    if (_analyzingAttachments) return AskodoxCompanionMood.understanding;
    if (_companionError) return AskodoxCompanionMood.help;
    if (ref.watch(askodoxActionsInFlightProvider) > 0) return AskodoxCompanionMood.guiding;
    if (_sending) return AskodoxCompanionMood.thinking;
    if (_actionConfirmed) return AskodoxCompanionMood.success;
    if (_turns.isNotEmpty && !_turns.last.isUser) {
      final results = _resultsByTurn[_turns.length - 1];
      if (results != null && results.failed) return AskodoxCompanionMood.help;
      // ASKODOX asked for the one detail it still needs.
      if (results == null && (_lastAskedQuestion ?? '').trim().isNotEmpty) return AskodoxCompanionMood.suggesting;
      // Real options on screen: the companion turns to them and guides;
      // the cards stay fully usable.
      if (results != null && results.matches.isNotEmpty) return AskodoxCompanionMood.explaining;
    }
    return AskodoxCompanionMood.idle;
  }

  Widget _home(bool te) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          if (_leads.isNotEmpty)
            Card(
              key: const Key('askodoxLeadsInbox'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    te ? 'మీకు ${_leads.length} కొత్త కస్టమర్ అభ్యర్థనలు' : '${_leads.length} new customer request(s) for you',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  for (final lead in _leads.take(3))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(lead.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: _leadReplies.contains(lead.requestId)
                          ? Text(te ? 'పంపబడింది' : 'Sent')
                          : TextButton(
                              key: ValueKey('askodoxLeadReply-${lead.requestId}'),
                              onPressed: () => _replyToLead(lead),
                              child: Text(te ? 'నేను చేయగలను' : 'I can do this'),
                            ),
                    ),
                ]),
              ),
            ),
          const SizedBox(height: 24),
          // AI-first Home: the companion greets the user -- no shortcut grid,
          // no suggestion cards without a request. Tap it for Voice, Chat,
          // Camera, Photos, Video, Files or Location.
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            AskodoxCompanion(
                key: const Key('askodoxHomeOrb'),
                mood: _companionMood == AskodoxCompanionMood.idle ? AskodoxCompanionMood.greeting : _companionMood,
                size: 170,
                onTap: _onCompanionTap),
            Expanded(
              child: Container(
                key: const Key('askodoxHomeGreeting'),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                  ),
                  border: Border.all(color: const Color(0xFFE2DDFF)),
                  boxShadow: const [BoxShadow(color: Color(0x146C4DFF), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      _companionGuidance() ??
                          switch (_lang) {
                            'te' => 'నమస్తే! ఏం కావాలి? సహాయం చేద్దాం.',
                            'hi' => 'नमस्ते! बताइए, क्या चाहिए?',
                            _ => 'Hi! How can I help you today?',
                          },
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _ink, height: 1.25)),
                  const SizedBox(height: 6),
                  Text(
                      switch (_lang) {
                        'te' => 'నన్ను నొక్కండి -- మాట్లాడండి, ఫోటో లేదా ఫైల్ పంపండి, లేదా కింద టైప్ చేయండి.',
                        'hi' => 'मुझे दबाएँ -- बोलें, फ़ोटो या फ़ाइल भेजें, या नीचे लिखें।',
                        _ => 'Tap me to talk, send a photo or file -- or type below.',
                      },
                      style: const TextStyle(color: _muted, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
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


  /// Index of the user's latest message: where the current exchange starts.
  int get _currentExchangeStart {
    for (var i = _turns.length - 1; i >= 0; i--) {
      if (_turns[i].isUser) return i;
    }
    return 0;
  }

  /// The companion between the results and the conversation: its face,
  /// state and what it is saying / guiding right now.
  Widget _companionStage(bool te) => AskodoxCompanionBar(
        key: const Key('askodoxCompanionBar'),
        mood: _companionMood,
        telugu: te,
        lang: _lang,
        size: 88,
        results: _actionConfirmed ? 0 : _latestResults()?.matches.length ?? 0,
        onTap: _onCompanionTap,
        showLine: _voicePhase == _VoicePhase.idle || _voicePhase == _VoicePhase.recording,
        guidance: _companionGuidance(),
        subject: ref.watch(universalDealControllerProvider).deal?.subject,
        foundLabel: _lang == 'te' || _lang == 'en' || _lang == 'hi'
            ? null
            : askodoxChatLabel('found_pick', _lang, count: _latestResults()?.matches.length ?? 0),
      );

  /// A turn's message bubble and its notices.
  List<Widget> _turnHead(int index, ConversationTurnRecord turn, bool te) => [
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final attachment in turn.attachments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            switch (attachment['kind']) {
                              'video' => Icons.videocam_rounded,
                              'image' => Icons.image_rounded,
                              _ => Icons.description_rounded,
                            },
                            size: 16,
                            color: turn.isUser ? Colors.white : _blue,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(attachment['name'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: turn.isUser ? Colors.white : _ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    if (turn.text.isNotEmpty)
                      Text(turn.text,
                          style: TextStyle(
                              color: turn.isUser ? Colors.white : _ink,
                              height: 1.35,
                              fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            if (_signInTurn == index && _pendingSignInAction != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    key: const ValueKey('askodoxSignInToAct'),
                    onPressed: _sending ? null : _signInAndRetry,
                    icon: const Icon(Icons.phone_iphone_rounded),
                    label: Text(te ? 'సైన్ ఇన్ చేసి పంపండి' : 'Sign in and send'),
                  ),
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
      ];

  /// What a turn found: catalogue / result cards.
  List<Widget> _turnResults(int index, ConversationTurnRecord turn, bool te) => [
            if (_catalogueTurn == index && _catalogue != null)
              AskodoxCatalogueCard(
                template: _catalogue!,
                selected: _catalogueSelected,
                lang: _lang,
                onToggle: (key) => setState(() =>
                    _catalogueSelected.contains(key) ? _catalogueSelected.remove(key) : _catalogueSelected.add(key)),
                onSelectAll: () => setState(() => _catalogueSelected
                  ..clear()
                  ..addAll(_catalogue!.categories.map((c) => c.key))),
                onOpenEditor: _openCatalogueEditor,
              ),
            if (_resultsByTurn[index] case final results?)
              _ChatResultsView(
                key: ValueKey('askodoxChatResults-$index'),
                results: results,
                te: te,
                lang: _lang,
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
                onCompare: _sending || results.local.length < 2
                    ? null
                    : (match) => _compareMatch(results, match),
                onRequestSent: (match, orderId) => _onRequestSent(results.dealId, match, orderId),
                orderIdFor: (match) => _orderByMatchKey[_matchKey(results.dealId, match)],
                requestContext: () => _requestContextFor(results.dealId),
                pendingQuestion: _pendingSellerQuestion,
                refreshTick: _dealRefreshTick,
                onAlternatives: (rows) => _showAlternatives(results.dealId, rows),
                onSupport: _dealSupport,
                onRefer: _sending ? null : () => _referProvider(index, results),
                onJoin: _sending ? null : () => _joinAsProvider(index, results),
              ),
      ];

  /// Follow-ups under a turn: clarification choices, map pins, support.
  List<Widget> _turnFollowUps(int index, ConversationTurnRecord turn, bool te) => [
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
            if (index == _turns.length - 1 && !turn.isUser && _routePinsNeeded())
              Padding(
                key: const Key('askodoxRoutePins'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  ActionChip(
                    key: const Key('askodoxPickPickup'),
                    avatar: const Icon(Icons.trip_origin_rounded, size: 18),
                    label: Text(te ? 'పికప్ మ్యాప్‌లో' : 'Pickup on map'),
                    onPressed: _sending ? null : () => _pickRoutePoint(pickup: true),
                  ),
                  ActionChip(
                    key: const Key('askodoxPickDrop'),
                    avatar: const Icon(Icons.place_rounded, size: 18),
                    label: Text(te ? 'డ్రాప్ మ్యాప్‌లో' : 'Drop on map'),
                    onPressed: _sending ? null : () => _pickRoutePoint(pickup: false),
                  ),
                ]),
              ),
            if (_supportByTurn[index] case final support?)
              _SupportCard(
                key: ValueKey('askodoxSupport-$index'),
                te: te,
                critical: support.critical,
                supportCase: _supportCaseByTurn[index],
                onCheckReply: (caseId) {
                  final session = ref.read(authSessionProvider);
                  return ref.read(askodoxSupportEscalationServiceProvider).caseStatus(
                        caseId,
                        authToken: session.user == null ? null : session.tokenPlaceholder,
                      );
                },
                onChat: () => _escalateToSupport(index),
                onOpen: _openExternal,
              ),
      ];

  Widget _chat(bool te) => ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          // Earlier exchanges (their results + messages) scroll up...
          for (final (index, turn) in _turns.indexed)
            if (index < _currentExchangeStart) ...[
              ..._turnHead(index, turn, te),
              ..._turnResults(index, turn, te),
              ..._turnFollowUps(index, turn, te),
            ],
          // ...then the CURRENT exchange: its results first, the companion
          // in the middle, and the conversation itself at the bottom next to
          // the input -- however many results there are.
          for (final (index, turn) in _turns.indexed)
            if (index >= _currentExchangeStart) ..._turnResults(index, turn, te),
          _companionStage(te),
          for (final (index, turn) in _turns.indexed)
            if (index >= _currentExchangeStart) ...[
              ..._turnHead(index, turn, te),
              ..._turnFollowUps(index, turn, te),
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
        if (_attachments.isNotEmpty) _attachmentPreview(te),
        Row(children: [
        if (_voicePhase == _VoicePhase.recording)
          IconButton(
            key: const Key('askodoxVoiceCancel'),
            onPressed: _cancelVoice,
            tooltip: te ? 'రద్దు చేయండి' : 'Cancel voice',
            icon: const Icon(Icons.close_rounded, color: _muted)),
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
          // The docked companion above listens/thinks/speaks; the panel keeps
          // the plain mic/speaker cue.
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
              Flexible(
                child: Text(status,
                    key: const Key('askodoxVoiceStatus'),
                    style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
              ),
              if (listening) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                      switch (_lang) {
                        'te' => 'ఆపడానికి సహచరుడిని మళ్లీ నొక్కండి',
                        'hi' => 'रोकने के लिए साथी को फिर दबाएँ',
                        _ => 'Tap the companion again to stop',
                      },
                      key: const Key('askodoxVoiceStopHint'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final (index, attachment) in _attachments.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    Container(
                      key: ValueKey('askodoxAttachment-$index'),
                      width: 150,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        if (attachment.isImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(attachment.bytes,
                                width: 44, height: 44, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _attachmentIcon(attachment.kind)),
                          )
                        else
                          _attachmentIcon(attachment.kind),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(attachment.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        key: ValueKey('askodoxRemoveAttachment-$index'),
                        onTap: _sending || _analyzingAttachments
                            ? null
                            : () => setState(() => _attachments.removeAt(index)),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded, size: 16, color: _muted),
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          if (_analyzingAttachments)
            Row(key: const Key('askodoxAttachmentAnalyzing'), children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(child: Text(askodoxChatLabel('attach_analyzing', _lang))),
              TextButton(
                key: const Key('askodoxCancelAttachment'),
                onPressed: _cancelAttachmentAnalysis,
                child: Text(askodoxChatLabel('cancel', _lang)),
              ),
            ]),
        ]),
      );

  Widget _attachmentIcon(String kind) => SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          switch (kind) {
            'video' => Icons.video_file_outlined,
            'image' => Icons.image_outlined,
            _ => Icons.insert_drive_file_outlined,
          },
          color: _blue,
        ),
      );

  @override
  void dispose() {
    _device.setMethodCallHandler(null);
    _lipSyncTimer?.cancel();
    // (No ref use while disposing.)
    _voiceTimer?.cancel();
    _voiceTimer = null;
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
    this.onCheckReply,
  });

  final bool te;
  final bool critical;
  final AskodoxSupportCase? supportCase;
  final Future<Map<String, Object?>?> Function(String caseId)? onCheckReply;
  final Future<void> Function() onChat;
  final Future<void> Function(String uri) onOpen;

  @override
  State<_SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<_SupportCard> {
  bool _busy = false;
  String? _reply;

  Future<void> _check(String caseId) async {
    setState(() => _busy = true);
    final status = await widget.onCheckReply!(caseId);
    if (!mounted) return;
    final te = widget.te;
    setState(() {
      _busy = false;
      if (status == null) {
        _reply = te ? 'స్థితి ఇప్పుడు అందుబాటులో లేదు.' : 'Status is unavailable right now.';
      } else {
        final state = '${status['status'] ?? ''}';
        final note = status['resolution_note']?.toString();
        _reply = switch (state) {
          'RESOLVED' || 'CLOSED' => (te ? 'సపోర్ట్ పరిష్కరించింది: ' : 'Support resolved it: ') + (note ?? ''),
          'WAITING_FOR_USER' => te ? 'సపోర్ట్ మీ నుండి సమాచారం కోరుతోంది.' : 'Support needs more information from you.',
          'IN_PROGRESS' => te ? 'సపోర్ట్ టీమ్ పని చేస్తోంది.' : 'A support agent is working on it.',
          _ => te ? 'కేసు తెరిచి ఉంది; ఇంకా సమాధానం లేదు.' : 'Case open; no reply yet.',
        };
      }
    });
  }

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
            if (widget.onCheckReply != null)
              TextButton.icon(
                key: const Key('askodoxSupportCheckReply'),
                onPressed: _busy ? null : () => _check(supportCase.caseId),
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: Text(te ? 'సమాధానం చూడండి' : 'Check for reply'),
              ),
          ]),
          if (_reply != null)
            Text(_reply!, key: const Key('askodoxSupportReply'), style: const TextStyle(color: _ink)),
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
    this.lang = 'en',
    required this.retrying,
    required this.isActionable,
    required this.wasRequested,
    required this.onRequestSent,
    this.onRefer,
    this.onJoin,
    this.onAsk,
    this.onRetry,
    this.onCompare,
    this.orderIdFor,
    this.requestContext,
    this.pendingQuestion,
    this.refreshTick = 0,
    this.onAlternatives,
    this.onSupport,
  });

  final AskodoxChatResults results;
  final bool te;

  /// The conversation language (labels in hi/or/... come from the table).
  final String lang;
  final bool retrying;

  String _l(String key, String telugu, String english) =>
      lang == 'te' || lang == 'en' ? (te ? telugu : english) : askodoxChatLabel(key, lang);
  final VoidCallback? onRetry;
  final VoidCallback? onJoin;
  final bool Function(UniversalMatch match) isActionable;
  final bool Function(UniversalMatch match) wasRequested;
  final void Function(UniversalMatch match)? onAsk;
  final void Function(UniversalMatch match)? onCompare;
  final void Function(UniversalMatch match, String? orderId) onRequestSent;
  final String? Function(UniversalMatch match)? orderIdFor;
  final Map<String, Object?> Function()? requestContext;
  final String? pendingQuestion;
  final int refreshTick;
  final void Function(List<Map<String, Object?>> rows)? onAlternatives;
  final Future<void> Function()? onSupport;

  /// "Know someone who does this? Refer them to ASKODOX."
  final VoidCallback? onRefer;

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
        for (final (i, tip) in results.advice.indexed)
          _notice(
            key: ValueKey('askodoxAdvice-$i'),
            icon: Icons.lightbulb_outline_rounded,
            text: te ? tip.textTe : tip.text,
          ),
        if (results.nextActions.contains('refer_provider') && onRefer != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // Small, contextual: shown only when no ASKODOX provider has this
            // yet (seller, service provider, employer -- anyone). The online
            // options above stay; these two grow the local network.
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (onJoin != null)
                ActionChip(
                  key: const Key('askodoxJoinAsProvider'),
                  onPressed: onJoin,
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.storefront_rounded, size: 16),
                  label: Text(_l('join', 'మీరు విక్రేత/ప్రొవైడరా? ASKODOXలో చేరండి', 'Seller or provider? Join ASKODOX')),
                ),
              ActionChip(
                key: const Key('askodoxReferProvider'),
                onPressed: onRefer,
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: Text(_l('refer', 'ఎవరైనా తెలుసా? సూచించండి', 'Know someone? Refer')),
              ),
            ]),
          ),
        if (results.scopeMessage != null)
          _notice(
            key: const Key('askodoxResultsScope'),
            icon: Icons.travel_explore_rounded,
            text: results.scopeMessage!,
          ),
        if (results.searched && results.matches.isEmpty)
          _notice(
            key: const Key('askodoxResultsNone'),
            icon: Icons.search_off_rounded,
            text: askodoxNoResultsText(results, telugu: te),
          )
        else if ((results.broadcastSent ?? 0) > 0)
          _notice(
            key: const Key('askodoxResultsBroadcast'),
            icon: Icons.campaign_outlined,
            text: te
                ? 'మీ అభ్యర్థనను ${results.broadcastSent} నమోదైన ASKODOX ప్రొవైడర్లకు కూడా పంపాను.'
                : 'Also sent to ${results.broadcastSent} registered ASKODOX provider(s) nearby.',
          ),
        if (AskodoxLocalOnlineSummary.of(results.matches) case final summary?) _compareStrip(summary),
        // Several kinds of results (local, sponsored, online, ...): ONE
        // compact horizontal comparison, like the approved reference. A
        // single kind, or an option with a live request/order, keeps the
        // sectioned layout below.
        if (_comparison case final groups?
            when !groups.any((g) => g.$1 == AskodoxCompareKind.local) &&
                groups.any((g) => g.$1 == AskodoxCompareKind.online))
          _heading(askodoxSegmentTitle(AskodoxResultSegment.online, telugu: te, hasLocal: false, lang: lang),
              Icons.public_rounded),
        if (_comparison case final groups?)
          _ComparisonBoard(
            key: const Key('askodoxComparison'),
            groups: groups,
            lang: te ? 'te' : lang,
            card: (match, kind) => _card(match, compact: true, kind: kind),
          )
        else
        for (final (segment, rows) in askodoxGroupResults(results.matches)) ...[
          _heading(askodoxSegmentTitle(segment, telugu: te, hasLocal: hasLocal, lang: lang),
              _segmentIcon(segment)),
          // Several choices: ONE compact horizontal rail (swipe), so the
          // options stay visible without a long vertical feed. A single
          // option, or one with a live request/order, stays full width.
          if (rows.length >= 2 && rows.every((m) => (orderIdFor?.call(m) ?? '').isEmpty))
            SingleChildScrollView(
              key: ValueKey('askodoxRail-${segment.name}'),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final match in rows) _card(match, compact: true)],
              ),
            )
          else
            for (final match in rows) _card(match),
        ],
        if (results.sourcesWith('needs_location').isNotEmpty)
          Padding(
            key: const Key('askodoxNeedsLocation'),
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              Text(te ? 'దగ్గరలోని షాపుల కోసం మీ ప్రాంతం చెప్పండి.' : 'Set your location to see nearby shops.',
                  style: const TextStyle(color: _muted, fontSize: 12)),
              TextButton(
                key: const Key('askodoxSetLocation'),
                onPressed: () => context.push('/location'),
                child: Text(te ? 'ప్రాంతం ఎంచుకోండి' : 'Set location'),
              ),
            ]),
          ),
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

  List<(AskodoxCompareKind, List<UniversalMatch>)>? get _comparison {
    if (results.matches.any((m) => (orderIdFor?.call(m) ?? '').isNotEmpty)) return null;
    final groups = askodoxCompareGroups(results.matches);
    // Two or more options (of any kinds) compare side by side; a single
    // option stays a full card.
    return results.matches.length >= 2 ? groups : null;
  }

  Widget _card(UniversalMatch match, {bool compact = false, AskodoxCompareKind? kind}) => _MatchCard(
        match: match,
        compact: compact,
        kind: kind,
        dealId: results.dealId,
        te: te,
        actionable: isActionable(match),
        alreadySent: wasRequested(match),
        onAsk: onAsk == null ? null : () => onAsk!(match),
        onCompare: onCompare == null ? null : () => onCompare!(match),
        onRequestSent: (orderId) => onRequestSent(match, orderId),
        orderId: orderIdFor?.call(match),
        requestContext: requestContext,
        pendingQuestion: pendingQuestion,
        refreshTick: refreshTick,
        onAlternatives: onAlternatives,
        onSupport: onSupport,
      );

  /// One honest line about sources that returned nothing or are down, so
  /// no section is ever faked.
  String? _sourceNote(bool te) {
    String label(String key) => switch (key) {
          'askodox' => te ? 'ASKODOX విక్రేతలు' : 'ASKODOX sellers',
          'nearby' => te ? 'దగ్గరలోని షాపులు' : 'nearby shops',
          'used_deals' => te ? 'వాడినవి / డీల్స్' : 'used & deals',
          'online' => te ? 'ఆన్‌లైన్ స్టోర్లు' : 'online stores',
          'videos' => te ? 'వీడియోలు' : 'videos',
          'jobs' => te ? 'ఉద్యోగ సైట్లు' : 'job sites',
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
        AskodoxResultSegment.jobs => Icons.work_outline_rounded,
        AskodoxResultSegment.online => Icons.public_rounded,
        AskodoxResultSegment.partner => Icons.storefront_rounded,
        AskodoxResultSegment.sponsored => Icons.campaign_rounded,
        AskodoxResultSegment.video => Icons.play_circle_outline_rounded,
      };

  /// Nearby vs online in one line each -- real prices only (a page price is
  /// marked), nearest distance, the online source.
  Widget _compareStrip(AskodoxLocalOnlineSummary s) {
    String money(double? v) => v == null ? _l('no_price', 'ధర అడగాలి', 'price on request') : '₹${v.toStringAsFixed(0)}';
    return Container(
      key: const Key('askodoxLocalOnlineCompare'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E0FF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_l('local_vs_online', 'దగ్గరలో vs ఆన్‌లైన్', 'Nearby vs online'),
            style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.near_me_rounded, size: 16, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_l('nearby_from', 'దగ్గరలో', 'Nearby from')} ${money(s.localPrice)}'
              '${s.localDistanceKm == null ? '' : ' · ${s.localDistanceKm!.toStringAsFixed(1)} km'} · ${s.localCount}',
              key: const Key('askodoxCompareLocal'),
            ),
          ),
        ]),
        Row(children: [
          const Icon(Icons.public_rounded, size: 16, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_l('online_from', 'ఆన్‌లైన్', 'Online from')} ${money(s.onlinePrice)}'
              '${s.onlinePrice != null && !s.onlineVerified ? (te ? ' (పేజీలో)' : ' (page price)') : ''}'
              '${s.onlineSource == null ? '' : ' · ${s.onlineSource}'} · ${s.onlineCount}',
              key: const Key('askodoxCompareOnline'),
            ),
          ),
        ]),
      ]),
    );
  }

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

Color _kindColor(AskodoxCompareKind kind) => switch (kind) {
      AskodoxCompareKind.local => const Color(0xFF0F7B3F),
      AskodoxCompareKind.jobs => const Color(0xFF1769FF),
      AskodoxCompareKind.deals => const Color(0xFFD9344F),
      AskodoxCompareKind.sponsored => const Color(0xFF7A5A00),
      AskodoxCompareKind.online => const Color(0xFF1769FF),
      AskodoxCompareKind.affiliate => const Color(0xFF6C4DFF),
      AskodoxCompareKind.used => const Color(0xFF8A5A00),
      AskodoxCompareKind.surplus => const Color(0xFF00897B),
      AskodoxCompareKind.videos => const Color(0xFFD9344F),
    };

/// The compact comparison after a request: a row of kind tabs (only the
/// kinds this request returned, with counts) above ONE horizontal rail of
/// labelled cards. "All" keeps every kind in column order.
class _ComparisonBoard extends StatefulWidget {
  const _ComparisonBoard({super.key, required this.groups, required this.card, required this.lang});

  final List<(AskodoxCompareKind, List<UniversalMatch>)> groups;
  final Widget Function(UniversalMatch match, AskodoxCompareKind kind) card;
  final String lang;

  @override
  State<_ComparisonBoard> createState() => _ComparisonBoardState();
}

class _ComparisonBoardState extends State<_ComparisonBoard> {
  AskodoxCompareKind? _only;

  @override
  Widget build(BuildContext context) {
    final all = switch (widget.lang) { 'te' => 'అన్నీ', 'hi' => 'सभी', _ => 'All' };
    final total = widget.groups.fold<int>(0, (n, g) => n + g.$2.length);
    Widget tab(String key, String label, int count, Color color, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            key: ValueKey('askodoxCompareTab-$key'),
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? color : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? color : const Color(0xFFE1E8F2)),
              ),
              child: Text('$label  $count',
                  style: TextStyle(
                      color: selected ? Colors.white : color, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // One kind only: its label is on every card; no tab row needed.
      if (widget.groups.length >= 2)
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          tab('all', all, total, const Color(0xFF10204A), _only == null, () => setState(() => _only = null)),
          for (final (kind, rows) in widget.groups)
            tab(kind.name, askodoxCompareLabel(kind, widget.lang), rows.length, _kindColor(kind), _only == kind,
                () => setState(() => _only = _only == kind ? null : kind)),
        ]),
      ),
      SingleChildScrollView(
        key: const Key('askodoxComparisonRail'),
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (kind, rows) in widget.groups)
            if (_only == null || _only == kind)
              for (final match in rows) widget.card(match, kind),
        ]),
      ),
    ]);
  }
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
    this.onCompare,
    this.orderId,
    this.requestContext,
    this.pendingQuestion,
    this.refreshTick = 0,
    this.onAlternatives,
    this.onSupport,
    this.compact = false,
    this.kind,
  });
  final UniversalMatch match;

  /// The comparison column this card sits in (its visible label).
  final AskodoxCompareKind? kind;
  final String? dealId;
  final bool te;

  /// A card inside a horizontal rail: fixed width, short title, only the
  /// essential facts (price/salary, distance/place, source) -- the rest is
  /// behind Details.
  final bool compact;

  /// AI-first: Send request / Connect is exposed only once the user has
  /// discussed this option with ASKODOX or asked for the seller.
  final bool actionable;
  final bool alreadySent;
  final VoidCallback? onAsk;
  final VoidCallback? onCompare;
  final void Function(String? orderId) onRequestSent;
  final String? orderId;
  final Map<String, Object?> Function()? requestContext;
  final String? pendingQuestion;
  final int refreshTick;
  final void Function(List<Map<String, Object?>> rows)? onAlternatives;
  final Future<void> Function()? onSupport;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  static final _compact = FilledButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static final _compactOutline = OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static final _compactText = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  bool _placing = false;
  bool _orderFailed = false;
  bool _needsSignIn = false;
  String? _orderStatusMessage;

  UniversalMatch get _match => widget.match;

  /// A seller's own photo is served by ASKODOX as a relative path.
  String _resolvedImage(String url) {
    if (!url.startsWith('/')) return url;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return base == null ? url : base.resolve(url).toString();
  }

  Future<void> _openDirections(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _share() async {
    final m = _match;
    final text = [
      m.title,
      if (m.price != null) '₹${m.price!.toStringAsFixed(0)}${m.priceVerified ? '' : ' (page)'}',
      if (m.locationLabel?.trim().isNotEmpty == true) m.locationLabel!.trim(),
      if (m.destinationUrl?.trim().isNotEmpty == true) m.destinationUrl!.trim(),
      'via ASKODOX',
    ].join(' · ');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l('copied', 'కాపీ అయింది -- ఎక్కడైనా పేస్ట్ చేసి షేర్ చేయండి.', 'Copied -- paste it anywhere to share.'))));
    }
  }
  bool get _te => widget.te;
  ChatResultAction get _action => chatResultActionFor(_match);

  String _l(String key, String telugu, String english) {
    final lang = ref.watch(askodoxReplyLanguageProvider);
    return lang == 'te' || lang == 'en' ? (_te ? telugu : english) : askodoxChatLabel(key, lang);
  }

  /// Videos play inside ASKODOX; back returns to this exact chat position.
  Future<void> _openVideo() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => AskodoxVideoViewerScreen(video: _match, telugu: _te),
    ));
    if (result == askodoxVideoAskResult) {
      widget.onAsk?.call();
    } else if (result != null && result.startsWith(askodoxVideoFollowUpPrefix)) {
      // "Find near me" / "Show deals"...: the same conversation, same discovery.
      final ask = result.substring(askodoxVideoFollowUpPrefix.length).trim();
      if (ask.isNotEmpty) ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(ask);
    }
  }

  Future<void> _openDestination() async {
    // Partner rows open through ASKODOX's tracked redirect; the tap itself
    // is reported as a click (fire-and-forget, never blocks opening).
    final tracker = ref.read(askodoxPartnerTrackerProvider);
    final uri = tracker.openUri(_match);
    if (uri == null) return;
    tracker.track(_match, 'click');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  /// Phone + OTP sign-in, then the same Send request runs again.
  Future<void> _signInAndSend() async {
    await context.push<bool>('/onboarding?signin=1');
    if (!mounted || ref.read(authSessionProvider).user == null) return;
    await _sendRequest();
  }

  Future<void> _sendRequest() async {
    if (_placing) return;
    setState(() {
      _placing = true;
      _orderStatusMessage = null;
      _orderFailed = false;
    });
    // Same executor as a typed "yes / order it" in chat.
    final result = await askodoxExecuteMatchAction(
      ref,
      match: _match,
      dealId: widget.dealId,
      telugu: _te,
      requestContext: widget.requestContext?.call(),
      question: widget.pendingQuestion,
    );
    if (!mounted) return;
    if (result.success) widget.onRequestSent(result.order?.id);
    setState(() {
      _placing = false;
      _needsSignIn = result.needsSignIn;
      _orderFailed = !result.success;
      _orderStatusMessage = result.success
          ? (_te
              ? 'అభ్యర్థన పంపబడింది. వారు అంగీకరించిన తర్వాతే ఇది నిర్ధారిత డీల్ అవుతుంది, కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
              : 'Request sent. It becomes a confirmed deal -- and contact details are shared -- only after they accept.')
          : (result.message ?? '').toLowerCase().contains('sign in')
              // Sign-in is needed only to act (send/contact), never to browse.
              ? (_te
                  ? 'అభ్యర్థన పంపడానికి సైన్ ఇన్ చేయండి. ఫలితాలు చూడడానికి సైన్ ఇన్ అవసరం లేదు.'
                  : 'Sign in to send this request. Browsing results never needs sign-in.')
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
    // A price only found in page text is labelled as such, never shown as
    // a confirmed price.
    final price = match.price == null
        ? null
        : match.priceVerified
            ? '₹${match.price!.toStringAsFixed(0)}'
            : (_te
                ? 'పేజీలో ₹${match.price!.toStringAsFixed(0)}'
                : 'Page mentions ₹${match.price!.toStringAsFixed(0)}');
    final score = match.score == null
        ? null
        : (match.score! <= 1 ? match.score! * 100 : match.score!);
    final placed = widget.alreadySent ||
        (_orderStatusMessage != null && !_orderFailed);
    final requestable = action == ChatResultAction.connect ||
        action == ChatResultAction.sendRequest;
    final showRequest = requestable && (widget.actionable || placed);
    final compact = widget.compact;
    return Container(
      key: ValueKey('askodoxResultCard-${match.source}-${match.id}'),
      width: compact ? 272 : null,
      margin: compact ? const EdgeInsets.only(right: 10, bottom: 10) : const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The column label (LOCAL / ONLINE / DEALS ...); paid rows carry
        // their Sponsored / Promoted badge instead.
        if (widget.kind case final kind? when match.paidPlacementLabel == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              key: ValueKey('askodoxKindLabel-${match.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _kindColor(kind).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(askodoxCompareLabel(kind, _te ? 'te' : 'en').toUpperCase(),
                  style: TextStyle(color: _kindColor(kind), fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: .6)),
            ),
          ),
        if (compact && action != ChatResultAction.watchVideo && _match.imageUrl?.trim().isNotEmpty == true) ...[
          ClipRRect(
            key: ValueKey('askodoxCardImage-${match.id}'),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 112,
              width: double.infinity,
              child: Image.network(_resolvedImage(_match.imageUrl!),
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: _sourceIcon())),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
          if (!(compact && _match.imageUrl?.trim().isNotEmpty == true)) ...[
          SizedBox(
              width: 64,
              height: 64,
              child: _match.imageUrl?.trim().isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_resolvedImage(_match.imageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _sourceIcon()))
                  : _sourceIcon()),
          const SizedBox(width: 12),
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (match.paidPlacementLabel case final paid?)
                  Container(
                    key: ValueKey('askodoxPaidBadge-${match.id}'),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4D6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE0B64A)),
                    ),
                    child: Text(
                        paid == 'Promoted'
                            ? (te ? 'ప్రమోట్ చేయబడింది' : 'Promoted')
                            : (te ? 'స్పాన్సర్డ్' : 'Sponsored'),
                        style: const TextStyle(
                            color: Color(0xFF7A5A00), fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                Text(match.title,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _ink, fontWeight: FontWeight.w900, fontSize: compact ? 15 : 16)),
                if (match.subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  // A long page snippet never becomes a paragraph: the full
                  // text is behind Details.
                  Text(match.subtitle!,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _muted,
                          height: 1.35,
                          fontWeight: FontWeight.w500))
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (widget.kind == null) _meta(_sourceLabel(_match.source)),
                  if (match.sourceName?.trim().isNotEmpty == true)
                    _meta(match.sourceName!.trim()),
                  if (match.duration?.trim().isNotEmpty == true)
                    _meta(match.duration!.trim()),
                  if (score != null && !compact) _meta('${score.toStringAsFixed(0)}% match'),
                  if (match.ratingAverage != null)
                    _meta(
                        '★ ${match.ratingAverage!.toStringAsFixed(1)} (${match.reviewCount})'),
                  if (distance != null) _meta(distance),
                  if (price != null) _meta(price),
                  if (match.salaryText?.trim().isNotEmpty == true)
                    _meta(te ? 'జీతం (పేజీ ప్రకారం): ${match.salaryText}' : 'Salary (as listed): ${match.salaryText}'),
                  if (match.offerTitle?.trim().isNotEmpty == true) _meta('🏷 ${match.offerTitle!.trim()}'),
                  if (match.benefits != null)
                    AskodoxBenefitsChip(match: match, lang: ref.watch(askodoxReplyLanguageProvider)),
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
          if (_needsSignIn)
            FilledButton.icon(
              key: ValueKey('askodoxCardSignIn-${match.id}'),
              onPressed: _signInAndSend,
              icon: const Icon(Icons.phone_iphone_rounded, size: 16),
              label: Text(te ? 'సైన్ ఇన్ చేసి పంపండి' : 'Sign in and send'),
            ),
          const SizedBox(height: 8),
        ],
        // Compact, left-aligned actions side by side; they wrap to the next
        // row on small screens instead of stacking full-width blocks.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if ((requestable && !showRequest) || (!requestable && widget.onAsk != null))
              FilledButton.tonalIcon(
                key: ValueKey('askodoxAsk-${match.id}'),
                onPressed: widget.onAsk,
                style: _compact,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(compact
                    ? _l('chat', 'చాట్', 'Chat')
                    : (te ? 'దీని గురించి ASKODOXని అడగండి' : 'Ask ASKODOX about this')),
              ),
            if (showRequest)
              FilledButton(
                onPressed: (_placing || placed) ? null : _sendRequest,
                style: _compact.merge(FilledButton.styleFrom(backgroundColor: _blue)),
                child: _placing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        placed
                            ? (te ? 'అభ్యర్థన పంపబడింది' : 'Request sent')
                            : _orderFailed
                                ? (te ? 'మళ్లీ ప్రయత్నించండి' : 'Retry request')
                                : action == ChatResultAction.connect
                                    ? (te ? 'కనెక్ట్ అభ్యర్థన పంపండి' : 'Connect')
                                    : _l('send_request', 'అభ్యర్థన పంపండి', 'Send request'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
              ),
            if (match.destinationUrl?.trim().isNotEmpty == true)
              OutlinedButton.icon(
                key: ValueKey('askodoxOpen-${match.id}'),
                onPressed: action == ChatResultAction.watchVideo ? _openVideo : _openDestination,
                style: _compactOutline,
                icon: Icon(
                    action == ChatResultAction.watchVideo ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
                    size: 16),
                label: Text(action == ChatResultAction.watchVideo
                    ? (te ? 'వీడియో చూడండి' : 'Watch')
                    : action == ChatResultAction.openLink
                        ? (match.isJob ? (te ? 'తెరిచి అప్లై చేయండి' : 'Open & apply') : _l('open', 'తెరవండి', 'Open'))
                        : (te ? 'వివరాలు చూడండి' : 'View details')),
              ),
            if (compact && widget.onCompare != null && action != ChatResultAction.watchVideo)
              IconButton(
                key: ValueKey('askodoxCompare-${match.id}'),
                tooltip: _l('compare', 'పోల్చండి', 'Compare'),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onCompare,
                icon: const Icon(Icons.compare_arrows_rounded, size: 20),
              ),
            if (!compact && widget.onCompare != null && action != ChatResultAction.watchVideo)
              TextButton.icon(
                key: ValueKey('askodoxCompare-${match.id}'),
                onPressed: widget.onCompare,
                style: _compactText,
                icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                label: Text(_l('compare', 'పోల్చండి', 'Compare')),
              ),
            if (compact && action != ChatResultAction.watchVideo && match.source != 'online' && !match.affiliate)
              if (askodoxDirectionsUri(match) case final directions?)
                IconButton(
                  key: ValueKey('askodoxDirections-${match.id}'),
                  tooltip: _l('directions', 'దారి చూపించు', 'Directions'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openDirections(directions),
                  icon: const Icon(Icons.directions_rounded, size: 20),
                ),
            if (!compact && action != ChatResultAction.watchVideo && match.source != 'online' && !match.affiliate)
              if (askodoxDirectionsUri(match) case final directions?)
                TextButton.icon(
                  key: ValueKey('askodoxDirections-${match.id}'),
                  onPressed: () => _openDirections(directions),
                  style: _compactText,
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: Text(_l('directions', 'దారి చూపించు', 'Directions')),
                ),
            Builder(builder: (context) {
              final saved = ref.watch(askodoxSavedOptionsProvider).any(
                  (s) => AskodoxSavedOptions.keyOf(s) == AskodoxSavedOptions.keyOf(match));
              return IconButton(
                key: ValueKey('askodoxSave-${match.id}'),
                tooltip: saved ? _l('saved', 'సేవ్ అయింది', 'Saved') : _l('save', 'సేవ్', 'Save'),
                visualDensity: VisualDensity.compact,
                icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 20,
                    color: saved ? _blue : null),
                onPressed: () => ref.read(askodoxSavedOptionsProvider.notifier).toggle(match),
              );
            }),
            IconButton(
              key: ValueKey('askodoxShare-${match.id}'),
              tooltip: _l('share', 'షేర్', 'Share'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: _share,
            ),
            TextButton.icon(
              key: ValueKey('askodoxDetails-${match.id}'),
              onPressed: () {
                ref.read(askodoxPartnerTrackerProvider).track(match, 'card_view');
                _showDetails(context);
              },
              style: _compactText,
              icon: const Icon(Icons.info_outline_rounded, size: 16),
              label: Text(compact ? _l('view', 'చూడండి', 'View') : _l('details', 'వివరాలు', 'Details')),
            ),
          ],
        ),
        if (showRequest)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
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
          ),
        if (widget.orderId != null && widget.orderId!.isNotEmpty)
          AskodoxDealPanel(
            key: ValueKey('askodoxDeal-${widget.orderId}-${widget.refreshTick}'),
            orderId: widget.orderId!,
            te: te,
            onAlternatives: widget.onAlternatives,
            onSupport: widget.onSupport,
          ),
        if (match.destinationUrl?.trim().isNotEmpty == true) ...[
          if (match.disclosure?.trim().isNotEmpty == true || match.affiliate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  match.disclosure?.trim().isNotEmpty == true
                      ? askodoxVideoDisclosure(match.disclosure, telugu: _te)
                      : 'Affiliate link',
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ),
        ],
      ]),
    );
  }

  /// Every verified field of the option -- nothing invented.
  void _showDetails(BuildContext context) {
    final m = _match;
    final te = _te;
    final rows = <(String, String)>[
      (te ? 'పేరు' : 'Name', m.title),
      if (m.subtitle?.trim().isNotEmpty == true) (te ? 'వివరణ' : 'Description', m.subtitle!.trim()),
      (te ? 'మూలం' : 'Source', [_sourceLabel(m.source), if (m.sourceName?.trim().isNotEmpty == true) m.sourceName!.trim()].join(' · ')),
      if (m.segment?.trim().isNotEmpty == true) (te ? 'రకం' : 'Type', askodoxSegmentLabel(m.segment!)),
      if (m.price != null)
        (te ? 'ధర' : 'Price', '₹${m.price!.toStringAsFixed(0)}${m.priceVerified ? '' : (te ? ' (పేజీలో, నిర్ధారించలేదు)' : ' (from the page, not verified)')}'),
      if (m.salaryText?.trim().isNotEmpty == true) (te ? 'జీతం' : 'Salary', m.salaryText!.trim()),
      if (m.distanceKm != null) (te ? 'దూరం' : 'Distance', '${m.distanceKm!.toStringAsFixed(1)} km'),
      if (m.locationLabel?.trim().isNotEmpty == true) (te ? 'ప్రదేశం' : 'Location', m.locationLabel!.trim()),
      if (m.availability?.trim().isNotEmpty == true) (te ? 'అందుబాటు' : 'Availability', m.availability!.trim()),
      if (m.ratingAverage != null) (te ? 'రేటింగ్' : 'Rating', '★ ${m.ratingAverage!.toStringAsFixed(1)} (${m.reviewCount})'),
      if (m.destinationUrl?.trim().isNotEmpty == true) (te ? 'లింక్' : 'Link', m.destinationUrl!.trim()),
      if (m.affiliate || m.disclosure?.trim().isNotEmpty == true)
        (te ? 'గమనిక' : 'Note', m.disclosure?.trim().isNotEmpty == true ? m.disclosure!.trim() : 'Affiliate link'),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          key: const Key('askodoxDetailsSheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: value),
                ])),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                te
                    ? 'స్టాక్, ఫైనల్ ధర, డెలివరీని విక్రేత మాత్రమే నిర్ధారించగలరు.'
                    : 'Stock, final price and delivery are confirmed only by the seller/provider.',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
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
