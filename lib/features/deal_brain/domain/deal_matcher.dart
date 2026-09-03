import 'dart:math' as math;

import 'no_match_recovery.dart';
import 'universal_deal.dart';

class DealMatchCandidate { const DealMatchCandidate({required this.id, required this.deal, this.trustScore = 0}); final String id; final UniversalDeal deal; final double trustScore; }
class DealMatch { const DealMatch({required this.candidate, required this.score, this.distanceKm}); final DealMatchCandidate candidate; final double score; final double? distanceKm; }
class DealMatchResult { const DealMatchResult({required this.matches, this.recovery}); final List<DealMatch> matches; final NoMatchRecoveryPlan? recovery; bool get hasLocalMatch => matches.isNotEmpty; bool get needsNoMatchRecovery => recovery != null; }

class DealMatcher {
  const DealMatcher();
  DealMatchResult match(UniversalDeal request, Iterable<DealMatchCandidate> candidates) {
    if (!request.readyToMatch) return const DealMatchResult(matches: []);
    final matches = <DealMatch>[];
    for (final candidate in candidates) {
      final supply = candidate.deal;
      if (!supply.readyToMatch || supply.intent != request.oppositeIntent) continue;
      if (!_sameCategory(request, supply) || !_sameSubject(request, supply)) continue;
      if (!_jobCompatible(request, supply) || !_routeCompatible(request, supply)) continue;
      if (!_timingCompatible(request, supply) || !_capacityCompatible(request, supply)) continue;
      if (!_rentalCompatible(request, supply) || !_appointmentCompatible(request, supply)) continue;
      final distanceKm = _distanceKm(request.location, supply.location);
      if (!_locationCompatible(request, supply, distanceKm)) continue;
      var score = 60.0;
      if (request.productProfile == supply.productProfile) score += 15;
      if (_normalized(request.subject) == _normalized(supply.subject)) score += 10;
      score += _jobScore(request, supply) + _routeScore(request, supply) + _rentalScore(request, supply) + _appointmentScore(request, supply);
      score += candidate.trustScore.clamp(0, 100) * 0.15;
      if (distanceKm != null) score += (10 - distanceKm).clamp(0, 10);
      matches.add(DealMatch(candidate: candidate, score: score, distanceKm: distanceKm));
    }
    matches.sort((a,b) => b.score.compareTo(a.score));
    return DealMatchResult(matches: matches, recovery: matches.isEmpty ? const NoMatchRecovery().build(request) : null);
  }

