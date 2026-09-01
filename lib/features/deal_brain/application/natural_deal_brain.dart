import '../domain/universal_deal.dart';
import 'domain_brain_registry.dart';
import 'universal_deal_brain.dart';

class GoalResolution {
  const GoalResolution({required this.id, required this.label, required this.confidence, this.requiredSignals = const [], this.optionalSignals = const [], this.actions = const []});
  final String id;
  final String label;
  final double confidence;
  final List<String> requiredSignals;
  final List<String> optionalSignals;
  final List<String> actions;
}

class NaturalDealResult {
  const NaturalDealResult({required this.deal, required this.domain, required this.profile, required this.goal});
  final UniversalDeal deal;
  final NaturalDomain domain;
  final DomainBrainProfile profile;
  final GoalResolution goal;
}

class NaturalDealBrain {
  const NaturalDealBrain({this.universal = const UniversalDealBrain(), this.domains = const DomainBrainRegistry()});
  final UniversalDealBrain universal;
  final DomainBrainRegistry domains;

  NaturalDealResult understand(String rawText) {
    final deal = universal.capture(rawText);
    final domain = domains.detect(rawText, category: deal.category);
    final profile = domains.profile(domain);
    return NaturalDealResult(deal: deal, domain: domain, profile: profile, goal: _resolveGoal(rawText, domain, profile));
  }

  GoalResolution _resolveGoal(String rawText, NaturalDomain domain, DomainBrainProfile profile) {
    final text = rawText.trim().toLowerCase();
    bool any(List<String> values) => values.any(text.contains);

    if (domain == NaturalDomain.insurance) {
      if (any(['claim', 'settlement', 'hospital claim', 'క్లెయిమ్'])) {
        return const GoalResolution(id: 'insurance_claim', label: 'Handle an insurance claim', confidence: .95, requiredSignals: ['policy_or_provider', 'claim_need'], optionalSignals: ['incident_or_treatment', 'documents', 'claim_status'], actions: ['explain_claim_steps', 'check_documents', 'track_or_connect_claim']);
      }
      if (any(['renew', 'renewal', 'expiring', 'రిన్యూ'])) {
        return const GoalResolution(id: 'insurance_renewal', label: 'Renew or review an existing policy', confidence: .95, requiredSignals: ['existing_policy'], optionalSignals: ['expiry_date', 'current_premium', 'coverage_changes'], actions: ['review_existing_cover', 'compare_renewal', 'renew_or_connect']);
      }
      // Once the domain is confidently insurance, an ordinary request for
      // insurance/cover/policy is naturally a new-policy discovery goal unless
      // claim or renewal language above says otherwise. This avoids requiring
      // users to phrase the request as "need insurance" exactly.
      if (any(['insurance', 'policy', 'cover', 'coverage', 'premium', 'బీమా', 'ఇన్సూరెన్స్'])) {
        return const GoalResolution(id: 'insurance_new_policy', label: 'Find suitable insurance coverage', confidence: .9, requiredSignals: ['policy_need'], optionalSignals: ['coverage', 'premium_budget', 'tenure', 'family'], actions: ['compare_coverage', 'explain_exclusions', 'connect_provider']);
      }
    }

    if (domain == NaturalDomain.jobs) {
      if (any(['hire', 'hiring', 'need worker', 'need staff', 'recruit'])) {
        return const GoalResolution(id: 'jobs_hire', label: 'Find or hire a suitable worker', confidence: .95, requiredSignals: ['role_or_skill', 'location'], optionalSignals: ['experience', 'salary', 'shift', 'employment_type'], actions: ['match_candidates', 'compare_fit', 'interview_or_connect']);
      }
      if (any(['resume', 'cv'])) {
        return const GoalResolution(id: 'jobs_resume_help', label: 'Improve a resume or CV', confidence: .95, requiredSignals: ['target_role'], optionalSignals: ['experience', 'skills', 'existing_resume'], actions: ['review_resume', 'improve_positioning', 'prepare_application']);
      }
      if (any(['interview', 'mock interview'])) {
        return const GoalResolution(id: 'jobs_interview_help', label: 'Prepare for an interview', confidence: .95, requiredSignals: ['target_role'], optionalSignals: ['company', 'experience', 'interview_stage'], actions: ['prepare_questions', 'practice_answers', 'improve_readiness']);
      }
      return GoalResolution(id: 'jobs_find_work', label: 'Find suitable work', confidence: .85, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);
    }

    if (domain == NaturalDomain.appointments) return GoalResolution(id: 'appointment_book', label: 'Find and book a suitable appointment', confidence: .85, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);
    if (domain == NaturalDomain.rides) return GoalResolution(id: 'ride_arrange', label: 'Arrange a ride for the requested route', confidence: .85, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);
    if (domain == NaturalDomain.services) return GoalResolution(id: 'service_solve', label: 'Solve the service need with a suitable provider', confidence: .85, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);
    if (domain == NaturalDomain.commerce || domain == NaturalDomain.grocery || domain == NaturalDomain.freshFood) return GoalResolution(id: 'commerce_transaction', label: 'Find the right item and complete the transaction', confidence: .8, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);

    if (domain != NaturalDomain.general) return GoalResolution(id: '${domain.name}_goal', label: rawText.trim(), confidence: .65, requiredSignals: profile.requiredSignals, optionalSignals: profile.optionalSignals, actions: profile.actions);

    return GoalResolution(id: 'open_ended', label: rawText.trim().isEmpty ? 'Understand and solve the user goal' : rawText.trim(), confidence: .5, requiredSignals: const ['goal'], optionalSignals: const ['location', 'budget', 'timing', 'preferences'], actions: const ['understand_goal', 'derive_schema', 'ask_missing_only', 'solve_or_route']);
  }

  List<String> missingRequiredSignals(NaturalDealResult result, {Iterable<String> knownSignals = const []}) {
    final known = knownSignals.map((e) => e.trim().toLowerCase()).toSet();
    final required = result.goal.requiredSignals.isNotEmpty ? result.goal.requiredSignals : result.profile.requiredSignals;
    return required.where((signal) => !known.contains(signal.toLowerCase())).toList(growable: false);
  }
}
