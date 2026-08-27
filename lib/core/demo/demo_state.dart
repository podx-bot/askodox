import 'demo_accounts.dart';

enum DemoRecordType { request, listing, order, history }
enum DemoJourneyStage { open, matched, accepted, completed }

class DemoRecord {
  const DemoRecord({required this.id, required this.module, required this.party, required this.type, required this.title, required this.status});
  final String id; final DemoModule module; final DemoParty party; final DemoRecordType type; final String title; final String status;
  DemoRecord copyWith({DemoRecordType? type, String? status}) => DemoRecord(id:id,module:module,party:party,type:type??this.type,title:title,status:status??this.status);
}

class DemoSeedData {
  const DemoSeedData._();
  static const records = <DemoRecord>[
    DemoRecord(id:'commerce-listing-1',module:DemoModule.commerce,party:DemoParty.a,type:DemoRecordType.listing,title:'Fresh chicken 1 kg',status:'available'), DemoRecord(id:'commerce-request-1',module:DemoModule.commerce,party:DemoParty.b,type:DemoRecordType.request,title:'Need 2 kg chicken nearby',status:'open'),
    DemoRecord(id:'jobs-listing-1',module:DemoModule.jobs,party:DemoParty.a,type:DemoRecordType.listing,title:'Computer operator vacancy',status:'open'), DemoRecord(id:'jobs-request-1',module:DemoModule.jobs,party:DemoParty.b,type:DemoRecordType.request,title:'Looking for computer operator work',status:'open'),
    DemoRecord(id:'services-listing-1',module:DemoModule.services,party:DemoParty.a,type:DemoRecordType.listing,title:'AC repair service',status:'available'), DemoRecord(id:'services-order-1',module:DemoModule.services,party:DemoParty.b,type:DemoRecordType.request,title:'AC repair booking',status:'open'),
    DemoRecord(id:'rides-listing-1',module:DemoModule.rides,party:DemoParty.a,type:DemoRecordType.listing,title:'Vijayawada to Bhimavaram ride',status:'3 seats available'), DemoRecord(id:'rides-order-1',module:DemoModule.rides,party:DemoParty.b,type:DemoRecordType.request,title:'One seat to Bhimavaram',status:'open'),
    DemoRecord(id:'parcel-listing-1',module:DemoModule.parcel,party:DemoParty.a,type:DemoRecordType.listing,title:'Nearby delivery rider online',status:'available'), DemoRecord(id:'parcel-order-1',module:DemoModule.parcel,party:DemoParty.b,type:DemoRecordType.request,title:'City parcel delivery',status:'open'),
    DemoRecord(id:'appointments-listing-1',module:DemoModule.appointments,party:DemoParty.a,type:DemoRecordType.listing,title:'Tomorrow 11:00 appointment slot',status:'available'), DemoRecord(id:'appointments-order-1',module:DemoModule.appointments,party:DemoParty.b,type:DemoRecordType.request,title:'Tomorrow appointment',status:'open'),
    DemoRecord(id:'catering-listing-1',module:DemoModule.catering,party:DemoParty.a,type:DemoRecordType.listing,title:'100 guest catering quotation',status:'available'), DemoRecord(id:'catering-request-1',module:DemoModule.catering,party:DemoParty.b,type:DemoRecordType.request,title:'Catering for 100 guests',status:'open'),
    DemoRecord(id:'local-listing-1',module:DemoModule.localDiscovery,party:DemoParty.a,type:DemoRecordType.listing,title:'Local shop catalog',status:'open'), DemoRecord(id:'local-request-1',module:DemoModule.localDiscovery,party:DemoParty.b,type:DemoRecordType.request,title:'Find nearby seller',status:'open'),
  ];
}

class DemoStateStore {
  DemoStateStore():_records=List<DemoRecord>.from(DemoSeedData.records);
  List<DemoRecord> _records;
  List<DemoRecord> get records=>List.unmodifiable(_records);
  List<DemoRecord> forModule(DemoModule module)=>_records.where((r)=>r.module==module).toList(growable:false);
  void add(DemoRecord record)=>_records=[..._records,record];
  void removeById(String id)=>_records=_records.where((r)=>r.id!=id).toList(growable:false);
  DemoJourneyStage stageFor(DemoModule module){ final statuses=forModule(module).map((r)=>r.status).toSet(); if(statuses.contains('completed')) return DemoJourneyStage.completed; if(statuses.contains('accepted')) return DemoJourneyStage.accepted; if(statuses.contains('matched')) return DemoJourneyStage.matched; return DemoJourneyStage.open; }
  void advanceJourney(DemoModule module){ final stage=stageFor(module); final next=switch(stage){DemoJourneyStage.open=>'matched',DemoJourneyStage.matched=>'accepted',DemoJourneyStage.accepted=>'completed',DemoJourneyStage.completed=>'completed'}; _records=[for(final r in _records) if(r.module==module && r.party==DemoParty.b) r.copyWith(type: next=='completed'?DemoRecordType.history:(next=='accepted'?DemoRecordType.order:r.type),status:next) else r]; }
  void reset()=>_records=List<DemoRecord>.from(DemoSeedData.records);
}
class DemoRuntime { const DemoRuntime._(); static final DemoStateStore state=DemoStateStore(); }
