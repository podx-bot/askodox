import '../domain/universal_deal.dart';

class UniversalDealContextResolver {
  const UniversalDealContextResolver();

  bool sameContext(UniversalDeal active, UniversalDeal incoming) {
    if (active.intent != incoming.intent) return false;
    final activeSubject = _normalize(active.subject);
    final incomingSubject = _normalize(incoming.subject);
    return activeSubject.isNotEmpty && activeSubject == incomingSubject;
  }

  UniversalDeal merge(UniversalDeal active, UniversalDeal incoming) {
    final dynamicFields = <String, Object?>{
      ...active.dynamicFields,
      ...incoming.dynamicFields,
    };
    return active.copyWith(
      rawText: incoming.rawText.trim().isNotEmpty ? incoming.rawText : active.rawText,
      partyA: incoming.partyA,
      partyB: incoming.partyB,
      subject: _text(incoming.subject) ?? active.subject,
      category: _text(incoming.category) ?? active.category,
      quantity: incoming.quantity ?? active.quantity,
      unit: _text(incoming.unit) ?? active.unit,
      price: incoming.price ?? active.price,
      priceBasis: _text(incoming.priceBasis) ?? active.priceBasis,
      quality: _text(incoming.quality) ?? active.quality,
      variant: _text(incoming.variant) ?? active.variant,
      size: _text(incoming.size) ?? active.size,
      weight: _text(incoming.weight) ?? active.weight,
      model: _text(incoming.model) ?? active.model,
      availability: _text(incoming.availability) ?? active.availability,
      fulfilment: _text(incoming.fulfilment) ?? active.fulfilment,
      location: incoming.location.isKnown ? incoming.location : active.location,
      timing: _text(incoming.timing) ?? active.timing,
      dynamicFields: dynamicFields,
      status: active.status,
    );
  }

  String _normalize(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    if (text.isEmpty) return '';
    return text
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _text(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
