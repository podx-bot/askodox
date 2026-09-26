import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/deal_quote.dart';
import '../domain/deal_quote_collection.dart';
import '../domain/deal_quote_result.dart';
import '../domain/rfq_quote_pipeline.dart';
import '../domain/rfq_request.dart';
import '../domain/universal_deal.dart';
import 'universal_deal_brain.dart';
import 'universal_deal_context_resolver.dart';

class UniversalDealSession {
  const UniversalDealSession({
    this.deal,
    this.lastQuestion,
    this.completed = false,
    this.quoteCollection = const DealQuoteCollection(<DealQuote>[]),
  });

  final UniversalDeal? deal;
  final String? lastQuestion;
  final bool completed;
  final DealQuoteCollection quoteCollection;

  DealQuoteResult get quoteResult => DealQuoteResult.fromCollection(quoteCollection);

  RfqRequest? get rfqRequest {
    final current = deal;
    if (current == null || !completed) return null;
    return RfqRequest.fromDeal(current);
  }

  UniversalDealSession copyWith({
    UniversalDeal? deal,
    String? lastQuestion,
    bool? completed,
    DealQuoteCollection? quoteCollection,
  }) {
    return UniversalDealSession(
      deal: deal ?? this.deal,
      lastQuestion: lastQuestion,
      completed: completed ?? this.completed,
      quoteCollection: quoteCollection ?? this.quoteCollection,
    );
  }
}

final universalDealControllerProvider = StateNotifierProvider<UniversalDealController, UniversalDealSession>(
  (ref) => UniversalDealController(),
);

class UniversalDealController extends StateNotifier<UniversalDealSession> {
  UniversalDealController() : super(const UniversalDealSession()) {
    unawaited(_restore());
  }

  static const _storageKey = 'askodox.active_universal_deal.v1';
  final UniversalDealBrain _brain = const UniversalDealBrain();
  final UniversalDealContextResolver _contextResolver = const UniversalDealContextResolver();

  void start(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    final current = state.deal;
    if (current != null && current.missingForMatch.isNotEmpty) {
      answer(value);
      return;
    }
    final incoming = _brain.capture(value);
    if (current != null && _contextResolver.sameContext(current, incoming)) {
      _setSession(_sessionFor(_contextResolver.merge(current, incoming)));
      return;
    }
    _setSession(_sessionFor(incoming));
  }

  void answer(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    final current = state.deal;
    if (current == null) {
      _setSession(_sessionFor(_brain.capture(value)));
      return;
    }
    final missing = current.missingForMatch;
    if (missing.isEmpty) return;
    // Short answers often arrive out of question order ("curry cut" while
    // ASKODOX asked for quantity) or several at once ("1 kg skinless").
    // Fill every missing detail the answer clearly describes; only when it
    // describes none of them fall back to the next pending question.
    final semantic = _semanticAnswer(current, missing, value);
    if (semantic != null) {
      _setSession(_sessionFor(semantic));
      return;
    }
    final field = missing.first;
    final fields = Map<String, Object?>.from(current.dynamicFields);
    var next = current;
    switch (field) {
      case 'subject':
        next = current.copyWith(subject: value);
        break;
      case 'quantity':
        final parsed = _quantity(value);
        if (parsed != null) {
          next = current.copyWith(quantity: parsed.$1, unit: parsed.$2);
        } else {
          fields['quantityText'] = value;
          next = current.copyWith(quantity: 1, unit: value, dynamicFields: fields);
        }
        break;
      case 'quality':
        next = current.copyWith(quality: value);
        break;
      case 'variant':
        next = current.copyWith(variant: value);
        break;
      case 'size':
        next = current.copyWith(size: value);
        break;
      case 'weight':
        next = current.copyWith(weight: value);
        break;
      case 'model':
        next = current.copyWith(model: value);
        break;
      case 'availability':
        next = current.copyWith(availability: value);
        break;
      case 'freshness':
      case 'cut':
      case 'chickenPreference':
        fields[field] = value;
        next = current.copyWith(dynamicFields: fields);
        break;
      case 'fulfilment':
        next = current.copyWith(fulfilment: _fulfilment(value) ?? value);
        break;
      case 'location':
        next = current.copyWith(
          location: DealLocation(
            label: value,
            latitude: current.location.latitude,
            longitude: current.location.longitude,
            radiusKm: current.location.radiusKm,
          ),
        );
        break;
      case 'timing':
        next = current.copyWith(timing: value);
        break;
      case 'from':
      case 'to':
      case 'skill':
        fields[field] = value;
        next = current.copyWith(dynamicFields: fields);
        break;
      default:
        fields[field] = value;
        next = current.copyWith(dynamicFields: fields);
    }
    _setSession(_sessionFor(next));
  }