  bool _sameCategory(UniversalDeal a, UniversalDeal b) {
    final ac=_normalized(a.category), bc=_normalized(b.category); if(ac.isNotEmpty&&bc.isNotEmpty&&ac!=bc)return false;
    if ((a.intent==DealIntent.buy||a.intent==DealIntent.sell)&&(b.intent==DealIntent.buy||b.intent==DealIntent.sell)) return a.productProfile==b.productProfile;
    return true;
  }
  bool _sameSubject(UniversalDeal a, UniversalDeal b) {
    if(_isWorkDeal(a)&&_isWorkDeal(b)) return _sameMeaning(a.dynamicFields['skill']?.toString()??a.subject,b.dynamicFields['skill']?.toString()??b.subject);
    if(_isRouteDeal(a)&&_isRouteDeal(b)) return true;
    return _sameMeaning(a.subject,b.subject);
  }
  bool _jobCompatible(UniversalDeal a, UniversalDeal b) {
    if(!_isWorkDeal(a)||!_isWorkDeal(b))return true; final employer=a.intent==DealIntent.needWorker?a:b, worker=a.intent==DealIntent.seekWork?a:b;
    final rt=_normalized(employer.dynamicFields['jobType']?.toString()), wt=_normalized(worker.dynamicFields['jobType']?.toString()); if(rt.isNotEmpty&&wt.isNotEmpty&&rt!=wt)return false;
    final min=_number(employer.dynamicFields['minExperienceYears']), exp=_number(worker.dynamicFields['experienceYears']); return !(min!=null&&exp!=null&&exp<min);
  }
  bool _routeCompatible(UniversalDeal a, UniversalDeal b) => !_isRouteDeal(a)||!_isRouteDeal(b)||(_sameMeaning(a.dynamicFields['from']?.toString(),b.dynamicFields['from']?.toString())&&_sameMeaning(a.dynamicFields['to']?.toString(),b.dynamicFields['to']?.toString()));
  bool _timingCompatible(UniversalDeal a, UniversalDeal b) { if(!_isRouteDeal(a)||!_isRouteDeal(b))return true; final l=_normalized(a.timing),r=_normalized(b.timing); return l.isEmpty||r.isEmpty||l==r; }
  bool _capacityCompatible(UniversalDeal a, UniversalDeal b) {
    if(_isRidePair(a,b)){final p=a.intent==DealIntent.needRide?a:b,d=a.intent==DealIntent.offerRide?a:b;final n=_number(p.dynamicFields['seats'])??p.quantity,v=_number(d.dynamicFields['seatsAvailable'])??_number(d.dynamicFields['seats'])??d.quantity;if(n!=null&&v!=null&&v<n)return false;}
    if(_isParcelPair(a,b)){final p=a.intent==DealIntent.sendParcel?a:b,c=a.intent==DealIntent.deliverParcel?a:b;final w=_number(p.dynamicFields['weightKg'])??_number(p.weight),m=_number(c.dynamicFields['maxWeightKg']);if(w!=null&&m!=null&&w>m)return false;} return true;
  }
  bool _rentalCompatible(UniversalDeal a, UniversalDeal b) {
    if(!_isRentalPair(a,b)) return true; final renter=a.intent==DealIntent.rent?a:b, offer=a.intent==DealIntent.offerRental?a:b;
    if(!_sameMeaning(renter.dynamicFields['rentalType']?.toString(),offer.dynamicFields['rentalType']?.toString())) return false;
    final startA=_normalized(renter.dynamicFields['startDate']?.toString()), startB=_normalized(offer.dynamicFields['startDate']?.toString()); if(startA.isNotEmpty&&startB.isNotEmpty&&startA!=startB)return false;
    final needed=_number(renter.dynamicFields['durationDays']), available=_number(offer.dynamicFields['availableDays']); if(needed!=null&&available!=null&&available<needed)return false; return true;
  }
  bool _appointmentCompatible(UniversalDeal a, UniversalDeal b) {
    if(!_isAppointmentPair(a,b))return true; final client=a.intent==DealIntent.bookAppointment?a:b, provider=a.intent==DealIntent.offerAppointment?a:b;
    if(!_sameMeaning(client.dynamicFields['speciality']?.toString()??client.subject,provider.dynamicFields['speciality']?.toString()??provider.subject))return false;
    final requested=_normalized(client.dynamicFields['slot']?.toString()??client.timing), offered=_normalized(provider.dynamicFields['slot']?.toString()??provider.timing); return requested.isEmpty||offered.isEmpty||requested==offered;
  }
  double _jobScore(UniversalDeal a, UniversalDeal b){if(!_isWorkDeal(a)||!_isWorkDeal(b))return 0;final e=a.intent==DealIntent.needWorker?a:b,w=a.intent==DealIntent.seekWork?a:b;var s=0.0;final es=_normalized(e.dynamicFields['skill']?.toString()),ws=_normalized(w.dynamicFields['skill']?.toString());if(es.isNotEmpty&&es==ws)s+=12;final et=_normalized(e.dynamicFields['jobType']?.toString()),wt=_normalized(w.dynamicFields['jobType']?.toString());if(et.isNotEmpty&&et==wt)s+=4;final min=_number(e.dynamicFields['minExperienceYears']),exp=_number(w.dynamicFields['experienceYears']);if(min!=null&&exp!=null)s+=(exp-min).clamp(0,5);return s;}
  double _routeScore(UniversalDeal a, UniversalDeal b){if(!_isRouteDeal(a)||!_isRouteDeal(b))return 0;var s=0.0;if(_normalized(a.dynamicFields['from']?.toString())==_normalized(b.dynamicFields['from']?.toString()))s+=8;if(_normalized(a.dynamicFields['to']?.toString())==_normalized(b.dynamicFields['to']?.toString()))s+=8;if(_normalized(a.timing).isNotEmpty&&_normalized(a.timing)==_normalized(b.timing))s+=4;return s;}
  double _rentalScore(UniversalDeal a, UniversalDeal b){if(!_isRentalPair(a,b))return 0;var s=0.0;if(_normalized(a.dynamicFields['rentalType']?.toString())==_normalized(b.dynamicFields['rentalType']?.toString()))s+=8;if(_normalized(a.dynamicFields['startDate']?.toString()).isNotEmpty&&_normalized(a.dynamicFields['startDate']?.toString())==_normalized(b.dynamicFields['startDate']?.toString()))s+=4;return s;}
  double _appointmentScore(UniversalDeal a, UniversalDeal b){if(!_isAppointmentPair(a,b))return 0;var s=0.0;if(_normalized(a.dynamicFields['speciality']?.toString())==_normalized(b.dynamicFields['speciality']?.toString()))s+=8;if(_normalized(a.dynamicFields['slot']?.toString()).isNotEmpty&&_normalized(a.dynamicFields['slot']?.toString())==_normalized(b.dynamicFields['slot']?.toString()))s+=6;return s;}
  bool _isWorkDeal(UniversalDeal d)=>d.intent==DealIntent.needWorker||d.intent==DealIntent.seekWork;
  bool _isRouteDeal(UniversalDeal d)=>d.intent==DealIntent.needRide||d.intent==DealIntent.offerRide||d.intent==DealIntent.sendParcel||d.intent==DealIntent.deliverParcel;
  bool _isRidePair(UniversalDeal a,UniversalDeal b)=>{a.intent,b.intent}.contains(DealIntent.needRide)&&{a.intent,b.intent}.contains(DealIntent.offerRide);
  bool _isParcelPair(UniversalDeal a,UniversalDeal b)=>{a.intent,b.intent}.contains(DealIntent.sendParcel)&&{a.intent,b.intent}.contains(DealIntent.deliverParcel);
  bool _isRentalPair(UniversalDeal a,UniversalDeal b)=>{a.intent,b.intent}.contains(DealIntent.rent)&&{a.intent,b.intent}.contains(DealIntent.offerRental);
  bool _isAppointmentPair(UniversalDeal a,UniversalDeal b)=>{a.intent,b.intent}.contains(DealIntent.bookAppointment)&&{a.intent,b.intent}.contains(DealIntent.offerAppointment);
  bool _sameMeaning(String? l,String? r){final a=_normalized(l),b=_normalized(r);return a.isEmpty||b.isEmpty||a==b||a.contains(b)||b.contains(a);}
  double? _number(Object? v){if(v is num)return v.toDouble();final m=RegExp(r'-?[0-9]+(?:\.[0-9]+)?').firstMatch(v?.toString().trim()??'');return double.tryParse(m?.group(0)??'');}
  bool _locationCompatible(UniversalDeal a,UniversalDeal b,double? d){if(_isRouteDeal(a)&&_isRouteDeal(b))return true;if(a.fulfilment=='online'||b.fulfilment=='online')return true;if(d!=null){final limits=<double>[if(a.location.radiusKm!=null&&a.location.radiusKm!>0)a.location.radiusKm!,if(b.location.radiusKm!=null&&b.location.radiusKm!>0)b.location.radiusKm!];return limits.isEmpty||d<=limits.reduce(math.min);}final l=_normalized(a.location.label),r=_normalized(b.location.label);return l.isEmpty||r.isEmpty||l==r||l.contains(r)||r.contains(l);}
  double? _distanceKm(DealLocation a,DealLocation b){if(a.latitude==null||a.longitude==null||b.latitude==null||b.longitude==null)return null;const er=6371.0;final l1=_radians(a.latitude!),l2=_radians(b.latitude!),dl=_radians(b.latitude!-a.latitude!),dn=_radians(b.longitude!-a.longitude!);final h=math.sin(dl/2)*math.sin(dl/2)+math.cos(l1)*math.cos(l2)*math.sin(dn/2)*math.sin(dn/2);return er*2*math.atan2(math.sqrt(h),math.sqrt(1-h));}
  double _radians(double d)=>d*math.pi/180;
  String _normalized(String? v)=>(v??'').trim().toLowerCase().replaceAll(RegExp(r'\s+'),' ');
}
