enum FeedbackCategory { bug, feature, ui, search, price, seller, performance, other }
enum FeedbackSeverity { low, medium, high, blocking }

class BetaFeedback {
  const BetaFeedback({
    required this.id,
    required this.category,
    required this.description,
    required this.screenName,
    required this.severity,
    required this.contactAllowed,
    required this.submittedAt,
    this.screenshotReference,
  });

  final String id;
  final FeedbackCategory category;
  final String description;
  final String screenName;
  final FeedbackSeverity severity;
  final String? screenshotReference;
  final bool contactAllowed;
  final DateTime submittedAt;
}
