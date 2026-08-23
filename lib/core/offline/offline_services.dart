import 'dart:async';

import '../persistence/local_store.dart';
import '../sync/sync_models.dart';
import 'offline_models.dart';

abstract interface class ConnectivityService { ConnectivityStatus get current; Stream<ConnectivityStatus> get changes; Future<ConnectivityStatus> check(); }
class MockConnectivityService implements ConnectivityService {
  MockConnectivityService([this._current = ConnectivityStatus.online]);
  ConnectivityStatus _current;
  final _controller = StreamController<ConnectivityStatus>.broadcast();
  @override ConnectivityStatus get current => _current;
  @override Stream<ConnectivityStatus> get changes => _controller.stream;
  @override Future<ConnectivityStatus> check() async => _current;
  void setStatus(ConnectivityStatus status) { _current = status; _controller.add(status); }
  Future<void> dispose() => _controller.close();
}

abstract interface class CacheRepository {
  Future<CacheEntry<T>?> read<T>(String key);
  Future<void> write<T>(String key, T value, {required Duration ttl, int version});
  Future<void> remove(String key);
  Future<void> clear({bool staleOnly});
  Future<bool> isExpired(String key);
  Future<DateTime?> lastUpdated(String key);
  Future<void> migrate(int fromVersion, int toVersion);
  int get hits;
  int get misses;
}
class MemoryCacheRepository implements CacheRepository {
  final Map<String, CacheEntry<Object?>> _cache = {};
  int _hits = 0, _misses = 0;
  @override int get hits => _hits; @override int get misses => _misses;
  @override Future<CacheEntry<T>?> read<T>(String key) async {
    final value = _cache[key];
    if (value == null) { _misses++; return null; }
    final payload = value.value;
    if (payload is! T) { _misses++; return null; }
    _hits++;
    return CacheEntry<T>(value: payload, updatedAt: value.updatedAt, expiresAt: value.expiresAt, version: value.version);
  }
  @override Future<void> write<T>(String key, T value, {required Duration ttl, int version = 1}) async { final now = DateTime.now(); _cache[key] = CacheEntry<Object?>(value: value, updatedAt: now, expiresAt: now.add(ttl), version: version); }
  @override Future<void> remove(String key) async => _cache.remove(key);
  @override Future<void> clear({bool staleOnly = false}) async { if (!staleOnly) { _cache.clear(); return; } final now = DateTime.now(); _cache.removeWhere((_, value) => value.isExpired(now)); }
  @override Future<bool> isExpired(String key) async => _cache[key]?.isExpired(DateTime.now()) ?? true;
  @override Future<DateTime?> lastUpdated(String key) async => _cache[key]?.updatedAt;
  @override Future<void> migrate(int fromVersion, int toVersion) async { if (toVersion < fromVersion) throw ArgumentError('Cache downgrade is unsupported'); }
}

class OfflineReadResult<T> { const OfflineReadResult(this.value, {required this.fromCache, required this.isStale}); final T value; final bool fromCache, isStale; }
class OfflineFirstRepository {
  const OfflineFirstRepository(this.cache, this.connectivity);
  final CacheRepository cache; final ConnectivityService connectivity;
  Future<OfflineReadResult<T>> read<T>({required String key, required Future<T> Function() remote, required Duration ttl, CachePolicy policy = CachePolicy.cacheFirst}) async {
    final cached = policy == CachePolicy.noCache ? null : await cache.read<T>(key);
    final offline = connectivity.current != ConnectivityStatus.online;
    if (cached != null && (policy == CachePolicy.cacheFirst || policy == CachePolicy.localOnly || offline)) return OfflineReadResult(cached.value, fromCache: true, isStale: cached.isExpired(DateTime.now()) || offline);
    if (offline || policy == CachePolicy.localOnly) { if (cached != null) return OfflineReadResult(cached.value, fromCache: true, isStale: true); throw StateError('No offline copy is available'); }
    try { final value = await remote(); if (policy != CachePolicy.noCache) await cache.write(key, value, ttl: ttl); return OfflineReadResult(value, fromCache: false, isStale: false); } catch (_) { if (cached != null) return OfflineReadResult(cached.value, fromCache: true, isStale: true); rethrow; }
  }
}

