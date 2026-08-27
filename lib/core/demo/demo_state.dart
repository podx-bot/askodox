import 'demo_accounts.dart';

enum DemoRecordType { request, listing, order, history }

class DemoRecord {
  const DemoRecord({
    required this.id,
    required this.module,
    required this.party,
    required this.type,
    required this.title,
    required this.status,
  });

  final String id;
  final DemoModule module;
  final DemoParty party;
  final DemoRecordType type;
  final String title;
  final String status;
}

class DemoSeedData {
  const DemoSeedData._();

  static const records = <DemoRecord>[
    DemoRecord(id: 'commerce-listing-1', module: DemoModule.commerce, party: DemoParty.a, type: DemoRecordType.listing, title: 'Fresh chicken 1 kg', status: 'available'),
    DemoRecord(id: 'commerce-request-1', module: DemoModule.commerce, party: DemoParty.b, type: DemoRecordType.request, title: 'Need 2 kg chicken nearby', status: 'matched'),
    DemoRecord(id: 'jobs-listing-1', module: DemoModule.jobs, party: DemoParty.a, type: DemoRecordType.listing, title: 'Computer operator vacancy', status: 'open'),
    DemoRecord(id: 'jobs-request-1', module: DemoModule.jobs, party: DemoParty.b, type: DemoRecordType.request, title: 'Looking for computer operator work', status: 'matched'),
    DemoRecord(id: 'services-listing-1', module: DemoModule.services, party: DemoParty.a, type: DemoRecordType.listing, title: 'AC repair service', status: 'available'),
    DemoRecord(id: 'services-order-1', module: DemoModule.services, party: DemoParty.b, type: DemoRecordType.order, title: 'AC repair booking', status: 'confirmed'),
    DemoRecord(id: 'rides-listing-1', module: DemoModule.rides, party: DemoParty.a, type: DemoRecordType.listing, title: 'Vijayawada to Bhimavaram ride', status: '3 seats available'),
    DemoRecord(id: 'rides-order-1', module: DemoModule.rides, party: DemoParty.b, type: DemoRecordType.order, title: 'One seat to Bhimavaram', status: 'confirmed'),
    DemoRecord(id: 'parcel-listing-1', module: DemoModule.parcel, party: DemoParty.a, type: DemoRecordType.listing, title: 'Nearby delivery rider online', status: 'available'),
    DemoRecord(id: 'parcel-order-1', module: DemoModule.parcel, party: DemoParty.b, type: DemoRecordType.order, title: 'City parcel delivery', status: 'assigned'),
    DemoRecord(id: 'appointments-listing-1', module: DemoModule.appointments, party: DemoParty.a, type: DemoRecordType.listing, title: 'Tomorrow 11:00 appointment slot', status: 'available'),
    DemoRecord(id: 'appointments-order-1', module: DemoModule.appointments, party: DemoParty.b, type: DemoRecordType.order, title: 'Tomorrow appointment', status: 'booked'),
    DemoRecord(id: 'catering-listing-1', module: DemoModule.catering, party: DemoParty.a, type: DemoRecordType.listing, title: '100 guest catering quotation', status: 'quoted'),
    DemoRecord(id: 'catering-request-1', module: DemoModule.catering, party: DemoParty.b, type: DemoRecordType.request, title: 'Catering for 100 guests', status: 'quotes received'),
    DemoRecord(id: 'local-listing-1', module: DemoModule.localDiscovery, party: DemoParty.a, type: DemoRecordType.listing, title: 'Local shop catalog', status: 'open'),
    DemoRecord(id: 'local-request-1', module: DemoModule.localDiscovery, party: DemoParty.b, type: DemoRecordType.request, title: 'Find nearby seller', status: 'matched'),
  ];
}

class DemoStateStore {
  DemoStateStore() : _records = List<DemoRecord>.from(DemoSeedData.records);

  List<DemoRecord> _records;

  List<DemoRecord> get records => List<DemoRecord>.unmodifiable(_records);

  List<DemoRecord> forModule(DemoModule module) =>
      _records.where((record) => record.module == module).toList(growable: false);

  void add(DemoRecord record) => _records = [..._records, record];

  void removeById(String id) =>
      _records = _records.where((record) => record.id != id).toList(growable: false);

  void reset() => _records = List<DemoRecord>.from(DemoSeedData.records);
}
