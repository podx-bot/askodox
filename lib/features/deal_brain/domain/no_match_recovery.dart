import 'universal_deal.dart';

class NoMatchAdminSignal {
  const NoMatchAdminSignal({
    required this.reason,
    required this.intent,
    required this.subject,
    required this.location,
    required this.category,
  });

  final String reason;
  final DealIntent intent;
  final String? subject;
  final String? location;
  final String? category;
}

enum NoMatchFallbackKind {
  broadenLocalRadius,
  onlineSuggestion,
  affiliateSuggestion,
  adminReview,
}

class NoMatchFallbackAction {
  const NoMatchFallbackAction({required this.kind, required this.label});
  final NoMatchFallbackKind kind;
  final String label;
}

class NoMatchRecoveryPlan {
  const NoMatchRecoveryPlan({
    required this.adminSignal,
    required this.actions,
  });

  final NoMatchAdminSignal adminSignal;
  final List<NoMatchFallbackAction> actions;
}

class NoMatchRecovery {
  const NoMatchRecovery();

  NoMatchRecoveryPlan? build(UniversalDeal request) {
    if (!request.readyToMatch) return null;

    final actions = <NoMatchFallbackAction>[
      if (request.fulfilment != 'online')
        const NoMatchFallbackAction(
          kind: NoMatchFallbackKind.broadenLocalRadius,
          label: 'Search a wider local area',
        ),
      if (request.intent == DealIntent.buy)
        const NoMatchFallbackAction(
          kind: NoMatchFallbackKind.onlineSuggestion,
          label: 'Show relevant online alternatives',
        ),
      if (request.intent == DealIntent.buy)
        const NoMatchFallbackAction(
          kind: NoMatchFallbackKind.affiliateSuggestion,
          label: 'Show verified external buying options',
        ),
      const NoMatchFallbackAction(
        kind: NoMatchFallbackKind.adminReview,
        label: 'Send no-match case for admin review',
      ),
    ];

    return NoMatchRecoveryPlan(
      adminSignal: NoMatchAdminSignal(
        reason: 'no_relevant_local_match',
        intent: request.intent,
        subject: request.subject,
        location: request.location.label,
        category: request.category,
      ),
      actions: actions,
    );
  }
}
