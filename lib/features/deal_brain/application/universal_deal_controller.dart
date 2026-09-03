import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/universal_deal.dart';
import 'universal_deal_brain.dart';

class UniversalDealSession {
  const UniversalDealSession({this.deal, this.lastQuestion, this.completed = false});
  final UniversalDeal? deal;
  final String? lastQuestion;
  final bool completed;
  UniversalDealSession copyWith({UniversalDeal? deal, String? lastQuestion, bool? completed}) => UniversalDealSession(deal: deal ?? this.deal, lastQuestion: lastQuestion, completed: completed ?? this.completed);
}

final universalDealControllerProvider = StateNotifierProvider<UniversalDealController, UniversalDealSession>((ref) => UniversalDealController());

class UniversalDealController extends StateNotifier<UniversalDealSession> {
  UniversalDealController() : super(const UniversalDealSession()) { unawaited(_restore()); }
  static const _storageKey = 'askodox.active_universal_deal.v1';
  final UniversalDealBrain _brain = const UniversalDealBrain();

  void start(String text) { final value=text.trim(); if(value.isEmpty)return; final current=state.deal; if(current!=null&&current.missingForMatch.isNotEmpty){answer(value);return;} _setSession(_sessionFor(_brain.capture(value))); }
  void answer(String text) {
    final value=text.trim(); if(value.isEmpty)return; final current=state.deal; if(current==null){_setSession(_sessionFor(_brain.capture(value)));return;} final missing=current.missingForMatch; if(missing.isEmpty)return; final field=missing.first; final dynamic=Map<String,Object?>.from(current.dynamicFields); var next=current;
    switch(field){case 'subject': next=current.copyWith(subject:value); break; case 'quantity': final parsed=_quantity(value); if(parsed!=null){next=current.copyWith(quantity:parsed.$1,unit:parsed.$2);}else{dynamic['quantityText']=value;next=current.copyWith(quantity:1,unit:value,dynamicFields:dynamic);} break; case 'freshness': case 'cut': case 'chickenPreference': dynamic[field]=value;next=current.copyWith(dynamicFields:dynamic);break; case 'fulfilment':next=current.copyWith(fulfilment:_fulfilment(value)??value);break; case 'location':next=current.copyWith(location:DealLocation(label:value,latitude:current.location.latitude,longitude:current.location.longitude,radiusKm:current.location.radiusKm));break;case 'timing':next=current.copyWith(timing:value);break;case 'from':case 'to':case 'skill':dynamic[field]=value;next=current.copyWith(dynamicFields:dynamic);break;default:dynamic[field]=value;next=current.copyWith(dynamicFields:dynamic);} _setSession(_sessionFor(next));
  }