  void applySelectedLocation({
    required String label,
    required double latitude,
    required double longitude,
    double? radiusKm,
  }) {
    final current = state.deal;
    if (current == null || current.location.isKnown) return;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return;
    final cleanLabel = label.trim();
    final next = current.copyWith(
      location: DealLocation(
        label: cleanLabel.isEmpty ? null : cleanLabel,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      ),
    );
    _setSession(_sessionFor(next));
  }

  void ingestSellerQuote({
    required String sellerId,
    required String text,
    String currency = 'INR',
    double? trustScore,
  }) {
    final request = state.rfqRequest;
    if (request == null || sellerId.trim().isEmpty || text.trim().isEmpty) return;
    final pipeline = RfqQuotePipeline(
      request: request,
      collection: state.quoteCollection,
    ).ingestText(
      sellerId: sellerId.trim(),
      text: text.trim(),
      currency: currency,
      trustScore: trustScore,
    );
    _setSession(state.copyWith(quoteCollection: pipeline.collection));
  }

  void clearSellerQuotes() {
    if (state.quoteCollection.quotes.isEmpty) return;
    _setSession(state.copyWith(quoteCollection: const DealQuoteCollection(<DealQuote>[])));
  }

  void attachMedia({required String path, required String name, String kind = 'image'}) {
    final current = state.deal;
    if (current == null || path.trim().isEmpty) return;
    final fields = Map<String, Object?>.from(current.dynamicFields);
    fields['attachment'] = {
      'kind': kind,
      'name': name,
      'path': path,
      'analysisStatus': 'analyzing',
    };
    _setSession(_sessionFor(current.copyWith(dynamicFields: fields)));
  }

