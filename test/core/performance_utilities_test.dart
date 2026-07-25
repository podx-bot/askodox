import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/offline/offline_services.dart';
import 'package:podx/core/pagination/pagination.dart';

void main() {
  test('pagination prevents duplicates while retaining stable order', () async { final paginator = MockPaginator<int>([1, 2, 2, 3, 4], pageSize: 3); await paginator.loadInitial(); await paginator.loadMore(); expect(paginator.state.items, [1, 2, 3, 4]); expect(paginator.state.status, PaginationStatus.endOfList); });
  test('indexed search enforces minimum query and removes duplicates', () async { final index = MemorySearchIndexService<String>(); await index.prepare(['Red Rice', 'Rice Bran'], (item) => [item]); expect(await index.search('r'), isEmpty); expect(await index.search('ri'), ['Red Rice', 'Rice Bran']); });
  test('newer debounced search cancels previous result', () async { final index = MemorySearchIndexService<String>(); await index.prepare(['rice', 'wheat'], (item) => [item]); final old = index.search('ri'); final current = index.search('wh'); expect(await old, isEmpty); expect(await current, ['wheat']); });
}
