enum SyncOperation { create, update, delete, archive, restore }

enum SyncEntityType {
  watchlistItem,
  buyerPreference,
  savedLocation,
  productRequest,
  sellerListing,
  priceUpdate,
  stockUpdate,
  alertPreference,
  shopFollow,
  sellerResponse,
  supportCaseDraft,
}

enum SyncItemStatus { pending, syncing, synced, failed, waitingForConnection, conflict, cancelled }
enum ConflictStatus { none, localWins, remoteWins, needsResolution }
enum ConflictResolutionStrategy { keepLocal, keepRemote, useLatestTimestamp, mergeFields, askUser, adminReviewRequired }

class LocalChange {
  const LocalChange({required this.entityType, required this.entityId, required this.operation, required this.payload, required this.createdAt});
  final String entityType, entityId, operation;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

class SyncQueueItem {
  const SyncQueueItem({required this.id, required this.change, this.status = SyncItemStatus.pending, this.retryCount = 0, this.lastAttempt, this.failureReason, this.conflictStatus = ConflictStatus.none});
  final String id;
  final LocalChange change;
  final SyncItemStatus status;
  final int retryCount;
  final DateTime? lastAttempt;
  final String? failureReason;
  String? get lastError => failureReason;
  final ConflictStatus conflictStatus;
  SyncQueueItem copyWith({SyncItemStatus? status, int? retryCount, DateTime? lastAttempt, String? failureReason, ConflictStatus? conflictStatus}) => SyncQueueItem(id: id, change: change, status: status ?? this.status, retryCount: retryCount ?? this.retryCount, lastAttempt: lastAttempt ?? this.lastAttempt, failureReason: failureReason, conflictStatus: conflictStatus ?? this.conflictStatus);
}

class SyncConflict {
  const SyncConflict({required this.id, required this.itemId, required this.localValue, required this.remoteValue, required this.localUpdatedAt, required this.remoteUpdatedAt, required this.recommendedStrategy, this.selectedStrategy});
  final String id, itemId;
  final Map<String, Object?> localValue, remoteValue;
  final DateTime localUpdatedAt, remoteUpdatedAt;
  final ConflictResolutionStrategy recommendedStrategy;
  final ConflictResolutionStrategy? selectedStrategy;
}

class SyncStatus {
  const SyncStatus({this.pendingCount = 0, this.failedCount = 0, this.isSyncing = false, this.lastSyncedAt, this.conflictStatus = ConflictStatus.none});
  final int pendingCount, failedCount;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final ConflictStatus conflictStatus;
}

class SyncRunResult {
  const SyncRunResult({required this.startedAt, required this.finishedAt, required this.synced, required this.failed, required this.conflicts, this.cancelled = false});
  final DateTime startedAt, finishedAt;
  final int synced, failed, conflicts;
  final bool cancelled;
  Duration get duration => finishedAt.difference(startedAt);
}

abstract interface class SyncQueueRepository {
  List<SyncQueueItem> get items;
  Future<void> add(SyncQueueItem item);
  Future<void> update(SyncQueueItem item);
  Future<void> remove(String id);
  Future<void> clearCompleted();
  Future<void> clear();
}

class MemorySyncQueueRepository implements SyncQueueRepository {
  final List<SyncQueueItem> _items = [];
  @override List<SyncQueueItem> get items => List.unmodifiable(_items);
  @override Future<void> add(SyncQueueItem item) async { if (!_items.any((e) => e.id == item.id)) _items.add(item); }
  @override Future<void> update(SyncQueueItem item) async { final i = _items.indexWhere((e) => e.id == item.id); if (i >= 0) _items[i] = item; }
  @override Future<void> remove(String id) async => _items.removeWhere((e) => e.id == id);
  @override Future<void> clearCompleted() async => _items.removeWhere((e) => e.status == SyncItemStatus.synced || e.status == SyncItemStatus.cancelled);
  @override Future<void> clear() async => _items.clear();
}

abstract interface class SyncService {
  SyncStatus get status;
  List<SyncQueueItem> get queue;
  Future<void> enqueue(LocalChange change);
  Future<SyncStatus> sync();
  Future<void> retry(String id);
  Future<void> remove(String id);
  Future<void> clearCompleted();
}

class MockSyncService implements SyncService {
  MockSyncService({MemorySyncQueueRepository? repository, this.isOnline = true, this.failNext = false, this.conflictNext = false}) : repository = repository ?? MemorySyncQueueRepository();
  final MemorySyncQueueRepository repository;
  bool isOnline, failNext, conflictNext;
  bool _running = false;
  DateTime? _last;
  @override List<SyncQueueItem> get queue => repository.items;
  @override SyncStatus get status => SyncStatus(pendingCount: queue.where((e) => e.status == SyncItemStatus.pending || e.status == SyncItemStatus.waitingForConnection).length, failedCount: queue.where((e) => e.status == SyncItemStatus.failed).length, isSyncing: _running, lastSyncedAt: _last, conflictStatus: queue.any((e) => e.status == SyncItemStatus.conflict) ? ConflictStatus.needsResolution : ConflictStatus.none);
  @override Future<void> enqueue(LocalChange change) => repository.add(SyncQueueItem(id: '${change.entityType}-${change.entityId}-${change.operation}', change: change));
  @override Future<SyncStatus> sync() async {
    if (_running) return status;
    _running = true;
    try {
      for (final item in [...queue]) {
        if (item.status == SyncItemStatus.synced || item.status == SyncItemStatus.cancelled) continue;
        if (!isOnline) { await repository.update(item.copyWith(status: SyncItemStatus.waitingForConnection)); continue; }
        await repository.update(item.copyWith(status: SyncItemStatus.syncing, lastAttempt: DateTime.now()));
        if (conflictNext) { conflictNext = false; await repository.update(item.copyWith(status: SyncItemStatus.conflict, retryCount: item.retryCount + 1, conflictStatus: ConflictStatus.needsResolution, failureReason: 'Conflicting remote change')); continue; }
        if (failNext) { failNext = false; await repository.update(item.copyWith(status: SyncItemStatus.failed, retryCount: item.retryCount + 1, failureReason: 'Mock synchronization failure')); continue; }
        await repository.update(item.copyWith(status: SyncItemStatus.synced));
      }
      if (!queue.any((e) => e.status == SyncItemStatus.failed || e.status == SyncItemStatus.conflict) && isOnline) _last = DateTime.now();
      return status;
    } finally { _running = false; }
  }
  @override Future<void> retry(String id) async { final item = queue.where((e) => e.id == id).firstOrNull; if (item != null) await repository.update(item.copyWith(status: SyncItemStatus.pending)); await sync(); }
  @override Future<void> remove(String id) => repository.remove(id);
  @override Future<void> clearCompleted() => repository.clearCompleted();
}

abstract interface class ConflictResolver { Map<String, Object?> resolve(SyncConflict conflict, ConflictResolutionStrategy strategy); }
class MockConflictResolver implements ConflictResolver {
  @override Map<String, Object?> resolve(SyncConflict c, ConflictResolutionStrategy strategy) {
    switch (strategy) {
      case ConflictResolutionStrategy.keepLocal: return c.localValue;
      case ConflictResolutionStrategy.keepRemote: return c.remoteValue;
      case ConflictResolutionStrategy.useLatestTimestamp: return c.localUpdatedAt.isAfter(c.remoteUpdatedAt) ? c.localValue : c.remoteValue;
      case ConflictResolutionStrategy.mergeFields: return {...c.remoteValue, ...c.localValue};
      case ConflictResolutionStrategy.askUser:
      case ConflictResolutionStrategy.adminReviewRequired: return {};
    }
  }
}
