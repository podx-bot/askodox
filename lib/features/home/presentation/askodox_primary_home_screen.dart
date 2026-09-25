import 'dart:async';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../services/in_app_assistant_service.dart';
import '../../../services/document_intelligence_service.dart';
import '../../../services/real_product_match_service.dart';
import '../../../services/vision_api_service.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/video_analysis_service.dart';
import '../../../services/askodox_voice_service.dart';
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../location/application/location_controller.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../../selling/data/seller_listing_repository.dart';
import '../domain/home_request_routing.dart';
import '../domain/semantic_deal_input.dart';
import 'askodox_orb.dart';

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

class AskodoxPrimaryHomeScreen extends ConsumerStatefulWidget {
  const AskodoxPrimaryHomeScreen({super.key, AskodoxVoiceService? voiceService})
      : _voiceService = voiceService;

  /// Overridable only for tests, which inject a fake to avoid touching the
  /// real microphone/audio plugins. Production code always uses the
  /// default (null -> a real AskodoxVoiceService created in State).
  final AskodoxVoiceService? _voiceService;

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
  final _assistant = const InAppAssistantService();
  final _realMatches = const RealProductMatchService();
  late final _voiceService = widget._voiceService ?? AskodoxVoiceService();
  final List<ConversationTurnRecord> _turns = [];
  List<UniversalMatch> _matches = const [];
  bool _active = false;
  bool _sending = false;
  bool _voiceBusy = false;
  bool _recording = false;
  Timer? _recordingSafetyTimer;
  String? _activeRole;
  bool _showActiveRoleChip = false;
  Timer? _activeRoleChipTimer;
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

