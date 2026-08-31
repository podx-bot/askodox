import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/universal_negotiation.dart';

void main() {
  const engine = UniversalNegotiationEngine();
  const policy = NegotiationPolicy(
    askingPrice: 220,
    autoAcceptFloor: 210,
    counterStep: 5,
  );

  test('accepts buyer offer inside seller auto-approval boundary', () {
    final result = engine.evaluate(buyerOffer: 215, policy: policy);

    expect(result.decision, NegotiationDecision.accepted);
    expect(result.agreedPrice, 215);
    expect(result.needsSeller, isFalse);
  });

  test('does not reveal or cross seller floor for low offer', () {
    final result = engine.evaluate(buyerOffer: 200, policy: policy);

    expect(result.decision, NegotiationDecision.countered);
    expect(result.counterOffer, 210);
    expect(result.agreedPrice, isNull);
  });

  test('escalates when seller has no counter rule and offer is outside boundary', () {
    const strict = NegotiationPolicy(askingPrice: 220, autoAcceptFloor: 210);
    final result = engine.evaluate(buyerOffer: 200, policy: strict);

    expect(result.decision, NegotiationDecision.sellerApprovalRequired);
    expect(result.needsSeller, isTrue);
  });

  test('asking price wins when buyer offers more than asking', () {
    final result = engine.evaluate(buyerOffer: 230, policy: policy);

    expect(result.decision, NegotiationDecision.accepted);
    expect(result.agreedPrice, 220);
  });

  test('parses natural buyer price offers', () {
    expect(engine.parseBuyerOffer('₹215 చేస్తారా?'), 215);
    expect(engine.parseBuyerOffer('Rs. 210 final?'), 210);
    expect(engine.parseBuyerOffer('I can pay INR 205'), 205);
    expect(engine.parseBuyerOffer('no number here'), isNull);
  });
}
