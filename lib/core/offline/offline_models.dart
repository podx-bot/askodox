enum ConnectivityStatus { online, offline, limited, reconnecting, unknown }
enum CachePolicy { cacheFirst, networkFirst, staleWhileRevalidate, localOnly, noCache }
enum CacheFreshness { justNow, today, withinThreeDays, stale, offlineCopy }
enum StartupPhase { initializing, restoringSession, loadingPreferences, ready, offlineReady, recoverableError, fatalConfigurationError }
enum ImageLoadingState { idle, loading, loaded, error }

class CacheEntry<T> {
  const CacheEntry({required this.value, required this.updatedAt, required this.expiresAt, this.version = 1});
  final T value;
  final DateTime updatedAt, expiresAt;
  final int version;
  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
  CacheFreshness freshness(DateTime now, {bool offline = false}) { if (offline) return CacheFreshness.offlineCopy; final age = now.difference(updatedAt); if (age.inMinutes < 5) return CacheFreshness.justNow; if (age.inDays < 1) return CacheFreshness.today; if (age.inDays < 3) return CacheFreshness.withinThreeDays; return CacheFreshness.stale; }
}

class StartupState {
  const StartupState(this.phase, {this.message, this.elapsed = Duration.zero});
  final StartupPhase phase;
  final String? message;
  final Duration elapsed;
}

class OptimisticUpdate<T> {
  const OptimisticUpdate({required this.id, required this.previous, required this.optimistic, required this.createdAt, this.failed = false});
  final String id; final T previous, optimistic; final DateTime createdAt; final bool failed;
  T rollback() => previous;
}

class LocalDataVersion { const LocalDataVersion({required this.current, required this.previous}); final int current, previous; }
class MigrationStep { const MigrationStep({required this.from, required this.to, required this.description}); final int from, to; final String description; }
class MigrationResult { const MigrationResult({required this.success, required this.version, required this.log, this.error}); final bool success; final int version; final List<String> log; final String? error; }
class StorageUsage { const StorageUsage({this.cachedProducts = 0, this.cachedShops = 0, this.searchHistory = 0, this.imageCache = 0, this.analyticsCache = 0, this.pendingSync = 0}); final int cachedProducts, cachedShops, searchHistory, imageCache, analyticsCache, pendingSync; int get total => cachedProducts + cachedShops + searchHistory + imageCache + analyticsCache + pendingSync; }
class PerformanceMetric { const PerformanceMetric({required this.name, required this.value, required this.recordedAt, this.unit = 'ms'}); final String name; final num value; final DateTime recordedAt; final String unit; }

abstract final class CacheDurations {
  static const productCatalog = Duration(hours: 12), sellerListings = Duration(hours: 6), nearbyShops = Duration(hours: 2), priceComparison = Duration(hours: 1), shopProfiles = Duration(days: 1), alerts = Duration(minutes: 15), demandInsights = Duration(hours: 6), analyticsSummaries = Duration(hours: 12), subscriptionState = Duration(hours: 1), adminDashboards = Duration(minutes: 15);
}
