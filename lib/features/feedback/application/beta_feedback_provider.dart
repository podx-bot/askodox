import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/beta_feedback.dart';

class BetaFeedbackNotifier extends Notifier<List<BetaFeedback>> {
  @override
  List<BetaFeedback> build() => const [];

  void submit(BetaFeedback feedback) => state = [...state, feedback];
  void reset() => state = const [];
}

final betaFeedbackProvider =
    NotifierProvider<BetaFeedbackNotifier, List<BetaFeedback>>(BetaFeedbackNotifier.new);
