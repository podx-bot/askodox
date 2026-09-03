import 'dart:math' as math;

import 'no_match_recovery.dart';
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
  const DealMatchResult({
    required this.matches,
    this.recovery,
  });

  final List<DealMatch> matches;
  final NoMatchRecoveryPlan? recovery;

  bool get hasLocalMatch => matches.isNotEmpty;
  bool get needsNoMatchRecovery => recovery != null;
}

class DealMatcher {
  const DealMatcher();

  DealMatchResult match(UniversalDeal request, Iterable<DealMatchCandidate> candidates) {
    if (!request.readyToMatch) {
      return const DealMatchResult(matches: []);
    }

    final matches = <DealMatch>[];
    for (final candidate in candidates) {
      final supply = candidate.deal;
      if (!supply.readyToMatch || supply.intent != request.oppositeIntent) continue;
      if (!_sameCategory(request, supply)) continue;
      if (!_sameSubject(request, supply)) continue;
      if (!_jobCompatible(request, supply)) continue;
      if (!_routeCompatible(request, supply)) continue;
      if (!_timingCompatible(request, supply)) continue;
      if (!_capacityCompatible(request, supply)) continue;

      final distanceKm = _distanceKm(request.location, supply.location);
      if (!_locationCompatible(request, supply, distanceKm)) continue;

      var score = 60.0;
      if (request.productProfile == supply.productProfile) score += 15;
      if (_normalized(request.subject) == _normalized(supply.subject)) score += 10;
      score += _jobScore(request, supply);
      score += _routeScore(request, supply);
      score += candidate.trustScore.clamp(0, 100) * 0.15;
      if (distanceKm != null) {
        score += (10 - distanceKm).clamp(0, 10);
      }
      matches.add(
        DealMatch(candidate: candidate, score: score, distanceKm: distanceKm),
      );
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return DealMatchResult(
      matches: matches,
      recovery: matches.isEmpty ? const NoMatchRecovery().build(request) : null,
    );
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
    if (_isWorkDeal(a) && _isWorkDeal(b)) {
      return _sameMeaning(
        a.dynamicFields['skill']?.toString() ?? a.subject,
        b.dynamicFields['skill']?.toString() ?? b.subject,
      );
    }

    if (_isRouteDeal(a) && _isRouteDeal(b)) return true;
    return _sameMeaning(a.subject, b.subject);
  }

  bool _jobCompatible(UniversalDeal a, UniversalDeal b) {
    if (!_isWorkDeal(a) || !_isWorkDeal(b)) return true;

    final employer = a.intent == DealIntent.needWorker ? a : b;
    final worker = a.intent == DealIntent.seekWork ? a : b;

    final requiredType = _normalized(employer.dynamicFields['jobType']?.toString());
    final workerType = _normalized(worker.dynamicFields['jobType']?.toString());
    if (requiredType.isNotEmpty && workerType.isNotEmpty && requiredType != workerType) {
      return false;
    }

    final minimumExperience = _number(employer.dynamicFields['minExperienceYears']);
    final workerExperience = _number(worker.dynamicFields['experienceYears']);
    if (minimumExperience != null &&
        workerExperience != null &&
        workerExperience < minimumExperience) {
      return false;
    }

    return true;
  }

  bool _routeCompatible(UniversalDeal a, UniversalDeal b) {
    if (!_isRouteDeal(a) || !_isRouteDeal(b)) return true;
    return _sameMeaning(
          a.dynamicFields['from']?.toString(),
          b.dynamicFields['from']?.toString(),
        ) &&
        _sameMeaning(
          a.dynamicFields['to']?.toString(),
          b.dynamicFields['to']?.toString(),
        );
  }

  bool _timingCompatible(UniversalDeal a, UniversalDeal b) {
    if (!_isRouteDeal(a) || !_isRouteDeal(b)) return true;
    final left = _normalized(a.timing);
    final right = _normalized(b.timing);
    if (left.isEmpty || right.isEmpty) return true;
    return left == right;
  }

  bool _capacityCompatible(UniversalDeal a, UniversalDeal b) {
    if (_isRidePair(a, b)) {
      final passenger = a.intent == DealIntent.needRide ? a : b;
      final driver = a.intent == DealIntent.offerRide ? a : b;
      final neededSeats = _number(passenger.dynamicFields['seats']) ?? passenger.quantity;
      final availableSeats =
          _number(driver.dynamicFields['seatsAvailable']) ??
          _number(driver.dynamicFields['seats']) ??
          driver.quantity;
      if (neededSeats != null && availableSeats != null && availableSeats < neededSeats) {
        return false;
      }
    }

    if (_isParcelPair(a, b)) {
      final parcel = a.intent == DealIntent.sendParcel ? a : b;
      final carrier = a.intent == DealIntent.deliverParcel ? a : b;
      final parcelWeight =
          _number(parcel.dynamicFields['weightKg']) ?? _number(parcel.weight);
      final maxWeight = _number(carrier.dynamicFields['maxWeightKg']);
      if (parcelWeight != null && maxWeight != null && parcelWeight > maxWeight) {
        return false;
      }
    }

    return true;
  }

  double _jobScore(UniversalDeal a, UniversalDeal b) {
    if (!_isWorkDeal(a) || !_isWorkDeal(b)) return 0;

    final employer = a.intent == DealIntent.needWorker ? a : b;
    final worker = a.intent == DealIntent.seekWork ? a : b;
    var score = 0.0;

    final employerSkill = _normalized(employer.dynamicFields['skill']?.toString());
    final workerSkill = _normalized(worker.dynamicFields['skill']?.toString());
    if (employerSkill.isNotEmpty && employerSkill == workerSkill) score += 12;

    final requiredType = _normalized(employer.dynamicFields['jobType']?.toString());
    final workerType = _normalized(worker.dynamicFields['jobType']?.toString());
    if (requiredType.isNotEmpty && requiredType == workerType) score += 4;

    final minimumExperience = _number(employer.dynamicFields['minExperienceYears']);
    final workerExperience = _number(worker.dynamicFields['experienceYears']);
    if (minimumExperience != null && workerExperience != null) {
      score += (workerExperience - minimumExperience).clamp(0, 5);
    }

    return score;
  }

  double _routeScore(UniversalDeal a, UniversalDeal b) {
    if (!_isRouteDeal(a) || !_isRouteDeal(b)) return 0;
    var score = 0.0;
    if (_normalized(a.dynamicFields['from']?.toString()) ==
        _normalized(b.dynamicFields['from']?.toString())) score += 8;
    if (_normalized(a.dynamicFields['to']?.toString()) ==
        _normalized(b.dynamicFields['to']?.toString())) score += 8;
    if (_normalized(a.timing).isNotEmpty &&
        _normalized(a.timing) == _normalized(b.timing)) score += 4;
    return score;
  }

  bool _isWorkDeal(UniversalDeal deal) =>
      deal.intent == DealIntent.needWorker || deal.intent == DealIntent.seekWork;

  bool _isRouteDeal(UniversalDeal deal) =>
      deal.intent == DealIntent.needRide ||
      deal.intent == DealIntent.offerRide ||
      deal.intent == DealIntent.sendParcel ||
      deal.intent == DealIntent.deliverParcel;

  bool _isRidePair(UniversalDeal a, UniversalDeal b) =>
      {a.intent, b.intent}.contains(DealIntent.needRide) &&
      {a.intent, b.intent}.contains(DealIntent.offerRide);

  bool _isParcelPair(UniversalDeal a, UniversalDeal b) =>
      {a.intent, b.intent}.contains(DealIntent.sendParcel) &&
      {a.intent, b.intent}.contains(DealIntent.deliverParcel);

  bool _sameMeaning(String? leftValue, String? rightValue) {
    final left = _normalized(leftValue);
    final right = _normalized(rightValue);
    if (left.isEmpty || right.isEmpty) return true;
    return left == right || left.contains(right) || right.contains(left);
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'-?[0-9]+(?:\.[0-9]+)?').firstMatch(text);
    return double.tryParse(match?.group(0) ?? '');
  }

  bool _locationCompatible(UniversalDeal a, UniversalDeal b, double? distanceKm) {
    if (_isRouteDeal(a) && _isRouteDeal(b)) return true;
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
