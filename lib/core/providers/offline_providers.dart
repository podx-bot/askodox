import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../offline/offline_models.dart';
import '../offline/offline_services.dart';
import '../startup/startup_controller.dart';
import '../sync/sync_models.dart';
import 'backend_providers.dart';

final connectivityServiceProvider = Provider<MockConnectivityService>((ref) { final service = MockConnectivityService(); ref.onDispose(service.dispose); return service; });
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) async* { final service = ref.watch(connectivityServiceProvider); yield service.current; yield* service.changes; });
final cacheRepositoryProvider = Provider<CacheRepository>((ref) => MemoryCacheRepository());
final syncQueueRepositoryProvider = Provider<MemorySyncQueueRepository>((ref) => MemorySyncQueueRepository());
final conflictResolverProvider = Provider<ConflictResolver>((ref) => MockConflictResolver());
final migrationServiceProvider = Provider<MigrationService>((ref) => MockMigrationService(ref.watch(localStoreProvider)));
final storageManagementProvider = Provider<StorageManagementService>((ref) => MockStorageManagementService(ref.watch(localStoreProvider), ref.watch(cacheRepositoryProvider), ref.watch(syncQueueRepositoryProvider)));
final performanceMonitorProvider = Provider<PerformanceMonitor>((ref) => LocalPerformanceMonitor());
final imageCacheServiceProvider = Provider<ImageCacheService>((ref) => MockImageCacheService());
final startupControllerProvider = StateNotifierProvider<StartupController, StartupState>((ref) => StartupController(ref.watch(connectivityServiceProvider)));
