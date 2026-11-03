import 'package:flutter_test/flutter_test.dart';
import 'package:podx/services/in_app_assistant_service.dart';

void main() {
  Map<String, dynamic> base(Object? appAction) => {
        'reply': 'POS లో bill వేయొచ్చు.',
        'domain': 'GENERAL',
        'transactional': false,
        'action': 'open_feature',
        'confidence': 0.9,
        'source': 'universal_ai',
        if (appAction != null) 'app_action': appAction,
      };

  test('a chat action from the backend becomes a button target', () {
    final d = InAppAssistantDecision.fromJson(
        base({'key': 'pos_bill', 'route': '/pos', 'label': 'Billing / POS'}));
    expect(d.appAction?.key, 'pos_bill');
    expect(d.appAction?.route, '/pos');
    expect(d.appAction?.label, 'Billing / POS');
  });

  test('older backends and empty actions add nothing', () {
    expect(InAppAssistantDecision.fromJson(base(null)).appAction, isNull);
    expect(InAppAssistantDecision.fromJson(base({'key': 'x', 'route': '/x', 'label': ''})).appAction, isNull);
  });

  test('only in-app routes are ever accepted', () {
    for (final route in ['https://evil.example', '//evil.example', '/../admin', 'pos', '/a b', '']) {
      expect(InAppAssistantDecision.fromJson(base({'key': 'k', 'route': route, 'label': 'L'})).appAction, isNull,
          reason: route);
    }
    expect(askodoxIsInternalRoute('/me/ai-credits'), isTrue);
  });
}
