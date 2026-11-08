import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/reply_suggestions.dart';
import 'package:podx/services/in_app_assistant_service.dart';

void main() {
  Map<String, dynamic> base(Object? suggestions) => {
        'reply': 'ఏ budget లో చూడాలి?',
        'domain': 'PRODUCT',
        'transactional': false,
        'action': 'ask_detail',
        'confidence': 0.9,
        'source': 'universal_ai',
        if (suggestions != null) 'suggestions': suggestions,
      };

  test('chips from the backend are parsed in order', () {
    final d = InAppAssistantDecision.fromJson(base(['₹10k లోపు', '₹15–20k', '₹25k+']));
    expect(d.suggestions, ['₹10k లోపు', '₹15–20k', '₹25k+']);
  });

  test('older backends and bad payloads add no chips', () {
    expect(InAppAssistantDecision.fromJson(base(null)).suggestions, isEmpty);
    expect(InAppAssistantDecision.fromJson(base('yes')).suggestions, isEmpty);
    expect(InAppAssistantDecision.fromJson(base([' ', ''])).suggestions, isEmpty);
  });

  test('never more than five chips from the payload', () {
    final d = InAppAssistantDecision.fromJson(base([for (var i = 0; i < 8; i++) 'Option $i']));
    expect(d.suggestions.length, 5);
  });

  group('askodoxSuggestionChips', () {
    test('keeps short distinct chips, drops links and long text', () {
      expect(
        askodoxSuggestionChips(['Compare top 2', 'compare top 2', 'www.spam.example', 'a' * 41, ' Nearby  shop ']),
        ['Compare top 2', 'Nearby shop'],
      );
    });

    test('one chip alone is not worth drawing', () {
      expect(askodoxSuggestionChips(['Yes']), isEmpty);
      expect(askodoxSuggestionChips(const []), isEmpty);
    });

    test('works for any language', () {
      expect(askodoxSuggestionChips(['రేపు ఉదయం', 'ఈ రోజు సాయంత్రం']), ['రేపు ఉదయం', 'ఈ రోజు సాయంత్రం']);
      expect(askodoxSuggestionChips(['कल सुबह', 'आज शाम']), ['कल सुबह', 'आज शाम']);
    });
  });
}
