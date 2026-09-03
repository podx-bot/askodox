import 'rfq_schema.dart';
import 'universal_deal.dart';

class RfqRequest {
  const RfqRequest({
    required this.intent,
    required this.subject,
    required this.category,
    required this.schemaId,
    required this.requirements,
  });

  final DealIntent intent;
  final String subject;
  final String category;
  final String schemaId;
  final Map<String, Object?> requirements;

  factory RfqRequest.fromDeal(UniversalDeal deal) {
    final schema = deal.rfqSchema;
    final requirements = <String, Object?>{
      'quantity': deal.quantity,
      'unit': deal.unit,
      'price': deal.price,
      'priceBasis': deal.priceBasis,
      'quality': deal.quality,
      'variant': deal.variant,
      'size': deal.size,
      'weight': deal.weight,
      'model': deal.model,
      'availability': deal.availability,
      'fulfilment': deal.fulfilment,
      'location': deal.location.label,
      'timing': deal.timing,
      ...deal.dynamicFields,
    }..removeWhere((_, value) => value == null || value.toString().trim().isEmpty);

    return RfqRequest(
      intent: deal.intent,
      subject: deal.subject?.trim().isNotEmpty == true ? deal.subject!.trim() : deal.rawText.trim(),
      category: deal.category?.trim().isNotEmpty == true ? deal.category!.trim() : 'general',
      schemaId: schema.id,
      requirements: Map<String, Object?>.unmodifiable(requirements),
    );
  }

  bool get isReady => subject.isNotEmpty && requirements.isNotEmpty;
}
