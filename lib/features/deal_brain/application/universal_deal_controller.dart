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
    final value = text.trim();
    if (value.isEmpty) return;

    // If a requirement is already being collected, text entered on the
    // conversation screen is an answer to the current missing field. Starting
    // a fresh capture here used to turn answers such as "Vuyyuru" into a new
    // product requirement and lose the original "chicken nearby" request.
    final current = state.deal;
    if (current != null && current.missingForMatch.isNotEmpty) {
      answer(value);
      return;
    }

    final deal = _brain.capture(value);
    state = UniversalDealSession(
      deal: deal,
      lastQuestion: _questionFor(deal.missingForMatch.firstOrNull),
      completed: deal.readyToMatch,
    );
  }

  void answer(String text) {
    final current = state.deal;
    if (current == null) {
      final value = text.trim();
      if (value.isEmpty) return;
      final deal = _brain.capture(value);
      state = UniversalDealSession(
        deal: deal,
        lastQuestion: _questionFor(deal.missingForMatch.firstOrNull),
        completed: deal.readyToMatch,
      );
      return;
    }
    final value = text.trim();
    if (value.isEmpty) return;
    final missing = current.missingForMatch;
    if (missing.isEmpty) return;

    final field = missing.first;
    final dynamic = Map<String, Object?>.from(current.dynamicFields);
    var next = current;

    switch (field) {
      case 'subject':
        next = current.copyWith(subject: value);
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
