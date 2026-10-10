import '../../../core/flags/askodox_remote_flags.dart';
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
import '../../location/domain/geo_models.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../../selling/data/seller_listing_repository.dart';
import '../application/conversation_archive.dart';
import '../application/match_action_executor.dart';
import '../../companion/companion_hub.dart';
import '../application/saved_options.dart';
import '../domain/follow_up_router.dart';
import '../domain/search_readiness.dart';
import '../../../services/self_heal_reporter.dart';
import '../data/greeting_repository.dart';
import '../domain/attachment_intent.dart';
import '../domain/result_board.dart';
import '../../../shared/widgets/rich_reply.dart';
import '../domain/conversation_closing.dart';
import '../domain/place_phrase.dart';
import '../../profile/data/user_profile_repository.dart';
import '../../selling/data/catalogue_repository.dart';
import '../../selling/domain/seller_catalogue.dart';
import '../../selling/presentation/catalogue_widgets.dart';
import '../../growth/data/growth_repository.dart';
import '../../mobility/application/mobility_draft.dart' show MobilityDraft, askodoxMobilityDraftProvider, askodoxMobilityPoint;
import '../../mobility/data/mobility_repository.dart';
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
import '../data/taxonomy_repository.dart';
import 'video_viewer_screen.dart';
import 'video_study_panel.dart';
import '../../guide/in_app_guide.dart';
import '../domain/result_board_tabs.dart';
import 'result_board_tab_row.dart';
import 'attachment_menu.dart';

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
    extends ConsumerState<AskodoxPrimaryHomeScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _store = ConversationTurnStore();
  final List<ConversationTurnRecord> _turns = [];

  // Rich results embedded in the conversation, keyed by the index of the
  // assistant turn they belong to. Earlier result sets stay in the history
  // while the user refines, like any other chat message.
  final Map<int, AskodoxChatResults> _resultsByTurn = {};

  /// One-time advice memory for THIS conversation: concerns the brain has
  /// already explained (key / summary / severity), sent back every turn.
  List<Map<String, Object?>> _adviceLedger = const [];
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

  /// The next message is a search ASKODOX itself offered (a video's "Find
  /// near me" / "Book a local service" ...): search with what is known.
  bool _pendingForcedSearch = false;
  bool _pendingDiscussOnly = false;

  /// The place the user asked for in THIS conversation ("AC shops in
  /// Guntur"): follow-ups that name no place keep it until the user says
  /// "near me" or hand-picks another place. Separate from the device /
  /// header place.
  DealLocation? _requestedPlace;

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

  /// The field the Universal Advisor asked about last turn (budget, usage,
  /// size...): the next short reply answers THAT field only.
  String? _pendingAdvisorField;

  /// Guidance already given in this conversation (never repeated).
  final Set<String> _guidanceGiven = {};
  // Real attachments waiting in the composer (bytes + MIME), analyzed by
  // the backend when sent -- never reduced to a file name.
  final List<ChatAttachment> _attachments = [];

  /// Attachments whose analysis failed in the last send: they stay in the
  /// composer (with their previews) so the customer can retry or remove them.
  List<ChatAttachment> _keptAttachments = const [];
  bool _staleLocationNoticeShown = false;

  /// The last listing failed because sign-in is missing / rejected.
  bool _listingNeedsSignIn = false;
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
  bool _voiceFallbackNoticeShown = false;

  /// ONE audio lifecycle: every spoken reply takes a new turn number; Stop
  /// and a newer reply bump it, so an older reply whose audio was cut off
  /// can never fall back to device TTS and talk over the new one.
  int _speechTurn = 0;

  /// The reply being spoken, which engine speaks it ('sarvam' / 'device'),
  /// where the device voice reached (native speechRange), pause and mute.
  String? _speakingText;
  String _speakingUserText = '';
  String _speakingEngine = '';
  int _speechRangeStart = 0;
  bool _speechPaused = false;
  String? _pausedRemainder;

  /// Spoken chunks still to come after the current one (device pause/resume
  /// continues with them).
  List<String> _speechQueue = const [];

  /// While a long reply is spoken, its text appears as it is read: the turn
  /// and how much of its markup is shown (null = the whole reply).
  int? _revealTurn;
  int? _revealEnd;
  Timer? _revealTimer;

  void _clearReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (_revealTurn != null && mounted) {
      setState(() {
        _revealTurn = null;
        _revealEnd = null;
      });
    }
  }

  /// Types [from]..[to] of the revealed turn over [duration] (word steps).
  void _typeReveal(int from, int to, Duration duration) {
    _revealTimer?.cancel();
    final steps = ((to - from) / 6).ceil().clamp(1, 400);
    final tick = Duration(milliseconds: (duration.inMilliseconds / steps).round().clamp(25, 400));
    var i = 0;
    setState(() => _revealEnd = from);
    _revealTimer = Timer.periodic(tick, (t) {
      if (!mounted || _revealTurn == null) return t.cancel();
      i++;
      final end = i >= steps ? to : from + ((to - from) * i / steps).round();
      setState(() => _revealEnd = end);
      if (end >= to) t.cancel();
    });
  }
  bool _speechMuted = false;

  /// Result Board: the card each category box shows ("dealId:kind" -> index)
  /// and whether the customer mega-expanded the board.
  final Map<String, int> _boardPositions = {};
  int? _boardMegaFor;

  /// The Result Board tab chosen per deck (a new deck starts on "Result Board").
  final Map<int, AskodoxBoardTab> _boardTabFor = {};

  /// Speaks [reply] through the one audio lifecycle (tests drive overlap).
  @visibleForTesting
  Future<void> speakReplyForTest(String reply) => _speakReply(reply, userText: reply);
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
    // Stays on until the user's Stop (no silence / no-speech auto-stop).
    _endpointer = AskodoxVoiceEndpointer.untilStop();
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
    // ONE draft: words already typed + this transcript (+ the attachments
    // still in the composer) go together -- typed text is never dropped.
    final draft = askodoxMergeVoiceDraft(_controller.text, transcript);
    if (_sending || _analyzingAttachments) {
      // A turn is still in flight: keep the transcript in the composer
      // instead of discarding it; the user sends it next.
      _controller.text = draft;
      setState(() => _voicePhase = _VoicePhase.idle);
      return;
    }
    setState(() => _voicePhase = _VoicePhase.thinking);
    await _send(draft, true);
    if (mounted && _voicePhase == _VoicePhase.thinking) {
      setState(() => _voicePhase = _VoicePhase.idle);
    }
  }

  /// Leaving the app (an external link, a call, the home button) stops the
  /// recorder natively; the chat must not stay in "recording" or
  /// "transcribing" when the user comes back -- the mic and the keyboard
  /// are usable again at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused && _voicePhase == _VoicePhase.recording) {
      unawaited(_cancelVoice());
    } else if (state == AppLifecycleState.resumed) {
      if (_voicePhase == _VoicePhase.recording || _voicePhase == _VoicePhase.speaking) {
        _voiceTimer?.cancel();
        _voiceTimer = null;
        setState(() => _voicePhase = _VoicePhase.idle);
      }
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
    _speechTurn++;
    _pausedRemainder = null;
    _speechQueue = const [];
    _clearReveal();
    try {
      await _device.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
    if (mounted && (_voicePhase == _VoicePhase.speaking || _speechPaused)) {
      setState(() {
        _speechPaused = false;
        _voicePhase = _VoicePhase.idle;
      });
    }
  }

  /// Pause: Sarvam reply audio pauses in place; the device voice cannot
  /// pause, so it stops and remembers the word it reached (resume goes on
  /// from there with the SAME device voice -- never a voice switch).
  Future<void> _pauseSpeaking() async {
    if (_voicePhase != _VoicePhase.speaking || _speechPaused) return;
    _lipSyncTimer?.cancel();
    ref.read(askodoxCompanionVoiceProvider).speechEnd();
    if (_speakingEngine == 'sarvam') {
      bool? paused;
      try {
        paused = await _device.invokeMethod<bool>('pauseReplyAudio');
      } catch (_) {}
      if (paused == true) {
        if (mounted) setState(() => _speechPaused = true);
        return;
      }
    }
    final text = _speakingText ?? '';
    final rest = [text.substring(_speechRangeStart.clamp(0, text.length)).trim(), ..._speechQueue]
        .where((p) => p.isNotEmpty)
        .join(' ');
    _speechQueue = const [];
    _clearReveal();
    _speechTurn++; // the stopped reply must not fall back to anything
    try {
      await _device.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pausedRemainder = rest;
      _speechPaused = true;
    });
  }

  Future<void> _resumeSpeaking() async {
    if (!_speechPaused) return;
    final rest = _pausedRemainder;
    if (rest == null) {
      bool? resumed;
      try {
        resumed = await _device.invokeMethod<bool>('resumeReplyAudio');
      } catch (_) {}
      if (!mounted) return;
      if (resumed == true) {
        setState(() => _speechPaused = false);
      } else {
        await _stopSpeaking();
      }
      return;
    }
    setState(() {
      _pausedRemainder = null;
      _speechPaused = false;
    });
    if (rest.isEmpty) {
      await _stopSpeaking();
      return;
    }
    await _speakReply(rest, userText: _speakingUserText, force: true, deviceOnly: true);
  }

  /// Mute voice replies (the text stays); unmute from any message's menu.
  Future<void> _toggleMute() async {
    final muted = !_speechMuted;
    setState(() => _speechMuted = muted);
    if (muted) await _stopSpeaking();
  }

  /// Replay one reply on request (even while replies are muted).
  Future<void> _replayReply(String text) async {
    await _stopSpeaking();
    await _speakReply(text, userText: text, force: true);
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
    WidgetsBinding.instance.addObserver(this);
    // A new active place (header / Profile / chat Location) refreshes the
    // latest results for it: cards and distances never stay from the old
    // place (phone finding A1).
    ref.listenManual<LocationState>(locationControllerProvider, (previous, next) {
      final before = previous?.defaultLocation, after = next.defaultLocation;
      if (after == null || before == null) return;
      if (askodoxPlaceMoved(before.point.latitude, before.point.longitude, after.point.latitude,
          after.point.longitude)) {
        // A place picked by hand replaces the place asked for in chat; the
        // phone merely moving does not.
        if (!next.followsDevice) _requestedPlace = null;
        unawaited(_refreshResultsForPlace(before, after));
      }
    });
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
      final start = (args['start'] as num?)?.toInt() ?? 0;
      _speechRangeStart = start; // where a paused device voice resumes
      voice.speechRange(start, (args['end'] as num?)?.toInt() ?? 0);
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
    if (request.videoRef case final videoRef?) {
      // "Ask about this video": the SAME chat, now about this video; every
      // question is answered from its study / listing until the customer
      // moves on.
      final te = _te;
      final title = (request.prompt ?? '').trim();
      setState(() {
        _videoStudyRef = videoRef;
        _videoFocus = true;
        _active = true;
        _turns.add(ConversationTurnRecord(
            text: te
                ? '"$title" గురించి ఏమైనా అడగండి -- వీడియోలో కనిపించినది / సెల్లర్ చెప్పినది / లిస్టింగ్ నుంచి మాత్రమే జవాబిస్తాను.'
                : 'Ask me anything about "$title" -- I answer only from what the video shows, what the seller says, or their listing.',
            isUser: false));
      });
      await _store.save(_turns);
      await _saveSnapshot();
      _scrollBottom();
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
    if (prompt != null && prompt.trim().isNotEmpty) {
      _pendingForcedSearch = request.search;
      await _send(prompt);
      _pendingForcedSearch = false;
    }
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
      // Only a search the readiness gate already allowed is re-run; a
      // request that was still being asked about stays without results.
      if (deal.readyToMatch &&
          deal.dynamicFields['searched'] == true &&
          AskodoxHomeRequestRouting.isTransactional(deal.rawText)) {
        if (deal.intent == DealIntent.sell && _userMeansToSell(deal.rawText, deal)) {
          // Restoring a conversation never posts anything: the listing was
          // saved (or not) when the user finished it. Re-posting here made a
          // duplicate listing on every app restart (APK 1316).
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
      'adviceLedger': _adviceLedger,
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

  /// The studied video attached in THIS conversation: follow-up questions
  /// about it go to its grounded Q&A, not to a deal search.
  String? _videoStudyRef;

  /// Images the customer sent in this session, by attachment id: the chat
  /// shows the picture, not just its file name (history keeps the name).
  final Map<String, Uint8List> _sentImages = {};

  /// Opened from "Ask about this video": every question is about it until
  /// the customer moves on.
  bool _videoFocus = false;

  /// Category-tree actions offered under an assistant turn ("Join as a
  /// partner", "Send a pickup").
  final Map<int, AskodoxTaxonomyMatch> _taxonomyByTurn = {};

  /// "Show me on screen" offered under an assistant turn.
  final Map<int, AskodoxGuideFlow> _guideByTurn = {};

  void _clearConversationState() {
    _adviceLedger = const [];
    _videoStudyRef = null;
    _videoFocus = false;
    _taxonomyByTurn.clear();
    _guideByTurn.clear();
    _turns.clear();
    _resultsByTurn.clear();
    _resultsHiddenFor = null;
    _resultsOutdatedFor = null;
    _resultsStaleFor = null;
    _boardMinimizedFor = null;
    _focusedMatch = null;
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
    _listingNeedsSignIn = false;
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
      // A video studied in this conversation keeps answering after restore.
      for (final turn in _turns) {
        for (final a in turn.attachments) {
          if (a['study_ref'] case final r? when r.isNotEmpty) _videoStudyRef = r;
        }
      }
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
      _adviceLedger = [
        for (final entry in (data['adviceLedger'] as List? ?? const []))
          if (entry is Map) Map<String, Object?>.from(entry),
      ];
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
    // A retired deck (genuine topic change) is no longer the active context:
    // follow-up answering and confirmations must not reach back into it.
    if (_resultsHiddenFor == lastKey) return null;
    return _resultsByTurn[lastKey];
  }

  /// The most recent results that have options ASKODOX can act on (a
  /// registered seller / interested provider). A newer turn that only
  /// showed online links or a per-need segment must not hide them from
  /// "yes / order it / contact seller".
  AskodoxChatResults? _latestActionableResults() {
    final keys = _resultsByTurn.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final key in keys.take(4)) {
      if (key == _resultsHiddenFor) continue; // retired deck (topic change)
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

  /// Result Diagnostics: tell the backend which contract sections this
  /// turn actually drew, and why any returned section was not drawn.
  void _reportRendered(AskodoxChatResults? results, {String? heldReason}) {
    final contract = results?.contract;
    final key = results?.traceKey;
    if (contract == null || key == null || key.isEmpty) return;
    final report = askodoxRenderedSections(contract, results!.matches, heldReason: heldReason);
    unawaited(ref.read(apiClientProvider).post<Map<String, Object?>>(
      '/api/results/rendered',
      body: {'trace_key': key, 'sections': report.rendered, 'hidden': report.hidden},
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
          .explain(videoId, question: match.title, language: _lang);
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

  /// Deals already posted as listings in this conversation (see
  /// [askodoxListingKey]).
  final Set<String> _listedDealKeys = {};

  Future<(String?, bool)> _createRealListing(UniversalDeal deal) async {
    final subject = deal.subject;
    if (!askodoxListingSubjectValid(subject, location: deal.location.label)) {
      return (
        _te ? 'మీరు ఏమి అమ్ముతున్నారో చెప్పండి (ఉదా: "2 సైకిళ్లు ₹3000").' : 'Tell me what you are selling (e.g. "2 bicycles for ₹3000").',
        false,
      );
    }
    final key = askodoxListingKey(subject, deal.price, deal.quantity);
    if (_listedDealKeys.contains(key)) return (null, false); // already posted
    _listedDealKeys.add(key);
    try {
      final result =
          await ref.read(sellerListingRepositoryProvider).createListing(deal);
      // Not saved (sign-in / error): the user may try the same listing again.
      if (!result.success) _listedDealKeys.remove(key);
      if (result.success && result.heldForReview) {
        final subject = deal.subject ?? '';
        final why = result.message ?? '';
        return (
          _te
              ? '“$subject” సేవ్ అయింది -- ASKODOX బృందం చూసిన తర్వాత కనిపిస్తుంది${why.isEmpty ? '' : ' ($why)'}.'
              : '“$subject” is saved -- it will appear once the ASKODOX team reviews it${why.isEmpty ? '' : ' ($why)'}.',
          false,
        );
      }
      if (result.success) {
        final subject = deal.subject ?? '';
        return (
          _te
              ? '“$subject” ఇప్పుడు లైవ్‌లో ఉంది -- కొనుగోలుదారులు దీన్ని ఇప్పుడు వెతికి కనుగొనవచ్చు.'
              : '“$subject” is now live -- buyers can search and find it right now.',
          false,
        );
      }
      final raw = result.message ?? '';
      if (RegExp(r'sign in|session', caseSensitive: false).hasMatch(raw)) {
        // A missing / rejected sign-in: say it plainly and offer sign-in --
        // never the server's internal wording (APK 1276).
        _listingNeedsSignIn = true;
        return (
          _te
              ? 'మీ లిస్టింగ్ ప్రచురించడానికి సైన్ ఇన్ చేయండి. మీ వివరాలు అలాగే ఉంటాయి.'
              : 'Sign in to publish your listing. Your details are kept.',
          true,
        );
      }
      return (
        raw.isNotEmpty
            ? raw
            : (_te
                ? 'లిస్టింగ్ సేవ్ చేయడం సాధ్యం కాలేదు.'
                : 'Unable to save this listing.'),
        true,
      );
    } catch (_) {
      _listedDealKeys.remove(key);
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
      // The canonical contract already ordered the rows (section by
      // section); only an older backend's rows are sorted here.
      final matches = result.contract != null
          ? [...result.matches]
          : ([...result.matches]..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore)));
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
        advisor: result.advisor,
        contract: result.contract,
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

  /// Re-runs the latest results for the new place -- only when that search
  /// was "near me" (it used the previous active place or none); a place the
  /// customer named in the request ("in Guntur") is kept.
  Future<void> _refreshResultsForPlace(BuyerSavedLocation before, BuyerSavedLocation after) async {
    final turn = _pinnedResultsTurn;
    final deal = turn == null ? null : _dealByTurn[turn];
    if (turn == null || deal == null || !mounted) return;
    final loc = deal.location;
    final usedActivePlace = (loc.latitude == null || loc.longitude == null)
        ? ((loc.label ?? '').trim().isEmpty || askodoxIsNearMePhrase(loc.label!)) // a typed place is the customer's own
        : !askodoxPlaceMoved(loc.latitude!, loc.longitude!, before.point.latitude, before.point.longitude);
    if (!usedActivePlace) return;
    final label = after.address.trim().isNotEmpty ? after.address.trim() : after.name.trim();
    final moved = deal.copyWith(
        location: DealLocation(
            label: label, latitude: after.point.latitude, longitude: after.point.longitude, radiusKm: loc.radiusKm));
    setState(() {
      _dealByTurn[turn] = moved;
      _resultsStaleFor = label;
    });
    if (_sending) return;
    setState(() => _sending = true);
    final results = await _findUniversalMatches(moved);
    if (!mounted) return;
    setState(() {
      _resultsByTurn[turn] = results;
      _resultsStaleFor = null;
      _sending = false;
      _turns.add(ConversationTurnRecord(
          text: _te ? 'ఫలితాలను $label కోసం నవీకరించాను.' : 'Updated the results for $label.', isUser: false));
    });
    await _store.save(_turns);
    unawaited(_saveSnapshot());
    _scrollBottom();
  }

  /// Set while results are being refreshed for a new place (old cards are
  /// marked, never shown as current).
  String? _resultsStaleFor;

  /// Result Board: the pinned deck the customer minimized to its pill (null
  /// = expanded). Fresh useful results always open the board again.
  int? _boardMinimizedFor;

  /// The shown results were for a DIFFERENT need than the one now being
  /// discussed (no search justified yet): not shown as if they matched.
  int? _resultsHiddenFor;

  /// The shown results were for EARLIER details of the same need (budget,
  /// brand, size... changed; the new search is not justified yet): dimmed and
  /// labelled, never presented as matches for the new details.
  int? _resultsOutdatedFor;

  /// What the options on screen were searched for (the brain decides from
  /// it whether a new detail needs a new search or the current options do).
  Map<String, Object?>? _searchedFor() {
    final pinned = _pinnedResultsTurn;
    if (pinned == null || _resultsHiddenFor == pinned) return null;
    final deal = _dealByTurn[pinned];
    if (deal == null) return null;
    final fields = deal.dynamicFields;
    return {
      'subject': deal.subject,
      // The customer's own wording of the need: a Telugu / Hindi follow-up is
      // compared with words in its own script, not only the English phrase.
      if ((fields['said_subject'] ?? '').toString().trim().isNotEmpty) 'said_subject': fields['said_subject'],
      if (fields['brain_facts'] is Map) 'facts': fields['brain_facts'],
      if (fields['budget_max'] != null) 'budget_max': fields['budget_max'],
      if (fields['brand'] != null) 'brand': fields['brand'],
      if (deal.size != null) 'size': deal.size,
      if (deal.location.label?.trim().isNotEmpty ?? false) 'location': deal.location.label,
      'options_shown': _resultsByTurn[pinned]?.matches.length ?? 0,
      // Where the shown options came from ("Meesho lo ivva" refines them).
      'sources': {
        for (final m in _resultsByTurn[pinned]?.matches ?? const <UniversalMatch>[])
          if ((m.sourceName ?? '').trim().isNotEmpty) m.sourceName!.trim(),
      }.take(8).toList(),
    };
  }

  /// What a search was for: the request's details, without bookkeeping.
  static String _requirementSignature(UniversalDeal deal) {
    const volatile = {'searched', 'said_subject', 'advisor_asked', 'requested_groups', 'aiCategory'};
    final fields = {
      for (final e in deal.dynamicFields.entries)
        if (!volatile.contains(e.key)) e.key: '${e.value}',
    };
    final keys = fields.keys.toList()..sort();
    return [
      (deal.subject ?? '').trim().toLowerCase(), deal.size ?? '', '${deal.price ?? ''}', '${deal.quantity ?? ''}',
      deal.location.label ?? '', for (final k in keys) '$k=${fields[k]}',
    ].join('|');
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

  /// Sends one turn. Whatever happens inside (a network error, an AI
  /// timeout, a parse failure), the composer, mic and card actions are
  /// usable again afterwards -- a stuck "sending" state disabled the input
  /// and the keyboard on real phones.
  /// Send from the composer (button / keyboard). While recording, Send ends
  /// the recording and sends typed text + transcript + attachments together;
  /// while a recording is being transcribed, that flow sends the draft.
  Future<void> _sendFromComposer() async {
    if (_voicePhase == _VoicePhase.recording) {
      await _finishVoice(noSpeech: false);
      return;
    }
    if (_voicePhase == _VoicePhase.transcribing) return;
    await _send();
  }

  Future<void> _send([String? preset, bool speakResponse = false]) async {
    try {
      await _sendTurn(preset, speakResponse);
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  Future<void> _sendTurn([String? preset, bool speakResponse = false]) async {
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
      var lowConfidence = false;
      // Each attachment is analysed on its own: one failure never discards
      // the others. Failed ones stay in the composer for a retry.
      final failed = <ChatAttachment>[];
      ChatAttachmentException? firstError;
      for (final attachment in attachments) {
        try {
          final result = await ref.read(chatAttachmentServiceProvider).analyze(
                attachment,
                userText: typed,
                language: _lang,
              );
          if (job != _attachmentJob || !mounted) return; // cancelled
          facts.add(attachments.length > 1 ? '${attachment.name}: ${result.facts}' : result.facts);
          final study = result.videoStudy;
          if (attachment.isImage) _sentImages[result.id] = attachment.bytes;
          sentAttachments.add({
            'name': attachment.name, 'kind': result.kind, 'id': result.id,
            // A short upload ASKODOX studied: open its grounded Q&A.
            if (study != null && study['status'] == 'ready' && study['ref'] != null) 'study_ref': '${study['ref']}',
            if (study != null && study['status'] != 'ready' && '${study['message'] ?? ''}'.isNotEmpty)
              'study_note': '${study['message']}',
          });
          lowConfidence = lowConfidence || result.lowConfidence;
          if (result.kind == 'image') imageAnalysis ??= result.analysis;
          if (result.kind == 'video') videoAnalysis ??= result.analysis;
        } on ChatAttachmentException catch (error) {
          if (job != _attachmentJob || !mounted) return;
          debugPrint('ASKODOX attachment analysis failed: ${error.diagnostic}');
          failed.add(attachment);
          firstError ??= error;
        }
      }
      if (!mounted) return;
      if (facts.isEmpty) {
        final error = firstError!;
        setState(() {
          _analyzingAttachments = false;
          _companionError = true;
        });
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
      setState(() => _analyzingAttachments = false);
      _keptAttachments = failed;
      if (failed.isNotEmpty) _attachmentNotice('attach_partial', diagnostic: firstError?.diagnostic);
      attachmentContext = 'Attachment facts: ${facts.join('\n')}';
      if (typed.isNotEmpty && askodoxWantsToList(typed) && (imageAnalysis != null || videoAnalysis != null)) {
        await _draftFromMedia(typed,
            imageAnalysis: imageAnalysis,
            videoAnalysis: videoAnalysis,
            speakResponse: speakResponse,
            attachments: sentAttachments);
        return;
      }
      // Attachment intent first: sent to be understood (no words, or "what is
      // this?") -> explain + ask what to do; never a search, sellers, online
      // cards or referral prompts.
      if (!askodoxAttachmentWantsAction(typed)) {
        _pendingAiContext = askodoxAttachmentGuidance(
            lowConfidence: lowConfidence, failed: [for (final f in failed) f.name]);
        _pendingDiscussOnly = true;
        ref.read(selfHealReporterProvider).report('attachment_intent_mismatch',
            turnKind: sentAttachments.isEmpty ? '' : sentAttachments.first['kind'] ?? '', language: _lang);
      } else if (lowConfidence) {
        _pendingAiContext = askodoxAttachmentGuidance(lowConfidence: true);
      }
      text = askodoxAttachmentRequest(typed.isEmpty ? askodoxAttachmentOnlyAsk : typed, facts.join('\n'));
    }

    setState(() {
      _sending = true;
      _active = true;
      _actionConfirmed = false;
      _listingBanner = null;
      _listingBannerIsError = false;
      _listingNeedsSignIn = false;
      _turns.add(ConversationTurnRecord(
        text: typed,
        isUser: true,
        attachments: sentAttachments,
        context: attachmentContext,
      ));
      _attachments
        ..clear()
        ..addAll(_keptAttachments);
      _keptAttachments = const [];
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
    // Never match against an old place silently: say it once per stale spell.
    if (locationState.stale && selectedLocation != null && !_staleLocationNoticeShown && mounted) {
      _staleLocationNoticeShown = true;
      ref.read(selfHealReporterProvider).report('stale_state', turnKind: 'location', language: _lang);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const ValueKey('askodoxStaleLocationNotice'),
        content: Text('${locationState.message ?? 'Using your last detected place.'} '
            '(${locationState.headerLocation ?? selectedLocation.name})'),
      ));
    } else if (!locationState.stale) {
      _staleLocationNoticeShown = false;
    }
    final knownLocationLabel = selectedLocation == null
        ? null
        : (selectedLocation.address.trim().isNotEmpty
            ? selectedLocation.address.trim()
            : selectedLocation.name.trim());

    final userTurnIndex = _turns.length - 1;

    // "bye" / "good night" / "thanks, that's all" (any language the lexicon
    // or the AI knows): a localized sign-off, never a search or a question.
    if (attachments.isEmpty && askodoxIsSignOff(typed)) {
      String? bye;
      try {
        bye = await ref.read(greetingRepositoryProvider).signoff(
            language: _lang, name: ref.read(authSessionProvider).user?.displayName ?? '');
      } catch (_) {
        bye = null;
      }
      if (!mounted) return;
      if (bye != null) {
        final text = bye;
        setState(() {
          _turns.add(ConversationTurnRecord(text: text, isUser: false));
          _sending = false;
        });
        await _store.save(_turns);
        await _saveSnapshot();
        _scrollBottom();
        if (speakResponse) unawaited(_speakReply(text, userText: typed));
        return;
      }
      _pendingAiContext = askodoxSignOffGuidance;
      _pendingDiscussOnly = true;
    }

    // A question about the video attached here -> its grounded study
    // (seen / said in the video, with timestamps), never ID-47 deal text.
    final attachedStudy = sentAttachments
        .map((a) => a['study_ref'])
        .firstWhere((r) => r != null && r.isNotEmpty, orElse: () => null);
    if (attachedStudy != null) _videoStudyRef = attachedStudy;
    final videoRef = _videoStudyRef;
    if (videoRef != null && askodoxAsksAboutVideo(typed, justAttached: attachedStudy != null || _videoFocus)) {
      await _answerFromVideo(videoRef, typed, speakResponse);
      return;
    }
    if (attachedStudy == null && typed.isNotEmpty && videoRef != null &&
        !askodoxAsksAboutVideo(typed, justAttached: _videoFocus)) {
      // The customer moved on (a new need / buy it nearby): normal flow.
      _videoStudyRef = null;
      _videoFocus = false;
    }

    // "How do I upload a video?": ASKODOX shows it on the real screen.
    final guide = attachments.isEmpty ? askodoxGuideFor(typed) : null;
    if (guide != null) {
      final flow = guide;
      final te = _te;
      final text = te
          ? '${flow.title(true)} -- అసలు స్క్రీన్‌పై దశలవారీగా చూపిస్తాను. ప్రతి బటన్ మీరే నొక్కుతారు.'
          : 'I can show you "${flow.titleEn}" on the real screen, step by step. You press every button yourself.';
      setState(() {
        _turns.add(ConversationTurnRecord(text: text, isUser: false));
        _guideByTurn[_turns.length - 1] = flow;
        _sending = false;
      });
      await _store.save(_turns);
      await _saveSnapshot();
      _scrollBottom();
      if (speakResponse) unawaited(_speakReply(text, userText: typed));
      return;
    }

    // "Can you deliver food?" / "I can work as a delivery partner": answered
    // from the universal category tree (what ASKODOX can do here), with the
    // real next step -- never a product search.
    if (attachments.isEmpty && askodoxAsksDeliveryCapability(typed)) {
      AskodoxTaxonomyMatch? match;
      try {
        match = await ref.read(askodoxTaxonomyRepositoryProvider).resolve(typed);
      } catch (_) {
        match = null;
      }
      if (!mounted) return;
      if (match != null && (match.provider ? match.actions.contains('join_as_partner')
          : match.actions.any((a) => a == 'request_delivery' || a == 'request_ride'))) {
        await _answerCapability(match, typed, speakResponse);
        return;
      }
    }

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
    // Follow-up about the results ON SCREEN ("compare the best 3",
    // "cheapest?", "only local", "any deals?", "directions"): answered from
    // the current result set -- never a new unrelated search, never a canned
    // reply. Unknown facts are "Not verified". When the shown results cannot
    // answer (no row has a rating / an offer), the normal flow searches.
    if (explicitContext == null && !_pendingDiscussOnly && latestResults != null) {
      final followUp = askodoxFollowUpIntent(text);
      if (followUp == AskodoxFollowUp.directions) {
        final target = [
          for (final m in askodoxComparableRows(latestResults.matches))
            if (askodoxDirectionsUri(m) != null) m,
        ].firstOrNull;
        if (target != null) {
          var opened = false;
          try {
            opened = await launchUrl(askodoxDirectionsUri(target)!, mode: LaunchMode.externalApplication);
          } catch (_) {
            opened = false;
          }
          if (!opened) {
            await _replyAndSave(
                _te
                    ? 'Google Maps తెరవలేకపోయాను. ${target.title} కార్డ్‌లో "దారి" నొక్కండి.'
                    : 'Could not open Google Maps. Tap Directions on the ${target.title} card.',
                speakResponse,
                text);
            return;
          }
          await _replyAndSave(
              _te ? '${target.title} కి దారి Google Maps లో తెరుస్తున్నాను.' : 'Opening directions to ${target.title} in Google Maps.',
              speakResponse,
              text);
          return;
        }
      } else if (followUp != null) {
        final answer = askodoxAnswerFollowUp(followUp, latestResults.matches,
            te: _te, budget: askodoxFollowUpBudget(text));
        if (answer != null) {
          await _replyAndSave(answer, speakResponse, text);
          return;
        }
      }
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

    // Every turn passes the Conversation Decision Brain BEFORE any search:
    // it reads the whole conversation and says whether a search is justified
    // now (see search_readiness.dart).
    final decision = await ref.read(askodoxAssistantServiceProvider).decide(
      message: aiMessage,
      locale: _lang,
      history: history,
      location: _saysNearMe(text) ? knownLocationLabel : (_requestedPlace?.label ?? knownLocationLabel),
      searchedFor: _searchedFor(),
      adviceGiven: _adviceLedger,
    );
    final aiUsable = decision?.usable == true;
    // One-time advice memory: keep the ledger the brain returned so a
    // concern already explained is not repeated (an older backend returns
    // none -- keep what we have).
    if (aiUsable && decision!.adviceLedger != null) _adviceLedger = decision.adviceLedger!;
    // APK 1305: the deterministic conversation-relation layer (backend)
    // classifies this turn against the ACTIVE need. A replaced subject or a
    // genuine new topic retires the previous active result deck NOW: those
    // cards belong to a different need and must not stay pinned over the new
    // request. Same-topic refinements keep the deck untouched.
    final relationNewTopic = decision != null &&
        (decision.subjectChanged || decision.conversationRelation == 'new_topic');
    if (relationNewTopic) {
      final pinned = _pinnedResultsTurn;
      if (pinned != null) {
        _resultsHiddenFor = pinned;
        _resultsOutdatedFor = null;
        _resultsStaleFor = null;
        _boardMinimizedFor = null;
        _focusedMatch = null; // the selected option belonged to the old need
      }
    }
    // The brain owns readiness this turn (a question about options already
    // shown never searches anyway).
    final brainGates = aiUsable && decision!.gatesSearch && !discussOnly;

    // Several needs in one message ("fridge ₹30–40k, TV ₹20–30k, car ₹10
    // lakh"): each becomes its own requirement with its own slots and its
    // own real results -- nothing is mixed between categories. Only when the
    // brain agrees enough is known (or gave no readiness).
    final needs = explicitContext == null && !discussOnly && !(brainGates && decision.searchReady == false)
        ? askodoxSplitNeeds(text)
        : const <AskodoxNeedSegment>[];
    if (needs.isNotEmpty) {
      _lastSearchGate = 'search (${brainGates ? 'brain' : 'offline'}: several needs)';
      await _searchSeveralNeeds(needs, speakResponse, text);
      return;
    }
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
    final forcedSearch = _pendingForcedSearch;
    _pendingForcedSearch = false;
    // The brain decides whether a video ask is a SEARCH ("Samsung S23 review
    // videos") or talk ABOUT videos / a platform ("facebook and instagram
    // videos kuda chupinchali" while setting up Meta); the keyword alone is
    // the offline rule only.
    final videoWords = askodoxAsksForVideos(text) &&
        ((aiUsable && decision!.action == 'search_videos') || !askodoxTalksAboutVideoPlatform(text));
    final videoAsk = !discussOnly && explicitContext == null && (forcedSearch || videoWords);
    final showNow = askodoxWantsResultsNow(text) || videoAsk || (clarified != null && _showNowAfterClarification);
    final showOnly = showNow && askodoxNeedSubject(text).isEmpty;
    // "the best one" / "ఒక్కటి చాలు": one actionable answer, not a list.
    final wantsOne = askodoxWantsSingleResult(text);
    // A short answer such as "curry cut", "1 kg" or "skinless" is not
    // transactional on its own, but it *is* transactional when ASKODOX is
    // already collecting details for an unfinished commerce request. Do not
    // let the assistant classifier drop that active deal and strand the user
    // in general chat just before matching. A real aside (a question or a
    // longer general message) still goes to general chat, and the unfinished
    // deal is kept so the user can resume it.
    final activeDealSession = ref.read(universalDealControllerProvider);
    // A request whose results the advisor is holding for one more answer
    // (budget...) is still the active request.
    final continuingActiveDeal = activeDealSession.deal != null &&
        (!activeDealSession.completed || _pendingAdvisorField != null);
    // The brain says whether this message answers the need being discussed
    // or starts a different one; the short-message rule is the offline case.
    final brainNewNeed = relationNewTopic ||
        (aiUsable && decision!.gatesSearch && decision.newNeed);
    final detailAnswer = !discussOnly &&
        clarified == null &&
        continuingActiveDeal &&
        !brainNewNeed &&
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
        !brainNewNeed &&
        activeDealSession.deal != null &&
        text.trim().split(RegExp(r'\s+')).length <= 4 &&
        askodoxDetectRole(text) == null &&
        (askodoxQualifierReply(text) != null || askodoxDetectBrand(text, known: listedBrands) != null);
    // Decision brain: an advice / decision question ("should I start a
    // car-finance business?", "what AC capacity do I need?") is answered
    // with reasoning -- never result cards -- unless the user also asked to
    // see options now or is answering a pending detail question.
    final adviceOnly = aiUsable && decision!.isAdvice && !showNow && !videoAsk && !detailAnswer && clarified == null;
    final transactional = !discussOnly &&
        !adviceOnly &&
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
    // But a message that ASKS to see / find something (the brain's search_*
    // action, a video ask, "show me") is a search whatever the saved role is:
    // a Seller role kept on the phone once turned every search into a
    // published listing -- text only, no results (APK 1276-1283).
    final asksToFind = videoAsk ||
        showNow ||
        (aiUsable && decision!.action.trim().toLowerCase().startsWith('search'));
    final actsAsSupplier = !asksToFind && askodoxActsAsSupplier(ref.read(askodoxRoleProvider).active, text);
    final routedText =
        aiUsable ? AskodoxSemanticDealInput.build(text, decision!, supplySide: actsAsSupplier) : text;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    AskodoxChatResults? results;
    UniversalDeal? matchedDeal;
    String? detailQuestion;
    AskodoxAdvisorView? advisorHeld;
    final advisorFieldAsked = _pendingAdvisorField;
    _pendingAdvisorField = null;
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
      } else if (brainNewNeed && session.deal != null) {
        // The brain: a different need. The current one is kept (parked) for
        // when the customer returns to it.
        _parkDeal(session.deal!);
        _lastGoodProductQuery = null;
        notifier.reset();
        notifier.start(routedText);
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
        final noPreference = askodoxIsNoPreference(text);
        final advisorField = advisorFieldAsked;
        final brandLike = noPreference
            ? null
            : askodoxQualifierReply(text) ??
                askodoxDetectBrand(text, known: ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{});
        if (advisorField != null && noPreference) {
          // "any" to the advisor's question settles THAT field only.
          notifier.markNoPreference(advisorField);
        } else if (advisorField == 'budget' && !askodoxBudgetRange(text).isEmpty) {
          // The amount is applied below (applyBudget) -- never written into
          // another slot such as TV size.
        } else if (advisorField != null && advisorField != 'budget' && brandLike == null &&
            _lastAskedQuestion == null) {
          notifier.answerAdvisorField(advisorField, text);
        } else if (noPreference && _lastAskedQuestion == null) {
          // "any" to the assistant's own brand question: the brand only --
          // never the next schema slot, never the budget (real-phone bug).
          notifier.markNoPreference('brand');
        } else if (brandLike != null) {
          notifier.answerOrBrand(text,
              brand: brandLike, known: ref.read(askodoxListedBrandsProvider).valueOrNull ?? const <String>{});
        } else {
          notifier.answer(text);
        }
      } else if (shouldStartFresh && session.deal != null) {
        _lastGoodProductQuery = null;
        notifier.reset();
        notifier.start(routedText);
      } else if (session.deal != null &&
          session.completed &&
          AskodoxHomeRequestRouting.isShortDetailAnswer(text) &&
          (aiSubject == null || askodoxSameNeed(session.deal!.subject, aiSubject))) {
        // "Size 9, ₹2000" right after results: it REFINES that request
        // (every earlier answer kept) -- never a fresh start that drops
        // the size (APK 1292: Size 9 was lost and a stale "Any" sent).
        dealBeforeAnswer = session.deal;
        notifier.adopt(session.deal!);
      } else if (session.deal == null || session.completed) {
        _lastGoodProductQuery = null;
        notifier.start(routedText);
      } else {
        dealBeforeAnswer = session.deal;
        notifier.answer(routedText);
      }

      if (_saysNearMe(text)) _requestedPlace = null;
      final requested = _requestedPlace;
      if (requested != null && ref.read(universalDealControllerProvider).deal?.location.isKnown != true) {
        notifier.applyRequestedPlace(requested);
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
      // The size the customer SAID (typed or voice), exactly as said; the
      // AI's size entity only when the words name none.
      final aiSize = aiUsable ? decision!.entityText('size') : null;
      final saidSize = askodoxExplicitSize(text) ??
          (aiSize != null && aiSize.trim().isNotEmpty && aiSize.length <= 20 && !askodoxIsNoPreference(aiSize)
              ? aiSize.trim()
              : null);
      if (saidSize != null) notifier.applyExplicitSize(saidSize);
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

      // The brain's accumulated state (every fact so far, flexible
      // preferences, the consolidated subject once ready) is the request.
      if (brainGates) {
        final facts = decision.facts;
        final flexibleBrand = decision.flexible.any((f) => f.contains('brand'));
        for (final fact in facts.entries) {
          if (!RegExp('budget|price', caseSensitive: false).hasMatch(fact.key)) continue;
          final range = askodoxBudgetRange('${fact.value}');
          if (!range.isEmpty) notifier.applyBudget(min: range.min, max: range.max);
        }
        final firmBrand = '${facts['brand'] ?? ''}'.trim();
        if (firmBrand.isNotEmpty && !flexibleBrand && !askodoxIsNoPreference(firmBrand) && firmBrand.length <= 40) {
          notifier.applyBrand(firmBrand, known: known);
        }
        notifier.applyBrainState(
          facts: facts,
          flexible: decision.flexible,
          searchSubject: decision.searchReady == true ? decision.searchSubject : null,
        );
      }

      final namedGroups = askodoxRequestedGroups(text);
      if (namedGroups.isNotEmpty) notifier.rememberGroups(namedGroups);
      final channel = askodoxChannelPreference(text);
      if (channel != null) notifier.rememberChannel(channel);
      final dealSession = ref.read(universalDealControllerProvider);
      final deal = dealSession.deal;
      if (deal != null) {
        _trackSearchQuery(deal.subject ?? deal.category);
        _lastIntent = deal.intent;
        // Understand the actual product first: a genuinely ambiguous need
        // gets ONE concise question instead of a guessed search.
        // Someone who asked for videos said what they want: show the real
        // videos (a clarifying question here left them with none).
        if (clarified == null && !detailAnswer && !videoAsk) {
          // The AI flags genuine ambiguity for any category; the fixed
          // rules only cover the offline case.
          final aiOptions = aiUsable && decision!.action == 'clarify_need'
              ? [for (final o in (decision.entities['clarify_options'] as List? ?? const [])) '$o']
              : const <String>[];
          // With the brain deciding, ambiguity is its call (clarify_need);
          // the fixed keyword rules only cover the offline case.
          final candidate = askodoxDynamicClarification(options: aiOptions, question: decision?.reply) ??
              (brainGates ? null : askodoxClarificationFor(text));
          if (candidate != null && !_clarifiedKeys.contains(candidate.key)) {
            needClarification = candidate;
            _showNowAfterClarification = showNow;
          }
        }
        // The brain asks the ONE next question itself (in its reply); the
        // schema's fixed next slot is only the offline fallback.
        if (!deal.readyToMatch && !brainGates) detailQuestion = dealSession.lastQuestion;
      }
      // Never loop on the same question: once asked and answered, or when
      // the customer says "show me", search with what is known.
      // A loop = the same question again AND the answer filled nothing.
      final missingNow = deal?.missingForMatch ?? const <String>[];
      final repeating = detailQuestion != null &&
          clarified == null &&
          detailQuestion == _lastAskedQuestion &&
          missingNow.join('|') == _lastMissing.join('|');
      final gate = askodoxSearchGate(
        hasSubject: deal?.subject?.trim().isNotEmpty ?? false,
        brainReady: brainGates ? decision.searchReady : null,
        userAskedNow: showNow || videoAsk,
        schemaReady: deal?.readyToMatch ?? false,
        repeating: repeating,
        brainReason: brainGates ? decision.readyReason : '',
      );
      _lastSearchGate = gate.toString();
      final searchNow = deal != null && gate.allowed;
      if (searchNow && !deal.readyToMatch) detailQuestion = repeating || videoAsk ? null : detailQuestion;
      // The deal's next question is written in English in the category
      // schema: ask it in the conversation language (APK 1275: Telugu chat
      // showed "How much chicken do you need?").
      if (detailQuestion != null && detailQuestion.trim().isNotEmpty && _lang != 'en') {
        detailQuestion = await ref
                .read(askodoxAssistantServiceProvider)
                .localizeQuestion(detailQuestion, language: _lang) ??
            detailQuestion;
      }
      if (deal != null && searchNow && needClarification == null) {
        if (deal.intent == DealIntent.sell && !asksToFind && _userMeansToSell(text, deal)) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          // A "sell" guess the user never said is a buyer search.
          final searchDeal = deal.intent == DealIntent.sell ? deal.copyWith(intent: DealIntent.buy) : deal;
          matchedDeal = searchDeal;
          notifier.markSearched();
          results = await _findUniversalMatches(searchDeal);
          // Universal Advisor: a required, decision-changing detail (e.g.
          // budget for a TV) is asked BEFORE final recommendations, unless
          // the user asked to see options now.
          final advisor = results.advisor;
          // Command Center can switch the advisor off (globally or targeted);
          // the server then sends no hold, and the app also never holds.
          if (!brainGates &&
              ref.read(askodoxFlagProvider('advisor.enabled')) &&
              askodoxAdvisorHolds(advisor, showNow: showNow, videoAsk: videoAsk)) {
            advisorHeld = advisor;
            notifier.markAdvisorAsked(advisor!.field ?? '');
            _reportRendered(results, heldReason: 'held: advisor asked a required question first');
            results = null;
            matchedDeal = null;
          }
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

    // No false success: without cards on screen this turn the reply never
    // claims "showing / finding options" (APK 1292), and it never restates
    // the customer's size differently ("Size 8 or 9" for "size 9").
    final cardsThisTurn =
        results != null && results.matches.isNotEmpty && (results.contract?.mayClaimResults ?? true);
    final keptSize = ref.read(universalDealControllerProvider).deal?.size;
    if (transactional && needClarification == null && askodoxReplyAltersSize(reply, keptSize)) {
      reply = askodoxNoCardsReply(results: results, question: detailQuestion, telugu: _te);
    } else if (transactional && needClarification == null && !cardsThisTurn && askodoxReplyClaimsResults(reply)) {
      // Drop only the false claim; the reasoning before results stays.
      final kept = askodoxStripResultClaims(reply);
      final notice = askodoxNoCardsReply(results: results, question: detailQuestion, telugu: _te);
      reply = kept.isEmpty ? notice : '$kept\n\n$notice';
    }

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

    if (advisorHeld != null) {
      // The advisor's question IS the reply this turn (plus a short "why"
      // when guidance applies): no results were claimed.
      final guidance = advisorHeld.guidance.where((g) => !_guidanceGiven.contains(g)).take(1).toList();
      _guidanceGiven.addAll(guidance);
      // The brain's own answer (its reasoning / estimate) stays; only its
      // trailing question yields to the advisor's one question.
      final answer = aiUsable ? askodoxWithoutTrailingQuestion(reply) : '';
      reply = [if (answer.isNotEmpty) answer, ...guidance, advisorHeld.question!.trim()].join('\n\n');
      _pendingAdvisorField = advisorHeld.field;
    } else if (results != null && results.advisor != null) {
      // With results: one line of trade-off guidance when it applies, never
      // repeated; an optional open question is offered, not forced.
      final guidance = results.advisor!.guidance.where((g) => !_guidanceGiven.contains(g)).take(1).toList();
      if (guidance.isNotEmpty && !reply.contains(guidance.first)) {
        _guidanceGiven.addAll(guidance);
        reply = '${reply.trim()}\n\n${guidance.first}';
      }
      final optional = results.advisor!.question?.trim();
      if (!brainGates && optional != null && optional.isNotEmpty && !reply.trim().endsWith('?') &&
          advisorFieldAsked != results.advisor!.field) {
        reply = '${reply.trim()}\n\n$optional';
        _pendingAdvisorField = results.advisor!.field;
        if (results.advisor!.field != null) notifier.markAdvisorAsked(results.advisor!.field!);
      }
    }

    // A clarification turn did not actually ask the detail question.
    // Only a question the user actually SAW counts as asked: when the AI's
    // own reply asked something else ("Any brand you prefer?"), the hidden
    // schema question is not pending, so "any" never fills its slot
    // (real-phone: "any" brand jumped straight to results).
    _lastAskedQuestion = transactional &&
            results == null &&
            needClarification == null &&
            detailQuestion != null &&
            reply.contains(detailQuestion.trim())
        ? detailQuestion
        : null;
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
        // One no-results notice per request: an earlier empty notice for the
        // SAME request id is folded into this one (APK 1292 showed "#47"
        // twice after the request was refined and searched again).
        final id = results.dealId ?? '';
        if (id.isNotEmpty) {
          _resultsByTurn.removeWhere((_, earlier) => earlier.dealId == id && earlier.matches.isEmpty);
        }
        // Fresh results replace any retired deck as the active context and
        // open the Result Board (expanded), even if the old one was minimized.
        _resultsHiddenFor = null;
        _boardMinimizedFor = null;
        _resultsByTurn[assistantIndex] = wantsOne ? askodoxBestOnly(results) : results;
        if (matchedDeal != null) _dealByTurn[assistantIndex] = matchedDeal;
        if (matchedDeal != null) _rememberRequestedPlace(matchedDeal.location, knownLocationLabel);
        _reportRendered(results);
      }
      if (support.need != AskodoxSupportNeed.none) {
        _supportByTurn[assistantIndex] = support;
      }
      // The requirement moved on without a new (justified) search: the old
      // cards must not pose as matches for it.
      final pinned = _pinnedResultsTurn;
      final shownFor = pinned == null ? null : _dealByTurn[pinned];
      final nowWanted = ref.read(universalDealControllerProvider).deal;
      if (transactional && (results == null || results.isEmpty) && shownFor != null && nowWanted != null) {
        final channelChanged = nowWanted.dynamicFields['channel'] != null &&
            nowWanted.dynamicFields['channel'] != shownFor.dynamicFields['channel'];
        if (channelChanged ||
            (!askodoxSameNeed(shownFor.subject, nowWanted.subject) &&
                !askodoxSameNeed('${shownFor.dynamicFields['said_subject'] ?? ''}', nowWanted.subject))) {
          // A different need -- or the same need from another channel (local
          // cards when online was asked): archived, recoverable, never shown
          // as the answer to this ask (APK 1312).
          _resultsHiddenFor = pinned;
          _boardMinimizedFor = null;
          _focusedMatch = null;
        } else if (_requirementSignature(shownFor) != _requirementSignature(nowWanted)) {
          _resultsOutdatedFor = pinned;
        }
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
      // Why this search ran (search-readiness gate) and the brain's state.
      'search_gate': _lastSearchGate,
      if (_lastDecision?.facts.isNotEmpty ?? false) 'brain_facts': _lastDecision!.facts,
      if (_lastDecision?.unknownCritical.isNotEmpty ?? false) 'brain_unknown': _lastDecision!.unknownCritical,
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

  bool _saysNearMe(String text) =>
      RegExp(r'\b(near me|nearby|around me|my location|current location|here)\b|నా దగ్గర|దగ్గరలో|मेरे पास',
              caseSensitive: false)
          .hasMatch(text);

  /// A search whose place came from the user's words (not the header /
  /// device place) becomes the conversation's requested place.
  void _rememberRequestedPlace(DealLocation location, String? headerLabel) {
    final label = location.label?.trim() ?? '';
    if (label.isEmpty || askodoxIsNearMePhrase(label)) return;
    final header = (headerLabel ?? '').trim().toLowerCase();
    if (header.isNotEmpty && (header == label.toLowerCase() || header.contains(label.toLowerCase()))) return;
    _requestedPlace = location;
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

  /// The ride / parcel / carpool this pinned route asks for, once both ends
  /// are on the map -- the hand-off to the ONE mobility system.
  String? _mobilityHandoffKind() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null) return null;
    final fields = deal.dynamicFields;
    if (fields['from_lat'] is! num || fields['to_lat'] is! num) return null;
    return askodoxMobilityKind('${deal.rawText} ${deal.subject ?? ''}');
  }

  /// The ride / parcel the conversation describes, as the ONE shared draft
  /// the Rides & deliveries screen opens with (labels + any map pins).
  MobilityDraft? _mobilityDraftFromChat() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null) return null;
    final kind = askodoxMobilityKind('${deal.rawText} ${deal.subject ?? ''}');
    if (kind == null || kind == 'carpool') return null;
    final fields = deal.dynamicFields;
    AskodoxPlace? end(String key) {
      final label = '${fields[key] ?? ''}'.trim();
      if (label.isEmpty) return null;
      final lat = fields['${key}_lat'], lng = fields['${key}_lng'];
      return AskodoxPlace(
          latitude: lat is num ? lat.toDouble() : 0, longitude: lng is num ? lng.toDouble() : 0, label: label);
    }

    final current = ref.read(askodoxMobilityDraftProvider);
    final draft = MobilityDraft(kind: kind, from: end('from'), to: end('to'));
    // Edits made on the Rides screen for this same trip win.
    if (current != null && current.kind == kind) {
      return MobilityDraft(kind: kind, from: current.from ?? draft.from, to: current.to ?? draft.to);
    }
    return draft;
  }

  void _openMobilityForm() {
    final draft = _mobilityDraftFromChat();
    if (draft == null) return;
    ref.read(askodoxMobilityDraftProvider.notifier).state = draft;
    context.push(draft.location);
  }

  /// Sends the pinned route to nearby approved partners. The reply is the
  /// backend's own stage: never "confirmed" until a partner accepts.
  Future<void> _requestMobility(String kind) async {
    if (kind == 'carpool') {
      context.push('/mobility?tab=2');
      return;
    }
    if (ref.read(authSessionProvider).user == null) {
      context.push('/onboarding?signin=1');
      return;
    }
    final fields = ref.read(universalDealControllerProvider).deal?.dynamicFields ?? const <String, Object?>{};
    Map<String, Object?> point(String end) => {
          'label': '${fields[end] ?? ''}',
          'latitude': (fields['${end}_lat'] as num).toDouble(),
          'longitude': (fields['${end}_lng'] as num).toDouble(),
        };
    // The shared draft (edited on the Rides screen) wins over the chat pins.
    final draft = _mobilityDraftFromChat();
    final pickup = draft?.from != null && draft!.from!.latitude != 0 ? askodoxMobilityPoint(draft.from!) : point('from');
    final drop = draft?.to != null && draft!.to!.latitude != 0 ? askodoxMobilityPoint(draft.to!) : point('to');
    setState(() => _sending = true);
    final result = await ref.read(mobilityRepositoryProvider).request(kind: kind, pickup: pickup, drop: drop);
    if (!mounted) return;
    final job = result.data;
    final text = job == null
        ? (_te ? 'రిక్వెస్ట్ పంపలేకపోయాం: ${result.error ?? ''}' : 'Could not send the request: ${result.error ?? ''}')
        : [
            job.stage,
            if (job.quote != null)
              _te ? 'అంచనా ₹${job.quote!.round()} (పార్ట్‌నర్ కన్ఫర్మ్ చేస్తారు).' : 'Estimate ₹${job.quote!.round()} (the partner confirms the fare).',
            _te ? 'ప్రొఫైల్ → రైడ్స్, పార్సెల్స్ లో ట్రాక్ చేయండి.' : 'Track it in Profile → Rides, parcels & carpool.',
          ].join('\n');
    setState(() {
      _sending = false;
      _turns.add(ConversationTurnRecord(text: text, isUser: false));
    });
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
    // Only a real thing is named in the comparison: a row whose title is a
    // place / price / status label is "this option" instead.
    final label = askodoxComparableLabel(match);
    await _send(_te
        ? (label == null ? 'ఈ ఎంపికను మిగతా ఎంపికలతో పోల్చండి' : '"$label" ని మిగతా ఎంపికలతో పోల్చండి')
        : (label == null ? 'Compare this option with the other options' : 'Compare "$label" with the other options'));
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
  Future<void> _speakReply(String reply,
      {required String userText, bool force = false, bool deviceOnly = false}) async {
    if (_speechMuted && !force) return; // muted: the text reply stays
    final markup = reply;
    final chunks = askodoxSpeechChunks(markup);
    if (chunks.length > 1) {
      await _speakChunks(markup, chunks, userText: userText, deviceOnly: deviceOnly);
      return;
    }
    reply = askodoxPlainReply(reply); // markup is for the eye, never spoken
    final turn = ++_speechTurn;
    _speakingText = reply;
    _speakingUserText = userText;
    _speechRangeStart = 0;
    _speechPaused = false;
    _pausedRemainder = null;
    bool current() => mounted && turn == _speechTurn && _voicePhase == _VoicePhase.speaking;
    final language = askodoxSpeechLanguage(
      reply: reply,
      userText: userText,
      uiTelugu: _te,
    );
    if (mounted) setState(() => _voicePhase = _VoicePhase.speaking);
    final lips = ref.read(askodoxCompanionVoiceProvider)..speechBegin(reply);
    try {
      // Flag voice.sarvam_tts off -> device TTS only (no Sarvam call).
      final audio = deviceOnly || !ref.read(askodoxFlagProvider('voice.sarvam_tts'))
          ? null
          : await ref
              .read(askodoxReplySpeechServiceProvider)
              .sarvamAudio(reply,
                  locale: language, voice: ref.read(appSettingsProvider).voicePreference.storageValue);
      if (!current()) return;
      if (audio != null) {
        lips.speechBegin(reply);
        _startLipSyncPolling(lips);
        _speakingEngine = 'sarvam';
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
      // Cut off by Stop or a newer reply: never fall back to the device voice.
      if (!current()) return;
      lastReplyVoiceEngine = 'device';
      final preference = ref.read(appSettingsProvider).voicePreference;
      if (preference != VoicePreference.automatic && !_voiceFallbackNoticeShown && mounted) {
        // Android does not say which device voices are male / female: say
        // once, briefly, that this reply may not match the choice.
        _voiceFallbackNoticeShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          key: const ValueKey('askodoxVoiceFallbackNotice'),
          duration: const Duration(seconds: 3),
          content: Text(_te
              ? 'ఇప్పుడు ఫోన్ వాయిస్ వాడుతున్నాం -- మీరు ఎంచుకున్న వాయిస్‌కి సరిపోకపోవచ్చు.'
              : 'Using the phone\'s voice right now -- it may not match your voice choice.'),
        ));
      }
      lips.speechBegin(reply);
      _speakingEngine = 'device';
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
      if (turn == _speechTurn) {
        _lipSyncTimer?.cancel();
        lips.speechEnd();
        _speakingEngine = '';
        if (mounted && _voicePhase == _VoicePhase.speaking) {
          setState(() {
            _speechPaused = false;
            _voicePhase = _VoicePhase.idle;
          });
        }
      }
    }
  }



  /// A long reply: ONE voice session that speaks chunk after chunk (the
  /// next chunk's audio is fetched while the current one plays) and reveals
  /// each chunk's text as it is read -- text and voice stay together. Stop /
  /// a newer reply end it; Sarvam pauses in place; device voice resumes with
  /// the rest (see [_pauseSpeaking]).
  Future<void> _speakChunks(String markup, List<({int start, int end})> chunks,
      {required String userText, bool deviceOnly = false}) async {
    final turn = ++_speechTurn;
    final plain = [for (final c in chunks) askodoxPlainReply(markup.substring(c.start, c.end)).trim()];
    final whole = askodoxPlainReply(markup);
    final language = askodoxSpeechLanguage(reply: whole, userText: userText, uiTelugu: _te);
    final revealIndex = _turns.lastIndexWhere((t) => !t.isUser && t.text == markup);
    _speakingUserText = userText;
    _speechPaused = false;
    _pausedRemainder = null;
    bool current() => mounted && turn == _speechTurn && _voicePhase == _VoicePhase.speaking;
    if (mounted) {
      setState(() {
        _voicePhase = _VoicePhase.speaking;
        if (revealIndex >= 0) {
          _revealTurn = revealIndex;
          _revealEnd = 0;
        }
      });
    }
    final lips = ref.read(askodoxCompanionVoiceProvider);
    final useSarvam = !deviceOnly && ref.read(askodoxFlagProvider('voice.sarvam_tts'));
    Future<Uint8List?> fetch(String text) async => useSarvam
        ? await ref
            .read(askodoxReplySpeechServiceProvider)
            .sarvamAudio(text, locale: language, voice: ref.read(appSettingsProvider).voicePreference.storageValue)
        : null;
    try {
      var next = fetch(plain.first);
      for (var i = 0; i < chunks.length; i++) {
        final audio = await next;
        if (!current()) return;
        if (i + 1 < chunks.length) next = fetch(plain[i + 1]);
        final text = plain[i];
        if (text.isEmpty) continue;
        _speakingText = text;
        _speechRangeStart = 0;
        _speechQueue = plain.sublist(i + 1);
        // Opus at ~32 kbps -> seconds of speech; device voice ~13 chars / s.
        final estimate = audio != null
            ? Duration(milliseconds: (audio.length * 8 / 32).round())
            : Duration(milliseconds: (text.length / 13 * 1000).round());
        if (_revealTurn != null) _typeReveal(chunks[i].start, chunks[i].end, estimate);
        lips.speechBegin(text);
        bool played = false;
        if (audio != null) {
          _startLipSyncPolling(lips);
          _speakingEngine = 'sarvam';
          played = await _device.invokeMethod<bool>(
                  'playReplyAudio', <String, Object?>{'bytes': audio, 'languageCode': language}) ==
              true;
          if (played) lastReplyVoiceEngine = 'sarvam_bulbul_v3';
        }
        _lipSyncTimer?.cancel();
        if (!current()) return;
        if (!played) {
          lastReplyVoiceEngine = 'device';
          _speakingEngine = 'device';
          await _device.invokeMethod<bool>('speakReply', <String, Object?>{
            'text': text,
            'languageCode': language,
            'voicePreference': ref.read(appSettingsProvider).voicePreference.storageValue,
          });
        }
        if (!current()) return;
      }
    } catch (_) {
      // The text reply stays available when no voice output works.
    } finally {
      if (turn == _speechTurn) {
        _lipSyncTimer?.cancel();
        lips.speechEnd();
        _speakingEngine = '';
        _speechQueue = const [];
        _clearReveal();
        if (mounted && _voicePhase == _VoicePhase.speaking) {
          setState(() {
            _speechPaused = false;
            _voicePhase = _VoicePhase.idle;
          });
        }
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
    // The centre mic / companion opens on Main Chat: a video, details or
    // study page pushed on top is closed first, so the hub, the composer and
    // the voice controls are visible instead of opening underneath it.
    ref.listen<bool>(askodoxCompanionHubOpenProvider, (previous, open) {
      if (!open || !mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context).popUntil((r) => r == route || r.isFirst);
      }
    });
    final hubOpen = ref.watch(askodoxCompanionHubOpenProvider);
    return ColoredBox(
        color: const Color(0xFFF9FBFF),
        child: Stack(children: [
          // ONE conversational page: the active results stay above, the
          // conversation about them scrolls below, then the input -- the
          // shell's nav sits under it. The board is sized from the height
          // ACTUALLY left for this column (header, nav and keyboard already
          // removed), so it can never push the latest replies or the input
          // off screen on a small phone; with no room it shows its pill.
          LayoutBuilder(builder: (context, constraints) {
            final pinned = _pinnedResultsTurn;
            final board = askodoxBoardStateOf(
              hasDeck: _active && pinned != null,
              retired: pinned != null && _resultsHiddenFor == pinned,
              minimized: pinned != null && _boardMinimizedFor == pinned,
              refreshing: _resultsStaleFor != null,
              outdated: pinned != null && _resultsOutdatedFor == pinned,
            );
            final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
            final expandedMode = _resultsMode == AskodoxResultsMode.expanded || _orderByMatchKey.isNotEmpty;
            final boardMax = pinned != null && _boardMegaFor == pinned && !keyboard
                ? askodoxBoardMegaHeight(constraints.maxHeight)
                : askodoxBoardMaxHeight(constraints.maxHeight, keyboard: keyboard, expanded: expandedMode);
            return Column(children: [
              switch (board) {
                AskodoxBoardState.hidden => const SizedBox.shrink(),
                AskodoxBoardState.archived => _archivedResultsChip(te, pinned!),
                AskodoxBoardState.minimized => _resultPill(te, pinned!),
                _ => boardMax == null ? _resultPill(te, pinned!) : _resultContext(te, pinned!, maxHeight: boardMax),
              },
              Expanded(child: _active ? _chat(te) : _home(te)),
              _composer(te)
            ]);
          }),
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
                          ref.watch(askodoxGreetingProvider(_lang)).valueOrNull ??
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


  /// The turn whose results are the active context (the latest search):
  /// kept above the conversation while the customer asks follow-ups.
  int? get _pinnedResultsTurn {
    final keys = _resultsByTurn.keys.where((k) => k >= 0 && k < _turns.length);
    if (keys.isEmpty) return null;
    return keys.reduce((a, b) => a > b ? a : b);
  }

  /// The results workspace size: compact by default (the conversation keeps
  /// most of the screen); a request in progress with a seller opens it fully.
  /// The size toggles, the "Results N" header, its summary line, the price
  /// strip and the category chips are hidden (APK 1303 phone finding): the
  /// cards themselves sit directly under the app header.
  /// The latest search-readiness decision (diagnostics trace).
  String _lastSearchGate = '';

  final AskodoxResultsMode _resultsMode = AskodoxResultsMode.compact;


  /// The ONE result workspace above the conversation: the latest search's
  /// cards only (never a copy in the chat), bounded height (smaller while the
  /// keyboard is open) so the latest messages and the input stay on screen.
  Widget _resultContext(bool te, int index, {required double maxHeight}) {
    // [maxHeight] bounds the WHOLE board (tab row + notices + cards), from
    // askodoxBoardMaxHeight: the conversation and the input always keep
    // their room below it.
    final tab = _boardTabFor[index] ?? AskodoxBoardTab.all;
    final tabEmpty = tab != AskodoxBoardTab.all &&
        askodoxBoardTabRows(tab, _resultsByTurn[index]?.matches ?? const []).isEmpty;
    return Container(
      key: const Key('askodoxResultContext'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE1E8F2))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ONE row: Result Board | Local | Online | Deals | Reviews | Videos,
        // Expand, Minimize. Tabs are views of THIS deck, never new searches.
        AskodoxResultBoardTabRow(
          selected: tab,
          counts: askodoxBoardTabCounts(_resultsByTurn[index]?.matches ?? const []),
          lang: _lang,
          expanded: _boardMegaFor == index,
          onSelect: (next) => setState(() => _boardTabFor[index] = next),
          // Minimize: the board folds into its pill so the conversation gets
          // the screen; nothing is lost (tap the pill to restore).
          onMinimize: () => setState(() {
            _boardMinimizedFor = index;
            _boardMegaFor = null;
          }),
          // Mega expand: the whole board with full cards; the input and the
          // latest conversation lines keep their room.
          onExpand: () => setState(() => _boardMegaFor = _boardMegaFor == index ? null : index),
        ),
        if (_resultsStaleFor != null)
          Padding(
            key: const Key('askodoxResultsRefreshing'),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    te ? '$_resultsStaleFor కోసం ఫలితాలు నవీకరిస్తున్నాను…' : 'Updating results for $_resultsStaleFor…',
                    style: const TextStyle(fontSize: 11.5, color: _muted)),
              ),
            ]),
          ),
        if (_resultsOutdatedFor == index && _resultsStaleFor == null)
          Padding(
            key: const Key('askodoxResultsOutdated'),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(
                te
                    ? 'ఇవి మీ పాత వివరాలకు ఫలితాలు -- కొత్త వివరాలతో త్వరలో నవీకరిస్తాను.'
                    : 'These are for your earlier details -- I will update them for the new ones.',
                style: const TextStyle(fontSize: 11.5, color: _muted)),
          ),
        Flexible(
          child: Opacity(
            // Cards from the old place / earlier details are dimmed.
            opacity: _resultsStaleFor == null && _resultsOutdatedFor != index ? 1 : .45,
            child: SingleChildScrollView(
              key: const Key('askodoxResultContextScroll'),
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tabEmpty
                    ? [
                        Padding(
                          key: ValueKey('askodoxBoardTabEmpty-${tab.name}'),
                          padding: const EdgeInsets.fromLTRB(2, 8, 8, 10),
                          child: Text(askodoxBoardTabEmptyText(tab, _lang),
                              style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.35)),
                        ),
                      ]
                    : _turnResults(index, _turns[index], te, workspace: true, tab: tab),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// The minimized Result Board: one line with what the results are for,
  /// plus the selected option (if any) as compact conversation context.
  /// Result Board ARCHIVED state: a deck retired by a topic change is not
  /// erased -- one small chip brings it back on the customer's tap (it never
  /// returns on its own over the new topic).
  Widget _archivedResultsChip(bool te, int index) {
    final count = _resultsByTurn[index]?.matches.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: ActionChip(
          key: const Key('askodoxArchivedResultsRestore'),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.history, size: 16),
          label: Text(te ? 'మునుపటి ఫలితాలు ($count)' : 'Earlier results ($count)',
              style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() {
            _resultsHiddenFor = null;
            _boardMinimizedFor = null;
          }),
        ),
      ),
    );
  }

  Widget _resultPill(bool te, int index) {
    final results = _resultsByTurn[index];
    if (results == null) return const SizedBox.shrink();
    final deal = _dealByTurn[index];
    final budget = deal?.dynamicFields['budget_max'];
    final label = askodoxBoardPillLabel(results,
        subject: deal?.subject, budget: budget is num ? budget.toDouble() : null, lang: _lang);
    final focused = _focusedMatch;
    final selected = focused != null && results.matches.any((m) => m.id == focused.id) ? focused : null;
    return Container(
      key: const Key('askodoxResultPill'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FBFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE1E8F2))),
      ),
      child: Row(children: [
        Expanded(
          child: Material(
            color: const Color(0xFFEAF1FF),
            shape: const StadiumBorder(),
            child: InkWell(
              key: const Key('askodoxResultPillRestore'),
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _boardMinimizedFor = null),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Text('$label ▲',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: InputChip(
              key: const Key('askodoxSelectedContext'),
              label: Text(askodoxComparableLabel(selected) ?? selected.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
              avatar: const Icon(Icons.push_pin_outlined, size: 14),
              onPressed: () => setState(() => _boardMinimizedFor = null),
              onDeleted: () => setState(() => _focusedMatch = null),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ]),
    );
  }

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
        // Smaller while results are on screen: the conversation stays visible.
        size: _pinnedResultsTurn == null ? 88 : 60,
        results: _actionConfirmed ? 0 : _latestResults()?.matches.length ?? 0,
        onTap: _onCompanionTap,
        // After an assistant reply the reply itself is the message: no second
        // bubble restating it between turns (APK 1275). Live states
        // (listening / understanding / thinking) still show their line.
        showLine: (_voicePhase == _VoicePhase.idle || _voicePhase == _VoicePhase.recording) &&
            (_turns.isEmpty ||
                _turns.last.isUser ||
                _resultsByTurn.containsKey(_turns.length - 1) ||
                const {
                  AskodoxCompanionMood.listening,
                  AskodoxCompanionMood.understanding,
                  AskodoxCompanionMood.thinking,
                }.contains(_companionMood)),
        guidance: _companionGuidance(),
        subject: ref.watch(universalDealControllerProvider).deal?.subject,
        foundLabel: _lang == 'te' || _lang == 'en' || _lang == 'hi'
            ? null
            : askodoxChatLabel('found_pick', _lang, count: _latestResults()?.matches.length ?? 0),
      );

  Future<void> _answerCapability(AskodoxTaxonomyMatch match, String question, bool speakResponse) async {
    final te = _te;
    final label = match.label;
    final text = match.provider
        ? (te
            ? 'తప్పకుండా! ASKODOX లో డెలివరీ / రైడ్ పార్ట్‌నర్‌గా చేరవచ్చు: ఒకసారి అప్లై చేయండి, స్టాఫ్ రివ్యూ తర్వాత ఆన్‌లైన్‌కి వెళ్లి దగ్గరి రిక్వెస్ట్‌లు అంగీకరించవచ్చు. మీరు అంగీకరించిన తర్వాతే కస్టమర్ వివరాలు కనిపిస్తాయి.'
            : 'Yes! You can join ASKODOX as a delivery / ride partner: apply once, and after a quick staff review go online and accept nearby requests. Customer details are shared only after you accept.')
        : (te
            ? 'అవును -- $label: దగ్గరి షాప్ నుంచి ఆర్డర్ చేసి డెలివరీ ఎంచుకోవచ్చు, లేదా డెలివరీ పార్ట్‌నర్‌తో పికప్ పంపవచ్చు. ఏది కావాలి?'
            : 'Yes -- $label: order from a nearby place and choose delivery, or send a pickup with an ASKODOX delivery partner. Which would you like?');
    setState(() {
      _turns.add(ConversationTurnRecord(text: text, isUser: false));
      _taxonomyByTurn[_turns.length - 1] = match;
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) unawaited(_speakReply(text, userText: question));
  }

  Widget _taxonomyActions(bool te, AskodoxTaxonomyMatch match) {
    final kind = match.mobilityKind;
    final sendKind = const ['parcel', 'documents', 'local_delivery', 'pickup_drop'].contains(kind)
        ? kind!
        : (match.actions.contains('request_ride') ? (kind ?? 'ride_taxi') : 'local_delivery');
    final subject = match.label.toLowerCase().replaceAll(' delivery', '');
    return Padding(
      key: ValueKey('askodoxTaxonomyActions-${match.key}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 6, children: [
        if (match.provider)
          ActionChip(
            key: const Key('askodoxJoinAsPartner'),
            avatar: const Icon(Icons.delivery_dining_rounded, size: 18),
            label: Text(te ? 'పార్ట్‌నర్‌గా చేరండి' : 'Join as a partner'),
            onPressed: () => context.push('/mobility?tab=3'),
          )
        else ...[
          if (match.actions.contains('order') && subject.isNotEmpty && subject != 'delivery')
            ActionChip(
              key: const Key('askodoxTaxonomyOrderNearby'),
              avatar: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(te ? 'దగ్గరలో $subject' : '$subject near me'),
              onPressed: _sending ? null : () => _send(te ? 'దగ్గరలో $subject' : '$subject near me'),
            ),
          ActionChip(
            key: const Key('askodoxTaxonomySendPickup'),
            avatar: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(match.actions.contains('request_ride')
                ? (te ? 'రైడ్ బుక్ చేయండి' : 'Book a ride')
                : (te ? 'పికప్ / పార్సెల్ పంపండి' : 'Send a pickup / parcel')),
            onPressed: () {
              final draft = MobilityDraft(kind: sendKind);
              ref.read(askodoxMobilityDraftProvider.notifier).state = draft;
              context.push(draft.location);
            },
          ),
        ],
      ]),
    );
  }

  Future<void> _answerFromVideo(String videoRef, String question, bool speakResponse) async {
    AskodoxVideoAnswer? answer;
    try {
      answer = await ref.read(askodoxVideoServiceProvider).ask(videoRef, question, language: _lang);
    } catch (_) {
      answer = null;
    }
    if (!mounted) return;
    final te = _lang == 'te';
    final text = answer == null
        ? (te
            ? 'ఇప్పుడు ఈ వీడియో అధ్యయనాన్ని చేరుకోలేకపోయాను. "వీడియో ప్రశ్నలు" తెరిచి మళ్లీ అడగండి.'
            : 'I could not reach this video\'s study right now. Open "Ask about this video" and try again.')
        : askodoxVideoAnswerText(answer.answer, answer.timestamps,
            found: answer.found, lang: _lang, basis: answer.basis);
    setState(() {
      _turns.add(ConversationTurnRecord(text: text, isUser: false));
      _sending = false;
    });
    await _store.save(_turns);
    await _saveSnapshot();
    _scrollBottom();
    if (speakResponse) unawaited(_speakReply(text, userText: question));
  }

  /// An uploaded video's grounded study (fact sheet + Q&A + market +
  /// next steps); a next step continues in THIS conversation.
  Future<void> _openUploadStudy(String studyRef) async {
    final lang = _lang;
    final pages = ref.read(askodoxDetailPagesOpenProvider.notifier);
    pages.state++;
    final String? result;
    try {
      result = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(askodoxChatLabel('video_study_ask', lang))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            AskodoxVideoStudyPanel(
              videoRef: studyRef,
              lang: lang,
              onFollow: (ask) => Navigator.of(context).pop('$askodoxVideoFollowUpPrefix$ask'),
            ),
          ]),
        ),
      ));
    } finally {
      pages.state = pages.state > 0 ? pages.state - 1 : 0;
    }
    if (!mounted || result == null || !result.startsWith(askodoxVideoFollowUpPrefix)) return;
    final ask = result.substring(askodoxVideoFollowUpPrefix.length).trim();
    if (ask.isNotEmpty) await _send(ask);
  }

  /// A turn's message bubble and its notices.
  List<Widget> _turnHead(int index, ConversationTurnRecord turn, bool te) => [
            Align(
              alignment:
                  turn.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
               key: ValueKey('askodoxBubble-$index'),
               onLongPress: turn.text.trim().isEmpty ? null : () => _messageActions(turn, te),
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
                      if (_sentImages[attachment['id']] case final bytes?)
                        Padding(
                          key: ValueKey('askodoxSentImage-${attachment['id']}'),
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(bytes,
                                width: 180,
                                height: 140,
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                                semanticLabel: attachment['name'],
                                errorBuilder: (_, __, ___) => Text(attachment['name'] ?? '',
                                    style: const TextStyle(color: Colors.white, fontSize: 12))),
                          ),
                        )
                      else
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
                    for (final attachment in turn.attachments)
                      if (attachment['study_ref'] case final studyRef?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ActionChip(
                            key: ValueKey('askodoxUploadStudy-$studyRef'),
                            avatar: const Icon(Icons.auto_awesome_motion_rounded, size: 16),
                            label: Text(askodoxChatLabel('video_study_ask', _lang)),
                            onPressed: () => _openUploadStudy(studyRef),
                          ),
                        )
                      else if (attachment['study_note'] case final note?)
                        Padding(
                          key: const Key('askodoxUploadStudyNote'),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(note,
                              style: TextStyle(
                                  fontSize: 12, color: turn.isUser ? Colors.white70 : _muted)),
                        ),
                    if (turn.text.isNotEmpty)
                      // Assistant replies render their structure (headings,
                      // points, bold, tables, links) -- never raw "**".
                      turn.isUser
                          ? Text(turn.text,
                              style: const TextStyle(color: Colors.white, height: 1.35, fontWeight: FontWeight.w500))
                          : AskodoxRichReply(
                              // Being read aloud: the text appears as it is spoken.
                              _revealTurn == index && _revealEnd != null
                                  ? askodoxRevealPrefix(turn.text, _revealEnd!)
                                  : turn.text,
                              style: const TextStyle(color: _ink, height: 1.35, fontWeight: FontWeight.w500)),
                  ],
                ),
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
  /// A turn's catalogue card (seller flow) and -- in the top workspace only --
  /// its result cards. The chat never shows result cards: the latest search
  /// lives ONCE in the workspace, and earlier searches are replaced, never
  /// left in the conversation as stale copies.
  List<Widget> _turnResults(int index, ConversationTurnRecord turn, bool te,
          {bool workspace = false, AskodoxBoardTab tab = AskodoxBoardTab.all}) => [
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
            if (workspace && index == _pinnedResultsTurn)
              if (_resultsByTurn[index] case final results?)
              _ChatResultsView(
                key: ValueKey(tab == AskodoxBoardTab.all ? 'askodoxChatResults-$index' : 'askodoxChatResults-$index-${tab.name}'),
                workspace: true,
                positions: _boardPositions,
                mega: _boardMegaFor == index,
                results: askodoxResultsForTab(results, tab),
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
                // Referral / join chips only when the customer's own words are
                // about referring or offering -- otherwise Profile -> Refer.
                onRefer: _sending || !_growthPromptAllowed(index) ? null : () => _referProvider(index, results),
                onJoin: _sending || !_growthPromptAllowed(index) ? null : () => _joinAsProvider(index, results),
              ),
      ];

  bool _growthPromptAllowed(int assistantTurn) {
    for (var i = assistantTurn - 1; i >= 0 && i < _turns.length; i--) {
      if (_turns[i].isUser) return _turns[i].context.isEmpty && askodoxAllowsGrowthPrompt(_turns[i].text);
    }
    return false;
  }

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
            if (_taxonomyByTurn[index] case final match?) _taxonomyActions(te, match),
            if (_guideByTurn[index] case final flow?)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, children: [
                  ActionChip(
                    key: ValueKey('askodoxGuideOffer-${flow.id}'),
                    avatar: const Icon(Icons.assistant_navigation, size: 18),
                    label: Text(te ? 'స్క్రీన్‌పై చూపించు' : 'Show me on screen'),
                    onPressed: () => ref.read(askodoxGuideProvider.notifier).start(flow),
                  ),
                  ActionChip(
                    key: const Key('askodoxGuideSupport'),
                    avatar: const Icon(Icons.support_agent_rounded, size: 18),
                    label: Text(te ? 'కస్టమర్ కేర్' : 'Customer Care'),
                    onPressed: _sending
                        ? null
                        : () => _send(te ? 'నేను కస్టమర్ కేర్‌తో మాట్లాడాలి' : 'I want to talk to Customer Care'),
                  ),
                ]),
              ),
            if (index == _turns.length - 1 && !turn.isUser && _mobilityDraftFromChat() != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ActionChip(
                  key: const Key('askodoxMobilityForm'),
                  avatar: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: Text(te ? 'రైడ్స్‌లో వివరాలు మార్చండి' : 'Edit in Rides & deliveries'),
                  onPressed: _sending ? null : _openMobilityForm,
                ),
              ),
            if (index == _turns.length - 1 && !turn.isUser && !_routePinsNeeded())
              if (_mobilityHandoffKind() case final kind?)
                Padding(
                  key: const Key('askodoxMobilityHandoff'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ActionChip(
                    avatar: Icon(kind == 'parcel' || kind == 'documents' ? Icons.local_shipping_outlined : Icons.local_taxi_outlined, size: 18),
                    label: Text(kind == 'carpool'
                        ? (te ? 'కార్‌పూల్ చూడండి' : 'Find a carpool')
                        : kind == 'parcel' || kind == 'documents' || kind == 'pickup_drop'
                            ? (te ? 'డెలివరీ పార్ట్‌నర్‌ను అడగండి' : 'Request a delivery partner')
                            : (te ? 'డ్రైవర్‌ను అడగండి' : 'Request a driver')),
                    onPressed: _sending ? null : () => _requestMobility(kind),
                  ),
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
                onSendReply: (caseId, message) {
                  final session = ref.read(authSessionProvider);
                  return ref.read(askodoxSupportEscalationServiceProvider).reply(
                        caseId,
                        message,
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
              // The active results are shown once, above the conversation.
              if (index != _pinnedResultsTurn) ..._turnResults(index, turn, te),
              ..._turnFollowUps(index, turn, te),
            ],
          // ...then the CURRENT exchange: its results first, the companion
          // in the middle, and the conversation itself at the bottom next to
          // the input -- however many results there are.
          for (final (index, turn) in _turns.indexed)
            if (index >= _currentExchangeStart && index != _pinnedResultsTurn) ..._turnResults(index, turn, te),
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
                message: _listingBanner!,
                isError: _listingBannerIsError,
                onSignIn: _listingNeedsSignIn ? () => context.push('/onboarding?signin=1') : null,
                signInLabel: te ? 'సైన్ ఇన్' : 'Sign in'),
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
            icon: const Icon(Icons.close_rounded, color: _muted))
        else
          // The ONE attachment control: Camera / Photos / Videos / Files.
          AskodoxAttachButton(
            lang: _lang,
            enabled: !_sending,
            onPick: (choice) => unawaited(_pickAttachment(choice)),
          ),
        Expanded(
          child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !_sending,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendFromComposer(),
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
          onPressed: _sending ? null : _sendFromComposer,
          style: IconButton.styleFrom(
            backgroundColor: _blue,
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero),
          icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white)),
        ]),
        // ONE small, global accuracy note (instead of a warning on every
        // result): shown once results / answers are on screen.
        if (_active)
          Padding(
            key: const Key('askodoxAccuracyNote'),
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              switch (_lang) {
                'te' => 'ASKODOX తప్పులు చేయవచ్చు. ముఖ్యమైన వివరాలను ఒకసారి తనిఖీ చేయండి.',
                'hi' => 'ASKODOX से गलती हो सकती है। ज़रूरी जानकारी एक बार जांच लें।',
                _ => 'ASKODOX can make mistakes. Check important details.',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 10.5),
            ),
          ),
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
        else if (_voicePhase == _VoicePhase.speaking) ...[
          IconButton(
            key: Key(_speechPaused ? 'askodoxResumeSpeaking' : 'askodoxPauseSpeaking'),
            tooltip: _speechPaused ? (te ? 'కొనసాగించు' : 'Resume') : (te ? 'ఆపి ఉంచు' : 'Pause'),
            visualDensity: VisualDensity.compact,
            onPressed: _speechPaused ? _resumeSpeaking : _pauseSpeaking,
            icon: Icon(_speechPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
          IconButton(
            key: const Key('askodoxMuteSpeaking'),
            tooltip: te ? 'వాయిస్ జవాబులు మ్యూట్' : 'Mute voice replies',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleMute,
            icon: const Icon(Icons.volume_off_rounded),
          ),
          TextButton(
            key: const Key('askodoxStopSpeaking'),
            onPressed: _stopSpeaking,
            child: Text(te ? 'ఆపండి' : 'Stop'),
          ),
        ],
      ]),
    );
  }

  /// Long-press on any message: copy, select text, share (the Android share
  /// sheet -- the user picks where; nothing is posted by ASKODOX), and for
  /// replies: replay aloud and mute / unmute voice replies.
  Future<void> _messageActions(ConversationTurnRecord turn, bool te) async {
    final text = turn.isUser ? turn.text.trim() : askodoxPlainReply(turn.text).trim();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('askodoxMessageCopy'),
            leading: const Icon(Icons.copy_rounded),
            title: Text(te ? 'కాపీ' : 'Copy'),
            onTap: () => Navigator.pop(sheet, 'copy'),
          ),
          ListTile(
            key: const Key('askodoxMessageSelect'),
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(te ? 'టెక్స్ట్ ఎంచుకోండి' : 'Select text'),
            onTap: () => Navigator.pop(sheet, 'select'),
          ),
          ListTile(
            key: const Key('askodoxMessageShare'),
            leading: const Icon(Icons.share_rounded),
            title: Text(te ? 'షేర్' : 'Share'),
            onTap: () => Navigator.pop(sheet, 'share'),
          ),
          if (!turn.isUser) ...[
            ListTile(
              key: const Key('askodoxMessageReplay'),
              leading: const Icon(Icons.replay_rounded),
              title: Text(te ? 'మళ్లీ వినిపించు' : 'Replay aloud'),
              onTap: () => Navigator.pop(sheet, 'replay'),
            ),
            ListTile(
              key: const Key('askodoxMessageMute'),
              leading: Icon(_speechMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              title: Text(_speechMuted
                  ? (te ? 'వాయిస్ జవాబులు ఆన్' : 'Unmute voice replies')
                  : (te ? 'వాయిస్ జవాబులు మ్యూట్' : 'Mute voice replies')),
              onTap: () => Navigator.pop(sheet, 'mute'),
            ),
          ],
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(te ? 'కాపీ అయింది' : 'Copied')));
        }
      case 'select':
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            content: SingleChildScrollView(
              child: SelectableText(text, key: const Key('askodoxMessageSelectable')),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: Text(te ? 'మూసివేయి' : 'Close')),
            ],
          ),
        );
      case 'share':
        try {
          await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': text, 'title': 'ASKODOX'});
        } catch (_) {
          if (mounted) _voiceError(te ? 'షేర్ చేయలేకపోయాను.' : 'Could not open sharing.');
        }
      case 'replay':
        await _replayReply(turn.text);
      case 'mute':
        await _toggleMute();
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
  const _ListingBanner({required this.message, required this.isError, this.onSignIn, this.signInLabel = 'Sign in'});
  final String message;
  final bool isError;
  final VoidCallback? onSignIn;
  final String signInLabel;

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
        if (onSignIn != null)
          TextButton(
              key: const Key('askodoxListingSignIn'), onPressed: onSignIn, child: Text(signInLabel)),
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
    this.onSendReply,
  });

  final bool te;
  final bool critical;
  final AskodoxSupportCase? supportCase;
  final Future<Map<String, Object?>?> Function(String caseId)? onCheckReply;
  final Future<Map<String, Object?>?> Function(String caseId, String message)? onSendReply;
  final Future<void> Function() onChat;
  final Future<void> Function(String uri) onOpen;

  @override
  State<_SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<_SupportCard> {
  bool _busy = false;
  String? _reply;
  String? _staffMessage;
  bool _canReply = false;
  final _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _send(String caseId) async {
    final text = _answer.text.trim();
    if (text.isEmpty || widget.onSendReply == null) return;
    setState(() => _busy = true);
    final status = await widget.onSendReply!(caseId, text);
    if (!mounted) return;
    if (status != null) _answer.clear();
    _show(status, sent: status != null);
  }

  Future<void> _check(String caseId) async {
    setState(() => _busy = true);
    final status = await widget.onCheckReply!(caseId);
    if (!mounted) return;
    _show(status);
  }

  void _show(Map<String, Object?>? status, {bool sent = false}) {
    final te = widget.te;
    // The latest message from ASKODOX Support (staff), shown as-is.
    final messages = status?['messages'];
    String? staff;
    if (messages is List) {
      for (final m in messages.reversed) {
        if (m is Map && m['from'] == 'staff' && m['kind'] == 'message') {
          staff = '${m['body'] ?? ''}'.trim();
          break;
        }
      }
    }
    setState(() {
      _staffMessage = (staff?.isNotEmpty ?? false) ? staff : null;
      _canReply = status?['can_reply'] == true;
      _busy = false;
      if (sent) {
        _reply = te ? 'మీ సమాధానం సపోర్ట్‌కు పంపబడింది.' : 'Your answer was sent to Support.';
      } else if (status == null) {
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
          if (_staffMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text((te ? 'సపోర్ట్: ' : 'Support: ') + _staffMessage!,
                  key: const Key('askodoxSupportStaffMessage'),
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ),
          if (_canReply && widget.onSendReply != null)
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('askodoxSupportAnswer'),
                  controller: _answer,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: te ? 'సపోర్ట్‌కు సమాధానం…' : 'Answer Support…'),
                ),
              ),
              IconButton(
                key: const Key('askodoxSupportSend'),
                tooltip: te ? 'పంపు' : 'Send',
                onPressed: _busy ? null : () => _send(supportCase.caseId),
                icon: const Icon(Icons.send_rounded, color: _blue),
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
    this.workspace = false,
    this.positions,
    this.mega = false,
  });

  final AskodoxChatResults results;

  /// Category box positions (owned by the screen: survive minimize).
  final Map<String, int>? positions;

  /// Mega expand: full cards (all details) inside the category boxes.
  final bool mega;

  /// Drawn in the top result workspace: the cards only -- no price summary
  /// strip, no "Online" heading over the comparison, no All / Local / Deals /
  /// Online chips (hidden UI; the data behind them is unchanged).
  final bool workspace;
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
        // A provider problem (quota / rate limit / key / outage) is said as
        // that -- never dressed up as "nothing found".
        if (askodoxProviderProblemText(results, telugu: te) case final problem?)
          _notice(
            key: const Key('askodoxResultsProviderError'),
            icon: Icons.cloud_off_rounded,
            text: problem,
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
        if (!workspace)
          if (AskodoxLocalOnlineSummary.of(results.matches) case final summary?) _compareStrip(summary),
        // Several kinds of results (local, sponsored, online, ...): ONE
        // compact horizontal comparison, like the approved reference. A
        // single kind, or an option with a live request/order, keeps the
        // sectioned layout below.
        if (_comparison case final groups?
            when !workspace &&
                !groups.any((g) => g.$1 == AskodoxCompareKind.local) &&
                groups.any((g) => g.$1 == AskodoxCompareKind.online))
          _heading(askodoxSegmentTitle(AskodoxResultSegment.online, telugu: te, hasLocal: false, lang: lang),
              Icons.public_rounded),
        if (_comparison case final groups?)
          _ComparisonBoard(
            key: const Key('askodoxComparison'),
            groups: groups,
            showTabs: !workspace,
            lang: te ? 'te' : lang,
            positions: positions,
            positionKey: results.dealId ?? '',
            boxes: workspace && mega,
            card: (match, kind) => _card(match, compact: !mega, kind: kind),
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
        relatedVideos: chatResultActionFor(match) == ChatResultAction.watchVideo
            ? [
                for (final m in results.matches)
                  if (m.id != match.id && chatResultActionFor(m) == ChatResultAction.watchVideo) m,
              ]
            : const [],
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
    // Quota / rate-limit / key / outage problems have their own notice.
    final down = askodoxProviderProblemText(results, telugu: te) != null
        ? <String>[]
        : results.sourcesWith('unavailable').map(label).toList();
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E0FF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.near_me_rounded, size: 14, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_l('nearby_from', 'దగ్గరలో', 'Nearby from')} ${money(s.localPrice)}'
              '${s.localDistanceKm == null ? '' : ' · ${s.localDistanceKm!.toStringAsFixed(1)} km'} · ${s.localCount}',
              key: const Key('askodoxCompareLocal'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        Row(children: [
          const Icon(Icons.public_rounded, size: 14, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_l('online_from', 'ఆన్‌లైన్', 'Online from')} ${money(s.onlinePrice)}'
              '${s.onlinePrice != null && !s.onlineVerified ? (te ? ' (పేజీలో)' : ' (page price)') : ''}'
              '${s.onlineSource == null ? '' : ' · ${s.onlineSource}'} · ${s.onlineCount}',
              key: const Key('askodoxCompareOnline'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w600),
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
      AskodoxCompareKind.shorts => const Color(0xFFB0306A),
      AskodoxCompareKind.news => const Color(0xFF3B6EA8),
    };

/// The compact comparison after a request: a row of kind tabs (only the
/// kinds this request returned, with counts) above ONE horizontal rail of
/// labelled cards. "All" keeps every kind in column order.
class _ComparisonBoard extends StatefulWidget {
  const _ComparisonBoard(
      {super.key,
      required this.groups,
      required this.card,
      required this.lang,
      this.showTabs = true,
      this.positions,
      this.positionKey = '',
      this.boxes = false});

  /// Mega-expanded board: one box per category with up / down navigation.
  /// The default board keeps the locked one-rail layout (after 1303).
  final bool boxes;

  /// Result Board navigation: which card each category box shows, owned by
  /// the screen so it survives minimize / restore / mega expand.
  final Map<String, int>? positions;
  final String positionKey;

  final List<(AskodoxCompareKind, List<UniversalMatch>)> groups;

  /// The All / Local / Deals / Online chips. Hidden in the top workspace:
  /// then every card shows in ONE rail (no preview limit, no "View all"
  /// tiles that would need a chip to go back).
  final bool showTabs;
  final Widget Function(UniversalMatch match, AskodoxCompareKind kind) card;
  final String lang;

  @override
  State<_ComparisonBoard> createState() => _ComparisonBoardState();
}

class _ComparisonBoardState extends State<_ComparisonBoard> {
  AskodoxCompareKind? _only;

  int _at(AskodoxCompareKind kind, int count) =>
      askodoxBoardPosition(widget.positions?['${widget.positionKey}:${kind.name}'] ?? 0, count);

  void _move(AskodoxCompareKind kind, int count, int delta) {
    final next = askodoxBoardPosition(_at(kind, count) + delta, count);
    setState(() => (widget.positions ?? <String, int>{})['${widget.positionKey}:${kind.name}'] = next);
  }

  /// The top Result Board: one box per category, side by side; inside a box
  /// the customer moves up / down through that category (buttons, vertical
  /// swipe), with a "2/10" counter.
  Widget _boxes() => SingleChildScrollView(
        key: const Key('askodoxComparisonRail'),
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (kind, rows) in widget.groups)
            if (rows.isNotEmpty) _box(kind, rows),
        ]),
      );

  Widget _box(AskodoxCompareKind kind, List<UniversalMatch> rows) {
    final at = _at(kind, rows.length);
    final match = rows[at];
    final color = _kindColor(kind);
    final many = rows.length >= 2;
    Widget arrow(String key, IconData icon, int delta, bool enabled, String label) => IconButton(
          key: ValueKey('askodoxCategory$key-${kind.name}'),
          tooltip: label,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: enabled ? () => _move(kind, rows.length, delta) : null,
          icon: Icon(icon, color: enabled ? color : const Color(0xFFB8C2D3)),
        );
    return Padding(
      key: ValueKey('askodoxCategoryBox-${kind.name}'),
      padding: const EdgeInsets.only(right: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(askodoxCompareLabel(kind, widget.lang),
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          if (many) ...[
            const SizedBox(width: 6),
            Text('${at + 1}/${rows.length}',
                key: ValueKey('askodoxCategoryCounter-${kind.name}'),
                style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 11.5)),
            arrow('Prev', Icons.keyboard_arrow_up_rounded, -1, at > 0,
                switch (widget.lang) { 'te' => 'ముందుది', 'hi' => 'पिछला', _ => 'Previous' }),
            arrow('Next', Icons.keyboard_arrow_down_rounded, 1, at < rows.length - 1,
                switch (widget.lang) { 'te' => 'తర్వాతది', 'hi' => 'अगला', _ => 'Next' }),
          ],
        ]),
        GestureDetector(
          key: ValueKey('askodoxCategorySwipe-${kind.name}'),
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: many
              ? (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v.abs() < 80) return;
                  _move(kind, rows.length, v < 0 ? 1 : -1); // swipe up = next
                }
              : null,
          // A box is one screen-width column; the next category is a swipe
          // to the side.
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 40).clamp(220.0, 420.0),
            child: KeyedSubtree(
                key: ValueKey('askodoxKind-${kind.name}-${match.id}'), child: widget.card(match, kind)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showTabs && widget.boxes) return _boxes();
    final all = switch (widget.lang) { 'te' => 'అన్నీ', 'hi' => 'सभी', _ => 'All' };
    final total = widget.groups.fold<int>(0, (n, g) => n + g.$2.length);
    Widget tab(String key, String label, int count, Color color, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            key: ValueKey('askodoxCompareTab-$key'),
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
      if (widget.showTabs && widget.groups.length >= 2)
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          tab('all', all, total, const Color(0xFF10204A), _only == null, () => setState(() => _only = null)),
          for (final (kind, rows) in widget.groups)
            tab(kind.name, askodoxCompareLabel(kind, widget.lang), rows.length, _kindColor(kind), _only == kind,
                () => setState(() => _only = _only == kind ? null : kind)),
        ]),
      ),
      // "All" = a short preview of every group (at most
      // [askodoxAllPreviewPerGroup] each) with "View all" for the rest; a
      // selected category shows only its own results. Same cards either way.
      SingleChildScrollView(
        key: const Key('askodoxComparisonRail'),
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (kind, rows) in widget.groups)
            if (_only == null || _only == kind) ...[
              for (final match in (widget.showTabs && _only == null && widget.groups.length >= 2
                  ? rows.take(askodoxAllPreviewPerGroup)
                  : rows))
                KeyedSubtree(key: ValueKey('askodoxKind-${kind.name}-${match.id}'), child: widget.card(match, kind)),
              if (widget.showTabs && _only == null && widget.groups.length >= 2 && rows.length > askodoxAllPreviewPerGroup)
                _viewAll(kind, rows.length),
            ],
        ]),
      ),
    ]);
  }

  /// "View all / అన్ని చూడండి" after a group's preview: opens that category.
  Widget _viewAll(AskodoxCompareKind kind, int count) {
    final label = switch (widget.lang) { 'te' => 'అన్ని చూడండి', 'hi' => 'सभी देखें', _ => 'View all' };
    final color = _kindColor(kind);
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        key: ValueKey('askodoxViewAll-${kind.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _only = kind),
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_forward_rounded, size: 18, color: color),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5, height: 1.25)),
            Text('${askodoxCompareLabel(kind, widget.lang)} · $count',
                textAlign: TextAlign.center,
                softWrap: true,
                style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.25)),
          ]),
        ),
      ),
    );
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
    this.relatedVideos = const [],
  });
  final UniversalMatch match;

  /// The other videos in these results (the viewer's Related / Next list).
  final List<UniversalMatch> relatedVideos;

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
    final pages = ref.read(askodoxDetailPagesOpenProvider.notifier);
    // Captured before awaiting: this card may be rebuilt elsewhere while
    // the viewer is open, and the follow-up must still reach the chat.
    final chatRequests = ref.read(askodoxChatRequestProvider.notifier);
    pages.state++;
    final String? result;
    try {
      result = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => AskodoxVideoViewerScreen(
          video: _match,
          telugu: _te,
          lang: ref.read(askodoxReplyLanguageProvider),
          related: widget.relatedVideos,
        ),
      ));
    } finally {
      pages.state = pages.state > 0 ? pages.state - 1 : 0;
    }
    if (result == askodoxVideoAskResult) {
      widget.onAsk?.call();
    } else {
      // "Find near me" (follow-up search), a typed question, the mic or an
      // attachment from the video page: the same conversation continues.
      final next = askodoxVideoChatRequest(result, title: _match.title);
      if (next != null) chatRequests.state = next;
    }
  }

  Future<void> _openDestination() async {
    // Partner Hub rows open through ASKODOX's tracked /go/ redirect; an
    // external-commerce partner's app deep link is tried first, then the web
    // fallback. Both trackers are fire-and-forget and never block opening.
    final tracker = ref.read(askodoxPartnerTrackerProvider);
    final deepLink = _match.deepLink?.trim();
    final primary = deepLink != null && deepLink.isNotEmpty
        ? deepLink
        : tracker.openUri(_match)?.toString();
    final fallback = _match.webFallbackUrl?.trim();
    if (primary == null || primary.isEmpty) return;
    tracker.track(_match, 'click');
    ref.read(universalMatchRepositoryProvider).recordExternalClick(
      match: _match,
      destinationUrl: primary,
    );
    var opened = false;
    try {
      final uri = Uri.tryParse(primary);
      opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && fallback != null && fallback.isNotEmpty && fallback != primary) {
      try {
        final fallbackUri = Uri.tryParse(fallback);
        opened = fallbackUri != null &&
            await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
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
    // Point-to-point distance (B13): labelled "straight line"; the road
    // distance is longer and comes from Maps directions.
    final distance = match.distanceKm == null ? null : askodoxDistanceLabel(match.distanceKm!, telugu: te);
    // A price only found in page text is labelled as such, never shown as
    // a confirmed price.
    // (Staff-catalog prices carry their MRP / discount and a checked date.)
    final price = askodoxPriceLabel(match, te: _te);
    final stock = askodoxStockLabel(match, te: _te);
    final checked = askodoxCheckedLabel(match, te: _te);
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
      // Compact rail card: small enough that a phone shows ~1.5 cards and
      // the conversation below stays on the same screen.
      width: compact ? askodoxCompactCardWidth : null,
      margin: compact ? const EdgeInsets.only(right: 8, bottom: 8) : const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The column label (LOCAL / ONLINE / DEALS ...); paid rows carry
        // their Sponsored / Promoted badge instead.
        if (widget.kind case final kind? when match.paidPlacementLabel == null)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 6),
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

        // Full cards keep the thumbnail above the text; compact cards put it
        // in the leading slot (one row: thumbnail + title/channel/duration).
        if (!compact && action == ChatResultAction.watchVideo &&
            match.imageUrl?.trim().isNotEmpty == true) ...[
          // Small "double stamp" thumbnail: the chat stays readable
          // (APK 1276: full-width thumbnails pushed the chat far down).
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: ValueKey('askodoxVideoThumb-${match.id}'),
              onTap: _openVideo,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(match.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF10204A))),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          size: 28, color: Colors.white),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (compact && action == ChatResultAction.watchVideo && match.imageUrl?.trim().isNotEmpty == true)
            GestureDetector(
              key: ValueKey('askodoxVideoThumb-${match.id}'),
              onTap: _openVideo,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 88,
                  height: 50,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(match.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF10204A))),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, size: 24, color: Colors.white)),
                  ]),
                ),
              ),
            )
          else
          SizedBox(
              key: _match.imageUrl?.trim().isNotEmpty == true ? ValueKey('askodoxCardImage-${match.id}') : null,
              // "Double stamp": two stamps side by side.
              width: _match.imageUrl?.trim().isNotEmpty == true ? (compact ? 60 : 72) : (compact ? 36 : 44),
              height: _match.imageUrl?.trim().isNotEmpty == true ? (compact ? 40 : 48) : (compact ? 36 : 44),
              child: _match.imageUrl?.trim().isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_resolvedImage(_match.imageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _sourceIcon()))
                  : _sourceIcon()),
          SizedBox(width: compact ? 8 : 10),
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
                        color: _ink, fontWeight: FontWeight.w900, fontSize: compact ? 13.5 : 16, height: 1.25)),
                if (match.subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  // A long page snippet never becomes a paragraph: the full
                  // text is behind Details.
                  Text(match.subtitle!,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _muted,
                          fontSize: compact ? 12 : null,
                          height: 1.3,
                          fontWeight: FontWeight.w500))
                ],
                if (match.why case final why?) ...[
                  const SizedBox(height: 4),
                  // Why this ASKODOX listing fits (or what it does not say)
                  // against the customer's own size / budget / distance.
                  Text(why,
                      key: ValueKey('askodoxFitWhy-${match.id}'),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: match.fitStatus == 'fits'
                              ? const Color(0xFF1B7F3B)
                              : (match.fitStatus == 'mismatch' ? const Color(0xFFB3261E) : const Color(0xFF8A5A00)))),
                ],
                SizedBox(height: compact ? 5 : 8),
                Wrap(spacing: compact ? 5 : 8, runSpacing: compact ? 4 : 6, children: [
                  ...() {
                    final facts = <Widget>[
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
                  if (stock != null) _meta(stock),
                  if (checked != null && !compact) _meta(checked),
                  if (match.salaryText?.trim().isNotEmpty == true)
                    _meta(te ? 'జీతం (పేజీ ప్రకారం): ${match.salaryText}' : 'Salary (as listed): ${match.salaryText}'),
                  if (match.offerTitle?.trim().isNotEmpty == true) _meta('🏷 ${match.offerTitle!.trim()}'),
                  if (match.benefits != null)
                    AskodoxBenefitsChip(match: match, lang: ref.watch(askodoxReplyLanguageProvider)),
                  if (match.locationLabel?.trim().isNotEmpty == true &&
                      !(compact && (match.subtitle ?? '').contains(match.locationLabel!.trim())))
                    _meta(match.locationLabel!),
                  // "Unknown" is not a fact worth a chip.
                  if (match.stockStatus == null &&
                      match.availability?.trim().isNotEmpty == true &&
                      match.availability!.trim().toLowerCase() != 'unknown')
                    _meta(match.availability!),
                    ];
                    // Compact rows keep the 3 most useful facts; the rest
                    // are one tap away in Details.
                    return compact ? facts.take(3).toList() : facts;
                  }(),
                ]),
              ])),
        ]),
        SizedBox(height: compact ? 6 : 12),
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
        // row on small screens instead of stacking full-width blocks. In a
        // rail the icon actions are tighter so they share one row.
        Theme(
          data: compact
              ? Theme.of(context).copyWith(
                  iconButtonTheme: IconButtonThemeData(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                )
              : Theme.of(context),
          child: Wrap(
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
                    ? (compact ? (te ? 'ప్లే' : 'Play') : (te ? 'వీడియో చూడండి' : 'Watch'))
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
            if (compact)
              IconButton(
                key: ValueKey('askodoxDetails-${match.id}'),
                tooltip: _l('details', 'వివరాలు', 'Details'),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  ref.read(askodoxPartnerTrackerProvider).track(match, 'card_view');
                  _showDetails(context);
                },
                icon: const Icon(Icons.info_outline_rounded, size: 20),
              )
            else
            TextButton.icon(
              key: ValueKey('askodoxDetails-${match.id}'),
              onPressed: () {
                ref.read(askodoxPartnerTrackerProvider).track(match, 'card_view');
                _showDetails(context);
              },
              style: _compactText,
              icon: const Icon(Icons.info_outline_rounded, size: 16),
              label: Text(_l('details', 'వివరాలు', 'Details')),
            ),
          ],
        )),
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
                  maxLines: compact ? 1 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
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
      if (m.price != null && m.priceSource == 'catalog')
        (te ? 'ధర' : 'Price', askodoxPriceLabel(m, te: te)!)
      else if (m.price != null)
        (te ? 'ధర' : 'Price', '₹${m.price!.toStringAsFixed(0)}${m.priceVerified ? '' : (te ? ' (పేజీలో, నిర్ధారించలేదు)' : ' (from the page, not verified)')}'),
      if (askodoxStockLabel(m, te: te) != null) (te ? 'స్టాక్' : 'Stock', askodoxStockLabel(m, te: te)!),
      if (askodoxCheckedLabel(m, te: te) != null) (te ? 'చివరి తనిఖీ' : 'Last checked', askodoxCheckedLabel(m, te: te)!),
      if (m.salaryText?.trim().isNotEmpty == true) (te ? 'జీతం' : 'Salary', m.salaryText!.trim()),
      if (m.distanceKm != null) (te ? 'దూరం' : 'Distance', askodoxDistanceLabel(m.distanceKm!, telugu: te)),
      if (m.locationLabel?.trim().isNotEmpty == true) (te ? 'ప్రదేశం' : 'Location', m.locationLabel!.trim()),
      if (m.stockStatus == null && m.availability?.trim().isNotEmpty == true)
        (te ? 'అందుబాటు' : 'Availability', m.availability!.trim()),
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
      padding: widget.compact
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFF6F7FA),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: _ink, fontSize: widget.compact ? 11 : 12, fontWeight: FontWeight.w700)));
}
