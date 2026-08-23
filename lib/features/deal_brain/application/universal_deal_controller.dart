import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/universal_deal.dart';
import 'universal_deal_brain.dart';

class UniversalDealSession {
  const UniversalDealSession({this.deal, this.lastQuestion, this.completed = false});

  final UniversalDeal? deal;
  final String? lastQuestion;
  final bool completed;

  UniversalDealSession copyWith({UniversalDeal? deal, String? lastQuestion, bool? completed}) {
    return UniversalDealSession(
      deal: deal ?? this.deal,
      lastQuestion: lastQuestion,
      completed: completed ?? this.completed,
    );
  }
}

final universalDealControllerProvider =
    StateNotifierProvider<UniversalDealController, UniversalDealSession>(
  (ref) => UniversalDealController(),
);

class UniversalDealController extends StateNotifier<UniversalDealSession> {
  UniversalDealController() : super(const UniversalDealSession());

  final UniversalDealBrain _brain = const UniversalDealBrain();

  void start(String text) {
    final deal = _brain.capture(text);
    state = UniversalDealSession(
      deal: deal,
      lastQuestion: _questionFor(deal.missingForMatch.firstOrNull),
      completed: deal.readyToMatch,
    );
  }

  void answer(String text) {
    final current = state.deal;
    if (current == null) {
      start(text);
      return;
    }
    final value = text.trim();
    if (value.isEmpty) return;
    final missing = current.missingForMatch;
    if (missing.isEmpty) return;

    final field = missing.first;
    var dynamic = Map<String, Object?>.from(current.dynamicFields);
    var next = current;

    switch (field) {
      case 'subject':
        next = current.copyWith(subject: value);
        break;
      case 'location':
        next = current.copyWith(location: DealLocation(label: value, radiusKm: current.location.radiusKm));
        break;
      case 'timing':
        next = current.copyWith(timing: value);
        break;
      case 'from':
      case 'to':
      case 'skill':
        dynamic[field] = value;
        next = current.copyWith(dynamicFields: dynamic);
        break;
      default:
        dynamic[field] = value;
        next = current.copyWith(dynamicFields: dynamic);
    }

    state = UniversalDealSession(
      deal: next,
      lastQuestion: _questionFor(next.missingForMatch.firstOrNull),
      completed: next.readyToMatch,
    );
  }

  void reset() => state = const UniversalDealSession();

  String? _questionFor(String? field) => switch (field) {
        'subject' => 'What exactly do you need or offer?',
        'location' => 'Where should ASKODOX find the match?',
        'timing' => 'When do you need this?',
        'from' => 'Where does it start from?',
        'to' => 'Where should it go to?',
        'skill' => 'What skill or work is required?',
        null => null,
        _ => 'Please tell me the missing $field detail.',
      };
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
