import '../domain/universal_deal.dart';
import 'domain_brain_registry.dart';
import 'universal_deal_brain.dart';

class NaturalDealResult {
  const NaturalDealResult({
    required this.deal,
    required this.domain,
    required this.profile,
  });

  final UniversalDeal deal;
  final NaturalDomain domain;
  final DomainBrainProfile profile;
}

/// Conversation-first entry point for ASKODOX deal understanding.
///
/// UniversalDealBrain extracts shared deal state. DomainBrainRegistry then
/// selects the natural behaviour family for the user's actual goal, so a
/// fresh-food example cannot dictate jobs, insurance, loans, rides, etc.
class NaturalDealBrain {
  const NaturalDealBrain({
    this.universal = const UniversalDealBrain(),
    this.domains = const DomainBrainRegistry(),
  });

  final UniversalDealBrain universal;
  final DomainBrainRegistry domains;

  NaturalDealResult understand(String rawText) {
    final deal = universal.capture(rawText);
    final domain = domains.detect(rawText, category: deal.category);
    return NaturalDealResult(
      deal: deal,
      domain: domain,
      profile: domains.profile(domain),
    );
  }

  /// Returns only the questions that are still useful for this domain.
  /// Caller-provided known signals are normalized to lower-case field names.
  List<String> missingRequiredSignals(
    NaturalDealResult result, {
    Iterable<String> knownSignals = const [],
  }) {
    final known = knownSignals.map((e) => e.trim().toLowerCase()).toSet();
    return result.profile.requiredSignals
        .where((signal) => !known.contains(signal.toLowerCase()))
        .toList(growable: false);
  }
}
