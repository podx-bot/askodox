import '../../../services/in_app_assistant_service.dart';

class AskodoxSemanticDealInput {
  const AskodoxSemanticDealInput._();

  static String build(String original, InAppAssistantDecision decision) {
    final subject = _firstText(decision, const ['subject', 'product', 'item', 'service', 'role', 'skill']);
    final quantity = decision.entityNumber('quantity');
    final unit = _canonicalUnit(decision.entityText('unit'));
    final location = decision.entityText('location');

    final parts = <String>[];
    if (quantity != null) {
      parts.add(quantity == quantity.roundToDouble() ? quantity.toInt().toString() : quantity.toString());
    }
    if (unit != null) parts.add(unit);
    if (subject != null) parts.add(subject);
    if (location != null) {
      parts
        ..add('in')
        ..add(location);
    }

    final payload = parts.isEmpty ? original.trim() : parts.join(' ').trim();
    return switch (decision.domain) {
      'STAFFING' => 'need staff $payload',
      'JOB_SEEKER' => 'need a job $payload',
      'SERVICE' => 'need service $payload',
      'PARCEL' => 'send parcel $payload',
      'RIDE' => 'need a ride $payload',
      'PRODUCT' || 'FOOD' => 'i want to buy $payload',
      'APPOINTMENT' => 'book appointment $payload',
      _ => payload,
    };
  }

  static String? _firstText(InAppAssistantDecision decision, List<String> keys) {
    for (final key in keys) {
      final value = decision.entityText(key);
      if (value != null) return value;
    }
    return null;
  }

  static String? _canonicalUnit(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if ({'kg', 'kgs', 'kilogram', 'kilograms', 'kilo', 'kilos', 'కిలో', 'కిలోలు', 'కిలోల'}.contains(value)) return 'kg';
    if ({'g', 'gm', 'gram', 'grams', 'గ్రాము', 'గ్రాములు', 'గ్రాముల'}.contains(value)) return 'g';
    if ({'l', 'lt', 'litre', 'litres', 'liter', 'liters', 'లీటర్', 'లీటర్లు', 'లీటర్ల'}.contains(value)) return 'litre';
    if ({'ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters'}.contains(value)) return 'ml';
    if ({'piece', 'pieces', 'pc', 'pcs', 'పీస్', 'పీసులు', 'పీసుల'}.contains(value)) return 'pieces';
    return value;
  }
}
