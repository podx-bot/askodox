import 'dart:math' as math;

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
  const DealMatch({
    required this.candidate,
    required this.score,
    this.distanceKm,
  });

  final DealMatchCandidate candidate;
  final double score;
  final double? distanceKm;
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

      final distanceKm = _distanceKm(request.location, supply.location);
      if (!_locationCompatible(request, supply, distanceKm)) continue;

      var score = 60.0;
      if (request.productProfile == supply.productProfile) score += 15;
      if (_normalized(request.subject) == _normalized(supply.subject)) score += 10;
      score += candidate.trustScore.clamp(0, 100) * 0.15;
      if (distanceKm != null) {
        score += (10 - distanceKm).clamp(0, 10);
      }
      matches.add(
        DealMatch(candidate: candidate, score: score, distanceKm: distanceKm),
      );
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

  bool _locationCompatible(UniversalDeal a, UniversalDeal b, double? distanceKm) {
    if (a.fulfilment == 'online' || b.fulfilment == 'online') return true;

    if (distanceKm != null) {
      final limits = <double>[
        if (a.location.radiusKm != null && a.location.radiusKm! > 0) a.location.radiusKm!,
        if (b.location.radiusKm != null && b.location.radiusKm! > 0) b.location.radiusKm!,
      ];
      if (limits.isNotEmpty && distanceKm > limits.reduce(math.min)) return false;
      return true;
    }

    final left = _normalized(a.location.label);
    final right = _normalized(b.location.label);
    if (left.isEmpty || right.isEmpty) return true;
    return left == right || left.contains(right) || right.contains(left);
  }

  double? _distanceKm(DealLocation a, DealLocation b) {
    if (a.latitude == null || a.longitude == null || b.latitude == null || b.longitude == null) {
      return null;
    }

    const earthRadiusKm = 6371.0;
    final lat1 = _radians(a.latitude!);
    final lat2 = _radians(b.latitude!);
    final deltaLat = _radians(b.latitude! - a.latitude!);
    final deltaLon = _radians(b.longitude! - a.longitude!);
    final h = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(deltaLon / 2) * math.sin(deltaLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  String _normalized(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
