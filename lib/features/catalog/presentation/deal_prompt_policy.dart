import '../../deal_brain/domain/universal_deal.dart';

class DealPromptPolicy {
  const DealPromptPolicy._();

  static String questionFor({
    required UniversalDeal deal,
    required String? field,
    required bool telugu,
  }) {
    final chicken = deal.isChickenRequest;

    if (telugu) {
      return switch (field) {
        'subject' => _subjectQuestionTe(deal.intent),
        'quantity' => chicken
            ? 'సరే 👍 ఎంత చికెన్ కావాలి? ఉదాహరణకు 1 kg, 2 kg అని చెప్పండి.'
            : 'ఎంత quantity కావాలి? సంఖ్యతో పాటు unit కూడా చెప్పండి.',
        'freshness' => chicken
            ? 'ఫ్రెష్ / live-cut కావాలా, లేక chilled కూడా సరేనా?'
            : 'మీకు కావాల్సిన quality లేదా type ఏది?',
        'cut' => chicken
            ? 'ఎలా కట్ చేయాలి? కర్రీ ముక్కలా, బిర్యానీ ముక్కలా, whole chickenలా?'
            : 'ఏ variant లేదా format కావాలి?',
        'chickenPreference' => chicken
            ? 'ఇంకేమైనా preference ఉందా? Skinless/with skin, front/back/mixed, breast/leg/wings, liver/gizzard — ఏది కావాలో చెప్పండి. ఏమీ లేకపోతే “ఏదైనా సరే” అనండి.'
            : 'ఇంకేమైనా preference ఉందా? లేకపోతే “ఏదైనా సరే” అనండి.',
        'fulfilment' => 'మీరు తీసుకుంటారా, లేక delivery కావాలా?',
        'location' => 'ఏ ప్రాంతంలో చూడాలి? మీ ప్రస్తుత స్థానం ఉపయోగించాలంటే “నా ప్రస్తుత స్థానం” అనండి.',
        'timing' => 'ఎప్పుడు కావాలి?',
        'from' => 'ఎక్కడి నుంచి బయలుదేరాలి?',
        'to' => 'ఎక్కడికి వెళ్లాలి?',
        'skill' => _skillQuestionTe(deal.intent),
        _ => 'ఇంకో చిన్న వివరము చెప్తారా?',
      };
    }

    return switch (field) {
      'subject' => _subjectQuestionEn(deal.intent),
      'quantity' => chicken
          ? 'How much chicken do you need? For example, 1 kg or 2 kg.'
          : 'How much do you need? Include the quantity and unit.',
      'freshness' => chicken
          ? 'Do you want fresh/live-cut, or is chilled okay too?'
          : 'What quality or type do you prefer?',
      'cut' => chicken
          ? 'How should it be cut: curry cut, biryani cut, or whole?'
          : 'Which variant or format do you need?',
      'chickenPreference' => chicken
          ? 'Any preference for skin, portion, breast/leg/wings, liver or gizzard? You can also say “no preference”.'
          : 'Any other preference? You can also say “no preference”.',
      'fulfilment' => 'Would you like pickup or delivery?',
      'location' => 'Which area should I search?',
      'timing' => 'When do you need it?',
      'from' => 'Where should the trip start?',
      'to' => 'Where should it go?',
      'skill' => _skillQuestionEn(deal.intent),
      _ => 'Tell me one more small detail.',
    };
  }

  static List<String> suggestionsFor({
    required UniversalDeal deal,
    required String? field,
    required bool telugu,
  }) {
    final chicken = deal.isChickenRequest;

    if (telugu) {
      return switch (field) {
        'quantity' => chicken ? ['1 kg', '2 kg', '3 kg'] : const [],
        'freshness' => chicken ? ['ఫ్రెష్ / live-cut', 'Chilled కూడా సరే'] : const [],
        'cut' => chicken ? ['కర్రీ కట్', 'బిర్యానీ కట్', 'Whole chicken'] : const [],
        'chickenPreference' => chicken
            ? ['Skinless • mixed pieces', 'Leg pieces', 'Liver కూడా కావాలి', 'ఏదైనా సరే']
            : ['ఏదైనా సరే'],
        'fulfilment' => ['డెలివరీ కావాలి', 'పికప్ చేస్తాను'],
        'location' => ['నా ప్రస్తుత స్థానం'],
        'timing' => ['ఇప్పుడు', 'ఈరోజు', 'రేపు'],
        _ => const [],
      };
    }

    return switch (field) {
      'quantity' => chicken ? ['1 kg', '2 kg', '3 kg'] : const [],
      'freshness' => chicken ? ['Fresh / live-cut', 'Chilled is okay'] : const [],
      'cut' => chicken ? ['Curry cut', 'Biryani cut', 'Whole chicken'] : const [],
      'chickenPreference' => chicken
          ? ['Skinless • mixed', 'Leg pieces', 'Add liver', 'No preference']
          : ['No preference'],
      'fulfilment' => ['Delivery', 'Pickup'],
      'location' => ['My current location'],
      'timing' => ['Now', 'Today', 'Tomorrow'],
      _ => const [],
    };
  }

  static String _subjectQuestionTe(DealIntent intent) => switch (intent) {
        DealIntent.needService => 'ఏ సర్వీస్ కావాలి?',
        DealIntent.offerService => 'మీరు ఏ సర్వీస్ అందిస్తారు?',
        DealIntent.needWorker => 'ఏ పని కోసం వ్యక్తి కావాలి?',
        DealIntent.seekWork => 'మీరు ఏ పని కోసం చూస్తున్నారు?',
        DealIntent.bookAppointment => 'ఏ appointment లేదా specialist కావాలి?',
        DealIntent.offerAppointment => 'మీరు ఏ appointment/service అందిస్తారు?',
        DealIntent.sell => 'మీరు ఖచ్చితంగా ఏది అమ్మాలనుకుంటున్నారు?',
        _ => 'సరే. మీకు ఖచ్చితంగా ఏది కావాలి?',
      };

  static String _subjectQuestionEn(DealIntent intent) => switch (intent) {
        DealIntent.needService => 'What service do you need?',
        DealIntent.offerService => 'What service do you offer?',
        DealIntent.needWorker => 'What work do you need someone for?',
        DealIntent.seekWork => 'What kind of work are you looking for?',
        DealIntent.bookAppointment => 'What appointment or specialist do you need?',
        DealIntent.offerAppointment => 'What appointment or service do you offer?',
        DealIntent.sell => 'What exactly do you want to sell?',
        _ => 'Sure. What exactly do you need?',
      };

  static String _skillQuestionTe(DealIntent intent) => switch (intent) {
        DealIntent.seekWork => 'మీరు ఏ పని లేదా skillలో ఉద్యోగం చూస్తున్నారు?',
        DealIntent.needWorker => 'ఏ పని లేదా skill ఉన్న వ్యక్తి కావాలి?',
        _ => 'ఏ పని లేదా skill కావాలి?',
      };

  static String _skillQuestionEn(DealIntent intent) => switch (intent) {
        DealIntent.seekWork => 'What job or skill are you looking for?',
        DealIntent.needWorker => 'What work or skill should the person have?',
        _ => 'What work or skill do you need?',
      };
}
