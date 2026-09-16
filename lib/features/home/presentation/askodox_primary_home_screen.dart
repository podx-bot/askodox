import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../services/in_app_assistant_service.dart';
import '../../../services/real_product_match_service.dart';
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
  final _assistant = const InAppAssistantService();
  final _realMatches = const RealProductMatchService();
  final List<ConversationTurnRecord> _turns = [];
  List<UniversalMatch> _matches = const [];
  bool _active = false;
  bool _sending = false;

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
          final query = _lastGoodProductQuery ?? '';
          if (query.isNotEmpty) {
            matches = await _realMatches.search(query);
          }
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

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _active = true;
      _turns.add(ConversationTurnRecord(text: text, isUser: true));
    });
    _controller.clear();
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
          final query = _lastGoodProductQuery ?? '';
          if (query.isNotEmpty) {
            matches = await _realMatches.search(query)
              ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
          }
        }
      }
    } else {
      notifier.reset();
    }

    final reply =
        aiUsable ? decision!.reply.trim() : _fallbackAssistantReply(text, _te);

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
      return te
          ? 'అవును, అదే కొనసాగిద్దాం. మీరు ముందు “${_shortContext(previous)}” అన్నారు. ఇప్పుడు మొదటి ముఖ్యమైన పని ఏదో నిర్ణయించి దానిని పూర్తి చేద్దాం; అది పూర్తయ్యాక వెంటనే తర్వాత పనికి వెళ్దాం.'
          : 'Yes, let’s continue from there. You previously said “${_shortContext(previous)}”. Let’s decide the first priority now, finish it, and then move straight to the next task.';
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

  String _shortContext(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 72) return compact;
    return '${compact.substring(0, 69)}…';
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
                  onTap: () => context.push('/discover/voice'))),
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
        child: Row(children: [
          IconButton.filled(
              onPressed: () => context.push('/discover/voice'),
              style: IconButton.styleFrom(backgroundColor: _accent),
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
                  borderSide:
                      const BorderSide(color: Color(0xFFDDD9FF), width: 1.5)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide:
                      const BorderSide(color: Color(0xFF6C4DFF), width: 2)),
            ),
          )),
          IconButton(
              onPressed: () => context.push('/discover/image'),
              icon: const Icon(Icons.image_outlined, color: _ink)),
          IconButton.filled(
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(backgroundColor: _blue),
              icon:
                  const Icon(Icons.arrow_upward_rounded, color: Colors.white)),
        ]),
      );

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
          border: Border.all(color: color.withOpacity(0.3))),
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
          Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: const Color(0xFFF0EFFF),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF5B4BFF))),
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
                  if (match.score != null)
                    _meta('★ ${match.score!.toStringAsFixed(0)}%'),
                  if (distance != null) _meta(distance),
                  if (price != null) _meta(price),
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
                        ? (te ? 'ఆర్డర్ ప్లేస్ చేయబడింది' : 'Order placed')
                        : (te ? 'ఆర్డర్ చేయండి' : 'Place order'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _meta(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFF6F7FA),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              color: _ink, fontSize: 12, fontWeight: FontWeight.w700)));
}
