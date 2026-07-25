import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/feedback/application/beta_feedback_provider.dart';
import 'package:podx/features/feedback/domain/beta_feedback.dart';

void main() {
  test('feedback remains local and can be reset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final item = BetaFeedback(
      id: 'feedback-1',
      category: FeedbackCategory.bug,
      description: 'Search results did not update.',
      screenName: 'Search',
      severity: FeedbackSeverity.high,
      contactAllowed: false,
      submittedAt: DateTime.utc(2026, 7, 25),
    );

    container.read(betaFeedbackProvider.notifier).submit(item);
    expect(container.read(betaFeedbackProvider), [item]);
    container.read(betaFeedbackProvider.notifier).reset();
    expect(container.read(betaFeedbackProvider), isEmpty);
  });
}