  void markVisionAnalysisFailed() {
    final current = state.deal;
    if (current == null) return;
    final fields = Map<String, Object?>.from(current.dynamicFields);
    final rawAttachment = fields['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, Object?>.from(rawAttachment.cast<String, Object?>());
    attachment['analysisStatus'] = 'failed';
    fields['attachment'] = attachment;
    _setSession(_sessionFor(current.copyWith(dynamicFields: fields)));
  }

  void mergeVisionAnalysis(Map<String, dynamic> analysis) {
    final current = state.deal;
    if (current == null || analysis.isEmpty) return;
    final fields = Map<String, Object?>.from(current.dynamicFields);
    fields['visionAnalysis'] = Map<String, Object?>.from(analysis);
    final rawAttachment = fields['attachment'];
    if (rawAttachment is Map) {
      final attachment = Map<String, Object?>.from(rawAttachment.cast<String, Object?>());
      attachment['analysisStatus'] = 'ready';
      fields['attachment'] = attachment;
    }
    final hints = analysis['deal_hints'];
    final hintMap = hints is Map ? hints.cast<Object?, Object?>() : const <Object?, Object?>{};
    String? hint(String key) {
      final value = hintMap[key]?.toString().trim();
      return value == null || value.isEmpty || value.toLowerCase() == 'null' ? null : value;
    }

    final detectedSubject = analysis['detected_subject']?.toString().trim();
    final categoryHint = analysis['category_hint']?.toString().trim();
    final subjectHint = hint('subject') ??
        ((detectedSubject == null || detectedSubject.isEmpty || detectedSubject.toLowerCase() == 'null')
            ? null
            : detectedSubject);
    final category = hint('category') ??
        ((categoryHint == null || categoryHint.isEmpty || categoryHint.toLowerCase() == 'null') ? null : categoryHint);
    final next = current.copyWith(
      subject: _missing(current.subject) ? subjectHint : current.subject,
      category: _missing(current.category) ? category : current.category,
      variant: _missing(current.variant) ? hint('variant') : current.variant,
      size: _missing(current.size) ? hint('size') : current.size,
      model: _missing(current.model) ? hint('model') : current.model,
      quality: _missing(current.quality) ? hint('quality') : current.quality,
      dynamicFields: fields,
    );
    _setSession(_sessionFor(next));
  }

  bool _missing(String? value) => value == null || value.trim().isEmpty;

  /// Replaces the subject after the user clarified an ambiguous need
  /// ("battery TV" → "portable rechargeable battery TV"). Everything else
  /// already collected is kept.
  void refineSubject(String subject) {
    final current = state.deal;
    final clean = subject.trim();
    if (current == null || clean.isEmpty) return;
    _setSession(_sessionFor(current.copyWith(subject: clean)));
  }

  /// JSON for any deal (History keeps one per result set for Retry).
  Map<String, Object?> encodeDeal(UniversalDeal deal) => _dealToJson(deal);

  UniversalDeal? decodeDeal(Map<String, dynamic> json) {
    try {
      return _dealFromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// JSON of the active deal (for History), or null when there is none.
  Map<String, Object?>? snapshot() {
    final deal = state.deal;
    return deal == null ? null : _dealToJson(deal);
  }

  /// Restores a deal captured by [snapshot] (History reopening). A null or
  /// unreadable snapshot clears the active deal.
  void restoreSnapshot(Map<String, dynamic>? json) {
    if (json == null) {
      reset();
      return;
    }
    try {
      _setSession(_sessionFor(_dealFromJson(json)));
    } catch (_) {
      reset();
    }
  }

  void reset() {
    state = const UniversalDealSession();
    unawaited(_clearPersisted());
  }

  UniversalDealSession _sessionFor(
    UniversalDeal deal, {
    DealQuoteCollection quoteCollection = const DealQuoteCollection(<DealQuote>[]),
  }) {
    final missing = deal.missingForMatch.firstOrNull;
    return UniversalDealSession(
      deal: deal,
      lastQuestion: _questionFor(deal, missing),
      completed: deal.readyToMatch,
      quoteCollection: quoteCollection,
    );
  }

  (double, String)? _quantity(String value) {
    final lower = value.toLowerCase();
    final match = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*(kg|kgs|g|gm|grams|litre|litres|liter|liters|l|ml|piece|pieces|pcs|bag|bags|pack|packs|packet|packets|carton|cartons|case|cases|unit|units|box|boxes|dozen|dozens|seat|seats|hour|hours|day|days)?\b',
    ).firstMatch(lower);
    final amount = double.tryParse(match?.group(1) ?? '');
    if (amount == null) return null;
    return (amount, match?.group(2) ?? 'unit');
  }

  static const _cutWords = [
    'curry', 'biryani', 'boneless', 'bone less', 'with bone', 'whole bird',
    'whole chicken', 'small pieces', 'big pieces', 'medium pieces', 'keema',
    'kheema', 'mince', 'breast', 'leg piece', 'drumstick', 'wings', 'fry cut',
    'cut', 'కర్రీ', 'బిర్యానీ', 'బోన్‌లెస్', 'బోన్లెస్', 'ముక్కలు', 'కీమా',
  ];
  static const _preferenceWords = [
    'skinless', 'skin less', 'with skin', 'without skin', 'no skin', 'skin',
    'liver', 'gizzard', 'no preference', 'స్కిన్', 'లివర్',
  ];
  static const _freshnessWords = [
    'fresh', 'live', 'chilled', 'frozen', 'తాజా', 'ఫ్రెష్',
  ];

  // ASCII keywords match whole words only ("live" must not match inside
  // "delivery"); Telugu keywords match as substrings (suffixes attach).
  bool _mentions(String lower, List<String> words) => words.any((word) {
        if (!RegExp(r'^[a-z ]+$').hasMatch(word)) return lower.contains(word);
        return RegExp('(^|[^a-z])${RegExp.escape(word)}(\$|[^a-z])')
            .hasMatch(lower);
      });

  UniversalDeal? _semanticAnswer(
    UniversalDeal current,
    List<String> missing,
    String value,
  ) {
    final lower = value.toLowerCase();
    // "live-cut" names freshness, not the cut style.
    final cutText = lower.replaceAll(RegExp(r'live[\s-]?cut'), ' ');
    final fields = Map<String, Object?>.from(current.dynamicFields);
    var next = current;
    var filled = false;
    for (final field in missing) {
      switch (field) {
        case 'quantity':
          final parsed = _quantity(_normalizeTeluguUnits(lower));
          if (parsed != null && parsed.$2 != 'unit') {
            next = next.copyWith(quantity: parsed.$1, unit: parsed.$2);
            filled = true;
          }
        case 'cut':
          if (_mentions(cutText, _cutWords)) {
            fields['cut'] = value;
            filled = true;
          }
        case 'chickenPreference':
          if (_mentions(lower, _preferenceWords)) {
            fields['chickenPreference'] = value;
            filled = true;
          }
        case 'freshness':
          if (_mentions(lower, _freshnessWords)) {
            fields['freshness'] = value;
            filled = true;
          }
        case 'size':
          final size = UniversalDealBrain.screenSizeIn(lower);
          if (size != null) {
            next = next.copyWith(size: size);
            filled = true;
          }
        case 'fulfilment':
          final mode = _fulfilment(value);
          if (mode != null) {
            next = next.copyWith(fulfilment: mode);
            filled = true;
          }
      }
    }
    if (!filled) return null;
    return next.copyWith(dynamicFields: fields);
  }

  String _normalizeTeluguUnits(String value) => value
      .replaceAll('కిలోలు', ' kg')
      .replaceAll('కిలో', ' kg')
      .replaceAll('కేజీ', ' kg')
      .replaceAll('గ్రాములు', ' g');

  String? _fulfilment(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('delivery') || lower.contains('డెలివరీ')) return 'delivery';
    if (lower.contains('pickup') || lower.contains('pick up') || lower.contains('పికప్')) return 'pickup';
    if (lower.contains('online')) return 'online';
    return null;
  }

  void _setSession(UniversalDealSession next) {
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final dealJson = decoded['deal'];
      if (dealJson is! Map<String, dynamic>) return;
      final deal = _dealFromJson(dealJson);
      final quotes = _quotesFromJson(decoded['quotes']);
      if (!mounted) return;
      state = _sessionFor(deal, quoteCollection: DealQuoteCollection(quotes));
    } catch (_) {
      await _clearPersisted();
    }
  }