abstract interface class MigrationService { LocalDataVersion get version; Future<MigrationResult> migrate(); Future<void> resetLocalData(); Future<void> backup(); }
class MockMigrationService implements MigrationService {
  MockMigrationService(this.store, {int initialVersion = 1}) : _version = initialVersion;
  final LocalStore store; int _version;
  @override LocalDataVersion get version => LocalDataVersion(current: 2, previous: _version);
  @override Future<MigrationResult> migrate() async { final log = <String>[]; try { if (_version < 2) { final searches = await store.read<List<dynamic>>(LocalKeys.recentSearches) ?? []; await store.write(LocalKeys.recentSearches, searches); log.add('v1→v2: normalized recent search list'); _version = 2; } return MigrationResult(success: true, version: _version, log: log); } catch (e) { return MigrationResult(success: false, version: _version, log: log, error: '$e'); } }
  @override Future<void> resetLocalData() => store.clear();
  @override Future<void> backup() async {}
}

abstract interface class StorageManagementService { Future<StorageUsage> usage(); Future<void> clearSearchHistory(); Future<void> clearAnalytics(); Future<void> clearStale(); Future<void> clearAllLocalData({bool includePreferences}); }
class MockStorageManagementService implements StorageManagementService {
  MockStorageManagementService(this.store, this.cache, this.queue);
  final LocalStore store; final CacheRepository cache; final SyncQueueRepository queue;
  @override Future<StorageUsage> usage() async => StorageUsage(cachedProducts: 48000, cachedShops: 12000, searchHistory: 1024, imageCache: 96000, analyticsCache: 8000, pendingSync: queue.items.length * 512);
  @override Future<void> clearSearchHistory() => store.remove(LocalKeys.recentSearches);
  @override Future<void> clearAnalytics() => store.remove('analytics');
  @override Future<void> clearStale() => cache.clear(staleOnly: true);
  @override Future<void> clearAllLocalData({bool includePreferences = false}) async { await cache.clear(); await queue.clear(); await clearSearchHistory(); await clearAnalytics(); if (includePreferences) await store.clear(); }
}

abstract interface class PerformanceMonitor { void record(String name, num value, {String unit}); List<PerformanceMetric> get metrics; }
class LocalPerformanceMonitor implements PerformanceMonitor {
  final List<PerformanceMetric> _metrics = [];
  @override List<PerformanceMetric> get metrics => List.unmodifiable(_metrics);
  @override void record(String name, num value, {String unit = 'ms'}) { _metrics.add(PerformanceMetric(name: name, value: value, recordedAt: DateTime.now(), unit: unit)); if (_metrics.length > 100) _metrics.removeAt(0); }
}

abstract interface class SearchIndexService<T> { Future<void> prepare(Iterable<T> items, Iterable<String> Function(T) terms); Future<List<T>> search(String query, {int limit}); }
class MemorySearchIndexService<T> implements SearchIndexService<T> {
  final Map<String, Set<T>> _index = {}; int _generation = 0;
  @override Future<void> prepare(Iterable<T> items, Iterable<String> Function(T) terms) async { _index.clear(); for (final item in items) { for (final term in terms(item)) { for (final token in term.toLowerCase().split(RegExp(r'\s+'))) { (_index[token] ??= {}).add(item); } } } }
  @override Future<List<T>> search(String query, {int limit = 10}) async { final generation = ++_generation; await Future<void>.delayed(const Duration(milliseconds: 250)); if (generation != _generation || query.trim().length < 2) return []; final words = query.toLowerCase().trim().split(RegExp(r'\s+')); final result = <T>{}; for (final entry in _index.entries) { if (words.any(entry.key.startsWith)) result.addAll(entry.value); } return result.take(limit).toList(); }
}

abstract interface class ImageCacheService { String cacheKey(String source, {int? width, int? height}); Future<void> clear(); }
class MockImageCacheService implements ImageCacheService { @override String cacheKey(String source, {int? width, int? height}) => '$source@${width ?? 0}x${height ?? 0}'; @override Future<void> clear() async {} }