  void attachMedia({required String path, required String name, String kind='image'}) { final current=state.deal;if(current==null||path.trim().isEmpty)return;final dynamic=Map<String,Object?>.from(current.dynamicFields);dynamic['attachment']={'kind':kind,'name':name,'path':path,'analysisStatus':'analyzing'};_setSession(_sessionFor(current.copyWith(dynamicFields:dynamic))); }
  void markVisionAnalysisFailed() { final current=state.deal;if(current==null)return;final dynamic=Map<String,Object?>.from(current.dynamicFields);final attachment=dynamic['attachment'];if(attachment is Map){final next=Map<String,Object?>.from(attachment.cast<String,Object?>());next['analysisStatus']='failed';dynamic['attachment']=next;_setSession(_sessionFor(current.copyWith(dynamicFields:dynamic)));} }
  void mergeVisionAnalysis(Map<String,dynamic> analysis) { final current=state.deal;if(current==null||analysis.isEmpty)return;final dynamic=Map<String,Object?>.from(current.dynamicFields);dynamic['visionAnalysis']=Map<String,Object?>.from(analysis);final attachment=dynamic['attachment'];if(attachment is Map){final next=Map<String,Object?>.from(attachment.cast<String,Object?>());next['analysisStatus']='ready';dynamic['attachment']=next;}final hints=analysis['deal_hints'];final hintMap=hints is Map?hints.cast<Object?,Object?>():const <Object?,Object?>{};String? hint(String key){final value=hintMap[key]?.toString().trim();return value==null||value.isEmpty||value.toLowerCase()=='null'?null:value;}final detectedSubject=analysis['detected_subject']?.toString().trim();final categoryHint=analysis['category_hint']?.toString().trim();final subjectHint=hint('subject')??((detectedSubject==null||detectedSubject.isEmpty||detectedSubject.toLowerCase()=='null')?null:detectedSubject);final category=hint('category')??((categoryHint==null||categoryHint.isEmpty||categoryHint.toLowerCase()=='null')?null:categoryHint);final next=current.copyWith(subject:_missing(current.subject)?subjectHint:current.subject,category:_missing(current.category)?category:current.category,variant:_missing(current.variant)?hint('variant'):current.variant,size:_missing(current.size)?hint('size'):current.size,model:_missing(current.model)?hint('model'):current.model,quality:_missing(current.quality)?hint('quality'):current.quality,dynamicFields:dynamic);_setSession(_sessionFor(next)); }
  bool _missing(String? value)=>value==null||value.trim().isEmpty;
  void reset(){state=const UniversalDealSession();unawaited(_clearPersisted());}
  UniversalDealSession _sessionFor(UniversalDeal deal)=>UniversalDealSession(deal:deal,lastQuestion:_questionFor(deal.missingForMatch.firstOrNull),completed:deal.readyToMatch);
  (double,String)? _quantity(String value){final lower=value.toLowerCase();final match=RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(kg|kgs|g|gm|grams|piece|pieces|pcs)?').firstMatch(lower);final amount=double.tryParse(match?.group(1)??'');if(amount==null)return null;return(amount,match?.group(2)??'kg');}
  String? _fulfilment(String value){final lower=value.toLowerCase();if(lower.contains('delivery')||lower.contains('డెలివరీ'))return'delivery';if(lower.contains('pickup')||lower.contains('pick up')||lower.contains('పికప్'))return'pickup';if(lower.contains('online'))return'online';return null;}
  void _setSession(UniversalDealSession next){state=next;unawaited(_persist(next));}
  Future<void> _restore() async{try{final prefs=await SharedPreferences.getInstance();final raw=prefs.getString(_storageKey);if(raw==null||raw.isEmpty||!mounted)return;final decoded=jsonDecode(raw);if(decoded is! Map<String,dynamic>)return;final dealJson=decoded['deal'];if(dealJson is! Map<String,dynamic>)return;final deal=_dealFromJson(dealJson);if(!mounted)return;state=_sessionFor(deal);}catch(_){await _clearPersisted();}}
  Future<void> _persist(UniversalDealSession session)async{final deal=session.deal;if(deal==null)return _clearPersisted();try{final prefs=await SharedPreferences.getInstance();await prefs.setString(_storageKey,jsonEncode({'deal':_dealToJson(deal)}));}catch(_){}}
  Future<void> _clearPersisted()async{try{final prefs=await SharedPreferences.getInstance();await prefs.remove(_storageKey);}catch(_){}}
  Map<String,Object?> _dealToJson(UniversalDeal d)=>{'rawText':d.rawText,'intent':d.intent.name,'partyA':_partyToJson(d.partyA),'partyB':_partyToJson(d.partyB),'subject':d.subject,'category':d.category,'quantity':d.quantity,'unit':d.unit,'price':d.price,'priceBasis':d.priceBasis,'quality':d.quality,'variant':d.variant,'size':d.size,'weight':d.weight,'model':d.model,'availability':d.availability,'fulfilment':d.fulfilment,'location':{'label':d.location.label,'latitude':d.location.latitude,'longitude':d.location.longitude,'radiusKm':d.location.radiusKm},'timing':d.timing,'dynamicFields':d.dynamicFields,'status':d.status.name};
  Map<String,Object?> _partyToJson(DealPartyRequirement p)=>{'side':p.side.name,'role':p.role,'action':p.action};
  UniversalDeal _dealFromJson(Map<String,dynamic> json){final location=json['location'] is Map?Map<String,dynamic>.from(json['location'] as Map):<String,dynamic>{};final dynamic=json['dynamicFields'] is Map?Map<String,Object?>.from(json['dynamicFields'] as Map):<String,Object?>{};return UniversalDeal(rawText:'${json['rawText']??''}',intent:DealIntent.values.firstWhere((e)=>e.name==json['intent'],orElse:()=>DealIntent.unknown),partyA:_partyFromJson(json['partyA']),partyB:_partyFromJson(json['partyB']),subject:json['subject']?.toString(),category:json['category']?.toString(),quantity:(json['quantity'] as num?)?.toDouble(),unit:json['unit']?.toString(),price:(json['price'] as num?)?.toDouble(),priceBasis:json['priceBasis']?.toString(),quality:json['quality']?.toString(),variant:json['variant']?.toString(),size:json['size']?.toString(),weight:json['weight']?.toString(),model:json['model']?.toString(),availability:json['availability']?.toString(),fulfilment:json['fulfilment']?.toString(),location:DealLocation(label:location['label']?.toString(),latitude:(location['latitude'] as num?)?.toDouble(),longitude:(location['longitude'] as num?)?.toDouble(),radiusKm:(location['radiusKm'] as num?)?.toDouble()),timing:json['timing']?.toString(),dynamicFields:dynamic,status:DealStatus.values.firstWhere((e)=>e.name==json['status'],orElse:()=>DealStatus.collecting));}
  DealPartyRequirement _partyFromJson(Object? raw){final json=raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};return DealPartyRequirement(side:DealPartySide.values.firstWhere((e)=>e.name==json['side'],orElse:()=>DealPartySide.seeker),role:'${json['role']??'user'}',action:'${json['action']??'connect'}');}
  String? _questionFor(String? field)=>field==null?null:switch(field){'subject'=>'What do you need or offer?','quantity'=>'How much / how many?','freshness'=>'Fresh or frozen?','cut'=>'Which cut or type?','chickenPreference'=>'Any preference like skinless/curry cut?','fulfilment'=>'Pickup, delivery, or online?','location'=>'Which area or location?','timing'=>'When do you need it?','from'=>'Where are you starting from?','to'=>'Where are you going?','skill'=>'Which job/skill are you looking for?',_=>'Please tell me $field.'};
}

extension _FirstOrNull<T> on List<T>{T? get firstOrNull=>isEmpty?null:first;}