  Future<void> _persist(UniversalDealSession session) async {
    final deal = session.deal;
    if (deal == null) return _clearPersisted();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'deal': _dealToJson(deal),
          'quotes': session.quoteCollection.quotes.map(_quoteToJson).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  Map<String, Object?> _dealToJson(UniversalDeal d) => {
        'rawText': d.rawText,
        'intent': d.intent.name,
        'partyA': _partyToJson(d.partyA),
        'partyB': _partyToJson(d.partyB),
        'subject': d.subject,
        'category': d.category,
        'quantity': d.quantity,
        'unit': d.unit,
        'price': d.price,
        'priceBasis': d.priceBasis,
        'quality': d.quality,
        'variant': d.variant,
        'size': d.size,
        'weight': d.weight,
        'model': d.model,
        'availability': d.availability,
        'fulfilment': d.fulfilment,
        'location': {
          'label': d.location.label,
          'latitude': d.location.latitude,
          'longitude': d.location.longitude,
          'radiusKm': d.location.radiusKm,
        },
        'timing': d.timing,
        'dynamicFields': d.dynamicFields,
        'status': d.status.name,
      };

  Map<String, Object?> _partyToJson(DealPartyRequirement p) => {
        'side': p.side.name,
        'role': p.role,
        'action': p.action,
      };

  Map<String, Object?> _quoteToJson(DealQuote q) => {
        'sellerId': q.sellerId,
        'amount': q.amount,
        'currency': q.currency,
        'kind': q.kind.name,
        'priceBasis': q.priceBasis,
        'tax': q.tax,
        'deliveryFee': q.deliveryFee,
        'leadTimeHours': q.leadTimeHours,
        'validUntil': q.validUntil?.toIso8601String(),
        'paymentTerms': q.paymentTerms,
        'warrantyOrReturn': q.warrantyOrReturn,
        'trustScore': q.trustScore,
        'notes': q.notes,
        'dynamicFields': q.dynamicFields,
      };

  List<DealQuote> _quotesFromJson(Object? raw) {
    if (raw is! List) return const <DealQuote>[];
    final result = <DealQuote>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final j = item.cast<String, dynamic>();
      final sellerId = j['sellerId']?.toString().trim() ?? '';
      final amount = (j['amount'] as num?)?.toDouble();
      if (sellerId.isEmpty || amount == null) continue;
      result.add(
        DealQuote(
          sellerId: sellerId,
          amount: amount,
          currency: j['currency']?.toString() ?? 'INR',
          kind: _enumByName(QuoteKind.values, j['kind'], QuoteKind.totalPrice),
          priceBasis: j['priceBasis']?.toString(),
          tax: (j['tax'] as num?)?.toDouble(),
          deliveryFee: (j['deliveryFee'] as num?)?.toDouble(),
          leadTimeHours: (j['leadTimeHours'] as num?)?.toDouble(),
          validUntil: DateTime.tryParse(j['validUntil']?.toString() ?? ''),
          paymentTerms: j['paymentTerms']?.toString(),
          warrantyOrReturn: j['warrantyOrReturn']?.toString(),
          trustScore: (j['trustScore'] as num?)?.toDouble(),
          notes: j['notes']?.toString(),
          dynamicFields: (j['dynamicFields'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
        ),
      );
    }
    return List<DealQuote>.unmodifiable(result);
  }

  UniversalDeal _dealFromJson(Map<String, dynamic> j) {
    final location = (j['location'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return UniversalDeal(
      rawText: j['rawText']?.toString() ?? '',
      intent: _enumByName(DealIntent.values, j['intent'], DealIntent.other),
      partyA: _partyFromJson((j['partyA'] as Map?)?.cast<String, dynamic>()),
      partyB: _partyFromJson((j['partyB'] as Map?)?.cast<String, dynamic>()),
      subject: j['subject']?.toString(),
      category: j['category']?.toString(),
      quantity: (j['quantity'] as num?)?.toDouble(),
      unit: j['unit']?.toString(),
      price: (j['price'] as num?)?.toDouble(),
      priceBasis: j['priceBasis']?.toString(),
      quality: j['quality']?.toString(),
      variant: j['variant']?.toString(),
      size: j['size']?.toString(),
      weight: j['weight']?.toString(),
      model: j['model']?.toString(),
      availability: j['availability']?.toString(),
      fulfilment: j['fulfilment']?.toString(),
      location: DealLocation(
        label: location['label']?.toString(),
        latitude: (location['latitude'] as num?)?.toDouble(),
        longitude: (location['longitude'] as num?)?.toDouble(),
        radiusKm: (location['radiusKm'] as num?)?.toDouble(),
      ),
      timing: j['timing']?.toString(),
      dynamicFields: (j['dynamicFields'] as Map?)?.cast<String, Object?>() ?? const {},
      status: _enumByName(DealStatus.values, j['status'], DealStatus.collecting),
    );
  }

  DealPartyRequirement _partyFromJson(Map<String, dynamic>? j) => DealPartyRequirement(
        side: _enumByName(DealSide.values, j?['side'], DealSide.demand),
        role: j?['role']?.toString() ?? 'user',
        action: j?['action']?.toString() ?? 'match',
      );

  T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
    final name = raw?.toString();
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  String? _questionFor(UniversalDeal deal, String? field) {
    if (field == null) return null;
    final categoryQuestion = deal.productSchema.questions[field];
    if (categoryQuestion != null && categoryQuestion.trim().isNotEmpty) return categoryQuestion;
    return switch (field) {
      'subject' => 'What exactly do you need or offer?',
      'quantity' => 'How much do you need?',
      'freshness' => 'Do you want fresh/live-cut or chilled?',
      'cut' => 'How should it be cut?',
      'chickenPreference' => 'Any preference for skin, portion, liver or gizzard? You can also say no preference.',
      'fulfilment' => 'Do you want pickup or delivery?',
      'location' => 'Where should ASKODOX find the match?',
      'timing' => 'When do you need this?',
      'from' => 'Where does it start from?',
      'to' => 'Where should it go to?',
      'skill' => 'What skill or work is required?',
      _ => 'Please tell me the missing $field detail.',
    };
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}