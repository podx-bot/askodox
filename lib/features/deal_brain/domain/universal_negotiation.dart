enum NegotiationDecision {
  accepted,
  countered,
  sellerApprovalRequired,
  unavailable,
}

class NegotiationPolicy {
  const NegotiationPolicy({
    required this.askingPrice,
    this.autoAcceptFloor,
    this.counterStep,
    this.currency = 'INR',
  });

  final double askingPrice;
  final double? autoAcceptFloor;
  final double? counterStep;
  final String currency;

  double get effectiveFloor {
    final floor = autoAcceptFloor;
    if (floor == null) return askingPrice;
    return floor.clamp(0, askingPrice).toDouble();
  }
}

class NegotiationResult {
  const NegotiationResult({
    required this.decision,
    required this.buyerOffer,
    required this.askingPrice,
    this.agreedPrice,
    this.counterOffer,
    this.reason,
  });

  final NegotiationDecision decision;
  final double buyerOffer;
  final double askingPrice;
  final double? agreedPrice;
  final double? counterOffer;
  final String? reason;

  bool get isResolved => decision == NegotiationDecision.accepted;
  bool get needsSeller => decision == NegotiationDecision.sellerApprovalRequired;
}

class UniversalNegotiationEngine {
  const UniversalNegotiationEngine();

  NegotiationResult evaluate({
    required double buyerOffer,
    required NegotiationPolicy policy,
  }) {
    if (buyerOffer <= 0 || policy.askingPrice <= 0) {
      return NegotiationResult(
        decision: NegotiationDecision.unavailable,
        buyerOffer: buyerOffer,
        askingPrice: policy.askingPrice,
        reason: 'A valid positive buyer offer and asking price are required.',
      );
    }

    final asking = policy.askingPrice;
    final floor = policy.effectiveFloor;

    if (buyerOffer >= asking) {
      return NegotiationResult(
        decision: NegotiationDecision.accepted,
        buyerOffer: buyerOffer,
        askingPrice: asking,
        agreedPrice: asking,
        reason: 'Buyer offer meets or exceeds the asking price.',
      );
    }

    if (buyerOffer >= floor) {
      return NegotiationResult(
        decision: NegotiationDecision.accepted,
        buyerOffer: buyerOffer,
        askingPrice: asking,
        agreedPrice: buyerOffer,
        reason: 'Buyer offer is inside the seller auto-approval boundary.',
      );
    }

    final step = policy.counterStep;
    if (step != null && step > 0) {
      final candidate = (buyerOffer + step).clamp(floor, asking).toDouble();
      if (candidate >= floor && candidate < asking) {
        return NegotiationResult(
          decision: NegotiationDecision.countered,
          buyerOffer: buyerOffer,
          askingPrice: asking,
          counterOffer: candidate,
          reason: 'ASKODOX can make a policy-safe counter without exposing the seller floor.',
        );
      }
    }

    return NegotiationResult(
      decision: NegotiationDecision.sellerApprovalRequired,
      buyerOffer: buyerOffer,
      askingPrice: asking,
      reason: 'Buyer offer is outside the seller auto-approval boundary.',
    );
  }

  double? parseBuyerOffer(String text) {
    final normalized = text.replaceAll(',', '');
    final currency = RegExp(r'(?:₹|rs\.?|inr)\s*(\d+(?:\.\d+)?)', caseSensitive: false)
        .firstMatch(normalized);
    final match = currency ?? RegExp(r'\b(\d+(?:\.\d+)?)\b').firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }
}