  /// Starts/stops ASKODOX's own in-app microphone recording (replaces the
  /// external Google speech-recognition popup). A first tap starts
  /// recording; ASKODOX -- not a platform silence timer -- decides when the
  /// user is done, so a second tap on the same button ends it. A generous
  /// safety cap still applies so an accidentally-open mic does not record
  /// forever, matching the 60s cap already used for video attachments.
  Future<void> _startVoice() async {
    if (_sending) return;
    if (_recording) {
      await _stopVoiceAndSend();
      return;
    }
    if (_voiceBusy) return;
    setState(() => _voiceBusy = true);
    try {
      await _voiceService.startListening();
      if (!mounted) return;
      _recordingSafetyTimer?.cancel();
      _recordingSafetyTimer = Timer(const Duration(seconds: 60), () {
        if (_recording) unawaited(_stopVoiceAndSend());
      });
      setState(() {
        _recording = true;
        _voiceBusy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _voiceBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'వాయిస్ ప్రారంభం కాలేదు. Microphone permission చూసి మళ్లీ ప్రయత్నించండి.'
              : 'Voice could not start. Check microphone permission and try again.'),
        ));
      }
    }
  }

  Future<void> _stopVoiceAndSend() async {
    _recordingSafetyTimer?.cancel();
    _recordingSafetyTimer = null;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _voiceBusy = true;
    });
    try {
      final transcript =
          await _voiceService.stopAndTranscribe(locale: _te ? 'te' : 'en');
      final text = transcript?.trim() ?? '';
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_te
                ? 'వాయిస్ వినిపించలేదు. మళ్లీ ప్రయత్నించండి.'
                : 'I could not hear that. Please try again.'),
          ));
        }
        return;
      }
      if (mounted) await _send(text, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'వాయిస్ ప్రాసెస్ కాలేదు. మళ్లీ ప్రయత్నించండి.'
              : 'Voice could not be processed. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
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
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final records = await _store.load();
    if (!mounted || records.isEmpty) return;
    final deal = ref.read(universalDealControllerProvider).deal;
    // Real seller-backed search replaces the old DemoNaturalMatchCatalog
    // sandbox data (which showed fake, sometimes domain-mismatched
    // placeholder businesses before the app had even finished asking for
    // required details). `readyToMatch` keeps the same "don't show anything
    // until the request is actually understood" gate the demo catalog used.
    var matches = const <UniversalMatch>[];
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
          matches = await _findUniversalMatches(deal);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _turns.addAll(records);
      _active = true;
      _matches = matches;
      _listingBanner = listingBanner;
      _listingBannerIsError = listingBannerIsError;
    });
    _scrollBottom();
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

  Future<List<UniversalMatch>> _findUniversalMatches(
    UniversalDeal deal,
  ) async {
    try {
      final result = await ref
          .read(universalMatchRepositoryProvider)
          .createAndMatch(deal);
      return result.matches;
    } catch (_) {
      // Keep the real seller catalog useful for signed-out commerce searches
      // while universal backend matching is unavailable.
      if (deal.intent != DealIntent.buy) return const [];
      final query = _lastGoodProductQuery ?? '';
      if (query.isEmpty) return const [];
      return _realMatches.search(query);
    }
  }

  Future<void> _send([String? preset, bool speakResponse = false]) async {
    final attachment = _attachment;
    var text = (preset ?? _controller.text).trim();
    if (_sending ||
        (text.isEmpty && attachment == null && _attachmentLabel == null)) {
      return;
    }
    text = text.isEmpty ? 'Please inspect this attachment and help me.' : text;

    if (attachment != null && !_isVideoAttachment(attachment)) {
      final analysis = await const VisionApiService().analyze(
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
      final facts = analysis['summary'] ?? analysis['text'] ?? '';
      if (facts.toString().trim().isNotEmpty) {
        text = '$text\nAttachment facts: ${facts.toString().trim()}';
      }
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
      _matches = const [];
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

    final decision = await _assistant.decide(
      message: text,
      locale: _te ? 'te' : 'en',
      history: history,
      location: knownLocationLabel,
    );
    final aiUsable = decision?.usable == true;
    _applyActiveRole(decision?.activeRole);
    final transactional = aiUsable
        ? decision!.transactional
        : AskodoxHomeRequestRouting.isTransactional(text);
    final routedText =
        aiUsable ? AskodoxSemanticDealInput.build(text, decision!) : text;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    List<UniversalMatch> matches = const [];
    String? listingBanner;
    var listingBannerIsError = false;

    if (transactional) {
      final session = ref.read(universalDealControllerProvider);
      final shouldStartFresh = AskodoxHomeRequestRouting.shouldStartFresh(
        session.deal?.rawText,
        routedText,
      );

      if (shouldStartFresh && session.deal != null) {
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
      final deal = ref.read(universalDealControllerProvider).deal;
      if (deal != null) {
        _trackSearchQuery(deal.subject ?? deal.category);
      }
      if (deal != null && deal.readyToMatch) {
        if (deal.intent == DealIntent.sell) {
          // A completed "sell" deal is a real listing to save, not a buyer
          // search -- see `_createRealListing`.
          final outcome = await _createRealListing(deal);
          listingBanner = outcome.$1;
          listingBannerIsError = outcome.$2;
        } else {
          matches = await _findUniversalMatches(deal)
            ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
        }
      }
    } else {
      notifier.reset();
    }

    final previous = _previousUserTurn();
    final isGeneralContinuation = !transactional &&
      previous != null &&
      (_isContinuation(text.toLowerCase()) ||
        _looksLikeGeneralFollowUp(text.toLowerCase()));
    final reply = aiUsable &&
        !(isGeneralContinuation &&
          askodoxIsGenericAssistantReply(decision!.reply))
      ? decision!.reply.trim()
      : isGeneralContinuation
        ? askodoxContinuationReply(
          previousUserTurn: previous,
          telugu: _te,
          )
        : _fallbackAssistantReply(
          text,
          _te,
          hasMatches: matches.isNotEmpty,
          );

    if (!mounted) return;
    setState(() {
      _matches = matches;
      _listingBanner = listingBanner;
      _listingBannerIsError = listingBannerIsError;
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      _sending = false;
    });
    await _store.save(_turns);
    _scrollBottom();
    if (speakResponse) await _speakReply(reply);
  }

  /// Plays the assistant's reply through the existing Sarvam Bulbul v3
  /// voice backend. Android system TTS is only a fallback for when Sarvam
  /// is unreachable, never the primary reply path.
  Future<void> _speakReply(String reply) async {
    await _voiceService.speak(reply, onSarvamUnavailable: () async {
      try {
        await const MethodChannel('com.askodox.app/device').invokeMethod<bool>(
          'speakReply',
          <String, Object?>{
            'text': reply,
            'languageCode': _te ? 'te' : 'en',
            'voicePreference': ref.read(appSettingsProvider).voicePreference.storageValue,
          },
        );
      } catch (_) {
        // The text reply remains available when no voice path is reachable.
      }
    });
  }

  /// Active Role = the current request's intent, re-derived by the backend
  /// on every message (see in_app_assistant.py's `_suggest_active_role`).
  /// A user's available capabilities never lock them into one role; this
  /// only updates the transient "X mode activated" chip and never blocks
  /// or delays the conversation.
  void _applyActiveRole(String? role) {
    final next = (role ?? '').trim();
    if (next.isEmpty || next == _activeRole) return;
    _activeRoleChipTimer?.cancel();
    setState(() {
      _activeRole = next;
      _showActiveRoleChip = true;
    });
    _activeRoleChipTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showActiveRoleChip = false);
    });
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

  String _fallbackAssistantReply(
    String text,
    bool te, {
    bool? hasMatches,
  }) {
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
      if (hasMatches == false) {
        return te
            ? 'ఈ అభ్యర్థనకు ప్రస్తుతం ధృవీకరించిన match దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను; సరైన అవకాశం లభిస్తే ASKODOX మీకు తెలియజేస్తుంది.'
            : 'I could not find a verified match for this request yet. I saved your need and ASKODOX will notify you when a suitable option becomes available.';
      }
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
          if (_showActiveRoleChip && _activeRole != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AskodoxActiveRoleChip(role: _activeRole!, te: te),
              ),
            ),
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
          for (final turn in _turns)
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
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text(te ? 'సంబంధిత ఎంపికలు' : 'Relevant matches',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: _ink))
            ]),
            const SizedBox(height: 10),
            ..._matches.map((match) => _MatchCard(match: match, te: te)),
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
        if (_attachmentLabel != null) _attachmentPreview(te),
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.graphic_eq_rounded, size: 16, color: Color(0xFFE53935)),
              const SizedBox(width: 6),
              Text(
                  te
                      ? 'వింటున్నాను… ఆపడానికి మళ్లీ నొక్కండి'
                      : 'Listening… tap again to stop',
                  style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
          ),
        Row(children: [
        IconButton.filled(
          onPressed: _voiceBusy && !_recording ? null : _startVoice,
          style: IconButton.styleFrom(
            backgroundColor: _recording ? const Color(0xFFE53935) : _accent,
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero),
          icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded,
              color: _recording ? Colors.white : _ink)),
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
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _recordingSafetyTimer?.cancel();
    _activeRoleChipTimer?.cancel();
    _voiceService.dispose();
    super.dispose();
  }
}

