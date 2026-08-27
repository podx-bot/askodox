import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/demo/demo_accounts.dart';
import 'package:podx/core/demo/demo_state.dart';

void main() {
  test('every demo module has seeded records for both parties', () {
    for (final module in DemoModule.values) {
      final records = DemoSeedData.records.where((record) => record.module == module).toList();
      expect(records.any((record) => record.party == DemoParty.a), isTrue, reason: '${module.name} missing Party A seed');
      expect(records.any((record) => record.party == DemoParty.b), isTrue, reason: '${module.name} missing Party B seed');
    }
  });

  test('demo seed record IDs are unique', () {
    final ids = DemoSeedData.records.map((record) => record.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('demo state can mutate and reset to deterministic defaults', () {
    final store = DemoStateStore();
    final originalLength = store.records.length;

    store.add(const DemoRecord(
      id: 'temporary-demo-record',
      module: DemoModule.commerce,
      party: DemoParty.b,
      type: DemoRecordType.history,
      title: 'Temporary test history',
      status: 'done',
    ));
    store.removeById('commerce-listing-1');
    expect(store.records.length, originalLength);
    expect(store.records.any((record) => record.id == 'temporary-demo-record'), isTrue);
    expect(store.records.any((record) => record.id == 'commerce-listing-1'), isFalse);

    store.reset();
    expect(store.records.length, originalLength);
    expect(store.records.any((record) => record.id == 'temporary-demo-record'), isFalse);
    expect(store.records.any((record) => record.id == 'commerce-listing-1'), isTrue);
  });
}
