import 'dart:async';
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
import '../../catalog/application/conversation_turn_store.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../../location/application/location_controller.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../../selling/data/seller_listing_repository.dart';
import '../domain/chat_result_policy.dart';
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

// Injectable so widget tests can drive the whole chat → matching → results
// flow without the network. Production uses the same default instances the
// screen always constructed directly.
final askodoxAssistantServiceProvider =
    Provider<InAppAssistantService>((ref) => const InAppAssistantService());
final askodoxRealProductMatchServiceProvider =
    Provider<RealProductMatchService>((ref) => const RealProductMatchService());
final askodoxVisionServiceProvider =
    Provider<VisionApiService>((ref) => const VisionApiService());

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
  bool _active = false;
  bool _sending = false;
  bool _voiceBusy = false;
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

  Future<void> _startVoice() async {
    if (_voiceBusy || _sending) return;
    setState(() => _voiceBusy = true);
    try {
      final spoken = await const MethodChannel('com.askodox.app/device')
          .invokeMethod<String>('startVoiceSearch', <String, Object?>{
        'languageCode': _te ? 'te' : 'en',
      });
      final text = spoken?.trim() ?? '';
      if (text.isNotEmpty && mounted) await _send(text, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te
              ? 'వాయిస్ ప్రారంభం కాలేదు. Microphone permission చూసి మళ్లీ ప్రయత్నించండి.'
              : 'Voice could not start. Check microphone permission and try again.'),
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
      return AskodoxChatResults(dealId: result.dealId, matches: matches);
    } on DealNeedsDetailsException catch (error) {
      return AskodoxChatResults(missingFields: error.missingFields);
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
      // No genuine local match reachable: clearly fall back to online
      // options (plain search links, never invented sellers).
      final online = local.isEmpty
          ? askodoxOfflineFallbackResults(query,
              includeVideos: askodoxIntentWantsVideos(deal.intent))
          : const <UniversalMatch>[];
      return AskodoxChatResults(
        matches: [...local, ...online],
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
    final decision = await ref.read(askodoxAssistantServiceProvider).decide(
      message: text,
      locale: _te ? 'te' : 'en',
      history: history,
      location: knownLocationLabel,
    );
    final aiUsable = decision?.usable == true;
    final transactional = aiUsable
        ? decision!.transactional
        : AskodoxHomeRequestRouting.isTransactional(text);
    final routedText =
        aiUsable ? AskodoxSemanticDealInput.build(text, decision!) : text;
    final notifier = ref.read(universalDealControllerProvider.notifier);
    AskodoxChatResults? results;
    UniversalDeal? matchedDeal;
    String? detailQuestion;
    String? roleNotice;
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
      final dealSession = ref.read(universalDealControllerProvider);
      final deal = dealSession.deal;
      if (deal != null) {
        _trackSearchQuery(deal.subject ?? deal.category);
        // Roles follow the user's activity: announce a switch (e.g. buyer →
        // seller) inside the chat, never silently answer in the old role.
        roleNotice = askodoxRoleSwitchNotice(
          previous: _lastIntent,
          current: deal.intent,
          telugu: _te,
        );
        _lastIntent = deal.intent;
        if (!deal.readyToMatch) detailQuestion = dealSession.lastQuestion;
      }
      if (deal != null && deal.readyToMatch) {
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
        : detailQuestion != null && detailQuestion.trim().isNotEmpty
          ? askodoxDetailQuestionReply(detailQuestion, telugu: _te)
          : results != null
            ? askodoxResultsReply(results, telugu: _te)
            : _fallbackAssistantReply(text, _te);

    if (!mounted) return;
    setState(() {
      if (roleNotice != null) _roleNoticeByTurn[userTurnIndex] = roleNotice;
      _listingBanner = listingBanner;
      _listingBannerIsError = listingBannerIsError;
      _turns.add(ConversationTurnRecord(text: reply, isUser: false));
      final assistantIndex = _turns.length - 1;
      if (results != null && !results.isEmpty) {
        _resultsByTurn[assistantIndex] = results;
        if (matchedDeal != null) _dealByTurn[assistantIndex] = matchedDeal;
      }
      _sending = false;
    });
    await _store.save(_turns);
    _scrollBottom();
    if (speakResponse) await _speakReply(reply);
  }

  Future<void> _speakReply(String reply) async {
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
      // The text reply remains available when device TTS is unavailable.
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
            if (_resultsByTurn[index] case final results?)
              _ChatResultsView(
                key: ValueKey('askodoxChatResults-$index'),
                results: results,
                te: te,
                retrying: _sending,
                onRetry: _dealByTurn.containsKey(index)
                    ? () => _retryMatching(index)
                    : null,
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
        if (_attachmentLabel != null) _attachmentPreview(te),
        Row(children: [
        IconButton.filled(
          onPressed: _startVoice,
          style: IconButton.styleFrom(
            backgroundColor: _accent,
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero),
          icon: const Icon(Icons.mic_rounded, color: _ink)),
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
class _ChatResultsView extends StatelessWidget {
  const _ChatResultsView({
    super.key,
    required this.results,
    required this.te,
    required this.retrying,
    this.onRetry,
  });

  final AskodoxChatResults results;
  final bool te;
  final bool retrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final local = results.local;
    final online = results.online;
    final videos = results.videos;
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
        if (local.isNotEmpty) ...[
          _heading(te ? 'దగ్గరలోని ఎంపికలు' : 'Local matches',
              Icons.near_me_rounded),
          for (final match in local)
            _MatchCard(match: match, dealId: results.dealId, te: te),
        ],
        if (online.isNotEmpty) ...[
          _heading(
              local.isEmpty
                  ? (te
                      ? 'స్థానిక match లేదు -- ఆన్‌లైన్ ఎంపికలు'
                      : 'No local match yet -- online options')
                  : (te ? 'ఆన్‌లైన్ ఎంపికలు' : 'Online options'),
              Icons.public_rounded),
          for (final match in online)
            _MatchCard(match: match, dealId: results.dealId, te: te),
        ],
        if (videos.isNotEmpty) ...[
          _heading(te ? 'వీడియోలు & రివ్యూలు' : 'Videos & reviews',
              Icons.play_circle_outline_rounded),
          for (final match in videos)
            _MatchCard(match: match, dealId: results.dealId, te: te),
        ],
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

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({required this.match, required this.te, this.dealId});
  final UniversalMatch match;
  final String? dealId;
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
  ChatResultAction get _action => chatResultActionFor(_match);

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
    final placed = _orderStatusMessage != null && !_orderFailed;
    final requestable = action == ChatResultAction.connect ||
        action == ChatResultAction.sendRequest;
    return Container(
      key: ValueKey('askodoxResultCard-${match.source}-${match.id}'),
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
        if (requestable) ...[
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
        if (match.destinationUrl?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openDestination,
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