/// Non-blocking "X mode activated" chip shown for a few seconds when
/// ASKODOX's Active Role detection changes. Public (rather than a private
/// `_` class) so it can be unit-tested directly.
class AskodoxActiveRoleChip extends StatelessWidget {
  const AskodoxActiveRoleChip({super.key, required this.role, required this.te});
  final String role;
  final bool te;

  static const _labels = <String, (String emoji, String en, String te)>{
    'BUYER': ('🛒', 'Buyer mode activated', 'కొనుగోలుదారు మోడ్ యాక్టివేట్ అయింది'),
    'SELLER': ('🏪', 'Seller mode activated', 'విక్రేత మోడ్ యాక్టివేట్ అయింది'),
    'SERVICE_PROVIDER': (
      '🛠',
      'Service Provider mode activated',
      'సర్వీస్ ప్రొవైడర్ మోడ్ యాక్టివేట్ అయింది'
    ),
    'SERVICE_CUSTOMER': (
      '🔧',
      'Service request mode activated',
      'సర్వీస్ అవసరం మోడ్ యాక్టివేట్ అయింది'
    ),
    'WORKER': ('💼', 'Job Seeker mode activated', 'జాబ్ సీకర్ మోడ్ యాక్టివేట్ అయింది'),
    'EMPLOYER': ('🧑‍💼', 'Employer mode activated', 'ఎంప్లాయర్ మోడ్ యాక్టివేట్ అయింది'),
    'DELIVERY_PARTNER': (
      '🚚',
      'Delivery Partner mode activated',
      'డెలివరీ పార్ట్‌నర్ మోడ్ యాక్టివేట్ అయింది'
    ),
    'DELIVERY_CUSTOMER': (
      '📦',
      'Delivery request mode activated',
      'డెలివరీ అవసరం మోడ్ యాక్టివేట్ అయింది'
    ),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _labels[role];
    if (entry == null) return const SizedBox.shrink();
    final (emoji, en, teLabel) = entry;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(te ? teLabel : en,
            style: const TextStyle(
                color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
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

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({required this.match, required this.te});
  final UniversalMatch match;
  final bool te;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  bool _placing = false;
  bool _orderFailed = false;
  String? _orderStatusMessage;

  UniversalMatch get _match => widget.match;
  bool get _te => widget.te;

  Future<void> _openDestination() async {
    final raw = _match.destinationUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te ? 'లింక్ తెరవడం సాధ్యం కాలేదు.' : 'This destination could not be opened.'),
        ));
      }
    }
  }

  Future<void> _placeOrder() async {
    if (_placing) return;
    setState(() {
      _placing = true;
      _orderStatusMessage = null;
      _orderFailed = false;
    });
    OrderActionResult result;
    try {
      result = await ref
          .read(orderRepositoryProvider)
          .placeOrder(productId: _match.id);
    } catch (_) {
      result = OrderActionResult(
        success: false,
        message:
            _te ? 'ఆర్డర్ చేయడం సాధ్యం కాలేదు.' : 'Unable to place this order.',
      );
    }
    if (!mounted) return;
    setState(() {
      _placing = false;
      _orderFailed = !result.success;
      _orderStatusMessage = result.success
          ? (_te
              ? 'ఆర్డర్ పంపబడింది. విక్రేత అంగీకరించి తప్ప పక్కన పడే సహచరుడి తర్వాత మాత్రమే ఇది నిర్ధారిత డీల్ అవుతుంది.'
              : 'Order request sent. The seller must accept it before it becomes a confirmed deal.')
          : (result.message ??
              (_te
                  ? 'ఆర్డర్ చేయడం సాధ్యం కాలేదు.'
                  : 'Unable to place this order.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final te = _te;
    final distance = match.distanceKm == null
        ? null
        : '${match.distanceKm!.toStringAsFixed(1)} km';
    final price =
        match.price == null ? null : '₹${match.price!.toStringAsFixed(0)}';
    final placed = _orderStatusMessage != null && !_orderFailed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 64,
            height: 64,
            child: _match.imageUrl?.trim().isNotEmpty == true
              ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(_match.imageUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _sourceIcon()))
              : _sourceIcon()),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(match.title,
                    style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                if (match.subtitle != null) ...[
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
                  if (match.score != null)
                    _meta('★ ${match.score!.toStringAsFixed(0)}%'),
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
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_placing || placed) ? null : _placeOrder,
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
                        : (te ? 'అభ్యర్థన పంపండి' : 'Send request'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
        if (match.destinationUrl?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openDestination,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(_te ? 'వివరాలు చూడండి' : 'View details'),
            ),
          ),
          if (match.disclosure?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(match.disclosure!,
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ),
        ],
      ]),
    );
  }

  Widget _sourceIcon() => Container(
      decoration: BoxDecoration(
          color: const Color(0xFFF0EFFF), borderRadius: BorderRadius.circular(14)),
      child: Icon(
          _match.source.toLowerCase() == 'online'
              ? Icons.public_rounded
              : _match.source.toLowerCase() == 'nearby'
                  ? Icons.near_me_rounded
                  : Icons.storefront_rounded,
          color: const Color(0xFF5B4BFF)));

  String _sourceLabel(String source) => switch (source.toLowerCase()) {
        'online' => _te ? 'ఆన్‌లైన్' : 'Online',
        'nearby' => _te ? 'దగ్గరలో' : 'Nearby',
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
