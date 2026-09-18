import '../../../services/in_app_assistant_service.dart';

class AskodoxSemanticDealInput {
  const AskodoxSemanticDealInput._();

  static String build(String original, InAppAssistantDecision decision) {
    final subject = _firstText(decision,
        const ['subject', 'product', 'item', 'service', 'role', 'skill']);
    final quantity = decision.entityNumber('quantity');
    final unit = _canonicalUnit(decision.entityText('unit'));
    final location = decision.entityText('location');
    final price = decision.entityNumber('price');

    final parts = <String>[];
    if (quantity != null) {
      parts.add(quantity == quantity.roundToDouble()
          ? quantity.toInt().toString()
          : quantity.toString());
    }
    if (unit != null) parts.add(unit);
    if (subject != null) parts.add(subject);
    if (location != null) {
      parts
        ..add('in')
        ..add(location);
    }
    if (price != null) {
      parts.add(
        '₹${price == price.roundToDouble() ? price.toInt() : price}',
      );
    }

    final payload = parts.isEmpty ? original.trim() : parts.join(' ').trim();
    final offering = _isOfferingSide(original, decision);
    return switch (decision.domain) {
      'STAFFING' => 'need staff $payload',
      'JOB_SEEKER' => 'need a job $payload',
      'SERVICE' =>
        offering ? 'offer service $payload' : 'need service $payload',
      'PARCEL' => 'send parcel $payload',
      'RIDE' => offering ? 'offer ride $payload' : 'need a ride $payload',
      'PRODUCT' ||
      'FOOD' =>
        offering ? 'i want to sell $payload' : 'i want to buy $payload',
      'APPOINTMENT' => 'book appointment $payload',
      _ => payload,
    };
  }

  static bool _isOfferingSide(
      String original, InAppAssistantDecision decision) {
    final action = decision.action.toLowerCase();
    if (action.isNotEmpty) {
      const offeringActionHints = [
        'sell',
        'list_product',
        'list_item',
        'list_my',
        'create_listing',
        'add_listing',
        'add_product',
        'publish_listing',
        'publish_product',
        'offer_product',
        'offer_service',
        'offer_ride',
        'provide_service',
        'become_seller',
        'register_seller',
      ];
      if (offeringActionHints.any(action.contains)) return true;
      const requestingActionHints = [
        'buy',
        'purchase',
        'order',
        'need_',
        'find_',
        'search_',
        'request_'
      ];
      if (requestingActionHints.any(action.contains)) return false;
    }

    final text = original.trim().toLowerCase();
    if (text.isEmpty) return false;
    const offeringPhrases = [
      'i want to sell',
      'want to sell',
      'i want sell',
      'i wanna sell',
      'looking to sell',
      'need to sell',
      'planning to sell',
      'for sale',
      'i am selling',
      'i m selling',
      'selling my',
      'sell my',
      'sell some',
      'list my',
      'listing my',
      'i have to sell',
      'i offer',
      'we offer',
      'i provide',
      'we provide',
      'offer service',
      'provide service',
      'service provider',
      'seats available',
      'ride available',
      'carpool available',
      'offer ride',
      'అమ్మాలి',
      'అమ్మకం',
      'అమ్ముతున్నాను',
      'అమ్మాలనుకుంటున్నాను',
      'నేను అమ్ముతున్నా',
    ];
    return offeringPhrases.any(text.contains);
  }

  static String? _firstText(
      InAppAssistantDecision decision, List<String> keys) {
    for (final key in keys) {
      final value = decision.entityText(key);
      if (value != null) return value;
    }
    return null;
  }

  static String? _canonicalUnit(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if ({
      'kg',
      'kgs',
      'kilogram',
      'kilograms',
      'kilo',
      'kilos',
      'కిలో',
      'కిలోలు',
      'కిలోల'
    }.contains(value)) return 'kg';
    if ({'g', 'gm', 'gram', 'grams', 'గ్రాము', 'గ్రాములు', 'గ్రాముల'}
        .contains(value)) return 'g';
    if ({
      'l',
      'lt',
      'litre',
      'litres',
      'liter',
      'liters',
      'లీటర్',
      'లీటర్లు',
      'లీటర్ల'
    }.contains(value)) return 'litre';
    if ({'ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters'}
        .contains(value)) return 'ml';
    if ({'piece', 'pieces', 'pc', 'pcs', 'పీస్', 'పీసులు', 'పీసుల'}
        .contains(value)) return 'pieces';
    return value;
  }
}
