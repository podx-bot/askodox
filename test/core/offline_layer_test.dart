import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/offline/offline_models.dart';
import 'package:podx/core/offline/offline_services.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/startup/startup_controller.dart';
import 'package:podx/core/sync/sync_models.dart';

void main() {
  group('startup and connectivity', () {
    test('restores session and preferences before ready', () async { final service = MockConnectivityService(); final controller = StartupController(service); final order = <String>[]; await controller.initialize(restoreSession: () async => order.add('session'), restorePreferences: () async => order.add('preferences')); expect(order, ['session', 'preferences']); expect(controller.state.phase, StartupPhase.ready); });
    test('starts offline and publishes connectivity changes', () async { final service = MockConnectivityService(ConnectivityStatus.offline); final controller = StartupController(service); await controller.initialize(); expect(controller.state.phase, StartupPhase.offlineReady); expectLater(service.changes, emits(ConnectivityStatus.online)); service.setStatus(ConnectivityStatus.online); });
    test('restoration failure is recoverable', () async { final controller = StartupController(MockConnectivityService()); await controller.initialize(restoreSession: () => throw StateError('corrupt')); expect(controller.state.phase, StartupPhase.recoverableError); });
  });

  group('cache and offline repository', () {
    test('records misses, hits, expiry, and stale offline fallback', () async { final cache = MemoryCacheRepository(); expect(await cache.read<String>('x'), isNull); await cache.write('x', 'cached', ttl: Duration.zero); expect((await cache.read<String>('x'))!.value, 'cached'); expect(await cache.isExpired('x'), isTrue); expect(cache.hits, 1); expect(cache.misses, 1); final connectivity = MockConnectivityService(ConnectivityStatus.offline); final result = await OfflineFirstRepository(cache, connectivity).read<String>(key: 'x', remote: () async => 'remote', ttl: const Duration(hours: 1)); expect(result.value, 'cached'); expect(result.isStale, isTrue); });
  });

  group('sync and conflicts', () {
    LocalChange change(String id) => LocalChange(entityType: 'watchlistItem', entityId: id, operation: 'create', payload: {'id': id}, createdAt: DateTime(2026));
    test('deduplicates queue and syncs successfully', () async { final service = MockSyncService(); await service.enqueue(change('1')); await service.enqueue(change('1')); expect(service.queue, hasLength(1)); await service.sync(); expect(service.queue.single.status, SyncItemStatus.synced); });
    test('failed sync remains retryable', () async { final service = MockSyncService(failNext: true); await service.enqueue(change('2')); await service.sync(); expect(service.queue.single.status, SyncItemStatus.failed); await service.retry(service.queue.single.id); expect(service.queue.single.status, SyncItemStatus.synced); });
    test('offline item waits and conflict is retained', () async { final service = MockSyncService(isOnline: false); await service.enqueue(change('3')); await service.sync(); expect(service.queue.single.status, SyncItemStatus.waitingForConnection); service.isOnline = true; service.conflictNext = true; await service.sync(); expect(service.queue.single.status, SyncItemStatus.conflict); });
    test('resolves by latest timestamp and merges fields', () { final conflict = SyncConflict(id: 'c', itemId: 'i', localValue: {'price': 120, 'stock': 3}, remoteValue: {'price': 125, 'name': 'Rice'}, localUpdatedAt: DateTime(2026, 1, 1), remoteUpdatedAt: DateTime(2026, 1, 2), recommendedStrategy: ConflictResolutionStrategy.useLatestTimestamp); final resolver = MockConflictResolver(); expect(resolver.resolve(conflict, ConflictResolutionStrategy.useLatestTimestamp)['price'], 125); expect(resolver.resolve(conflict, ConflictResolutionStrategy.mergeFields), {'price': 120, 'name': 'Rice', 'stock': 3}); });
  });

  test('optimistic update can roll back', () { final update = OptimisticUpdate(id: 'price', previous: 100, optimistic: 110, createdAt: DateTime(2026)); expect(update.rollback(), 100); });
  test('safe migration keeps searches and advances version', () async { final store = MemoryLocalStore(); await store.write(LocalKeys.recentSearches, ['rice']); final result = await MockMigrationService(store).migrate(); expect(result.success, isTrue); expect(result.version, 2); expect(await store.read<List<dynamic>>(LocalKeys.recentSearches), ['rice']); });
  test('storage clearing preserves preferences by default', () async { final store = MemoryLocalStore(); await store.write(LocalKeys.language, 'te'); await store.write(LocalKeys.recentSearches, ['rice']); final queue = MemorySyncQueueRepository(); final service = MockStorageManagementService(store, MemoryCacheRepository(), queue); await service.clearAllLocalData(); expect(await store.read<String>(LocalKeys.language), 'te'); expect(await store.read<List<dynamic>>(LocalKeys.recentSearches), isNull); });
}
