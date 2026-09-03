import 'universal_deal.dart';

class DealMatchCandidate {
  const DealMatchCandidate({
    required this.id,
    required this.deal,
    this.trustScore = 0,
  });

  final String id;
  final UniversalDeal deal;
  final double trustScore;
}

class DealMatch {
  const DealMatch({required this.candidate, required this.score});
  final DealMatchCandidate candidate;
  final double score;
}

class DealMatchResult {
  const DealMatchResult({required this.matches});
  final List<DealMatch> matches;
  bool get hasLocalMatch => matches.isNotEmpty;
  bool get needsNoMatchRecovery => matches.isEmpty;
}

class DealMatcher {
  const DealMatcher();

  DealMatchResult match(UniversalDeal request, Iterable<DealMatchCandidate> candidates) {
    if (!request.readyToMatch) return const DealMatchResult(matches: []);

    final matches = <DealMatch>[];
    for (final candidate in candidates) {
      final supply = candidate.deal;
      if (!supply.readyToMatch || supply.intent != request.oppositeIntent) continue;
      if (!_sameCategory(request, supply)) continue;
      if (!_sameSubject(request, supply)) continue;
      if (!_locationCompatible(request, supply)) continue;

      var score = 60.0;
      if (request.productProfile == supply.productProfile) score += 15;
      if (_normalized(request.subject) == _normalized(supply.subject)) score += 10;
      score += candidate.trustScore.clamp(0, 100) * 0.15;
      matches.add(DealMatch(candidate: candidate, score: score));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return DealMatchResult(matches: matches);
  }

  bool _sameCategory(UniversalDeal a, UniversalDeal b) {
    final ac = _normalized(a.category);
    final bc = _normalized(b.category);
    if (ac.isNotEmpty && bc.isNotEmpty && ac != bc) return false;
    if ((a.intent == DealIntent.buy || a.intent == DealIntent.sell) &&
        (b.intent == DealIntent.buy || b.intent == DealIntent.sell)) {
      return a.productProfile == b.productProfile;
    }
    return true;
  }

  bool _sameSubject(UniversalDeal a, UniversalDeal b) {
    final left = _normalized(a.subject);
    final right = _normalized(b.subject);
    if (left.isEmpty || right.isEmpty) return true;
    return left == right || left.contains(right) || right.contains(left);
  }

  bool _locationCompatible(UniversalDeal a, UniversalDeal b) {
    if (a.fulfilment == 'online' || b.fulfilment == 'online') return true;
    final left = _normalized(a.location.label);
    final right = _normalized(b.location.label);
    if (left.isEmpty || right.isEmpty) return true;
    return left == right || left.contains(right) || right.contains(left);
  }

  String _normalized(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
