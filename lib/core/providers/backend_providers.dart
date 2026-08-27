import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../auth/auth_service.dart';
import '../auth/session_manager.dart';
import '../config/environment.dart';
import '../logging/app_logger.dart';
import '../persistence/local_store.dart';
import '../storage/file_storage.dart';
import '../sync/sync_models.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  final apiBaseUrl = const String.fromEnvironment('API_BASE_URL').trim();
  final explicitBackend = const String.fromEnvironment('BACKEND_PROVIDER').trim();

  // A signed/demo build must never select the REST client with an empty URL.
  // CI can intentionally leave API_BASE_URL unset while the live backend is
  // not configured yet. In that case keep the app/demo usable via the mock
  // backend instead of throwing during match navigation.
  final resolvedBackend = apiBaseUrl.isEmpty
      ? 'mock'
      : (explicitBackend.isNotEmpty ? explicitBackend : 'rest');

  return AppConfig.fromEnvironment({
    'APP_ENV': const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    'BACKEND_PROVIDER': resolvedBackend,
    'API_BASE_URL': apiBaseUrl,
    'STORAGE_URL': const String.fromEnvironment('STORAGE_URL'),
    'AUTH_OTP_ENABLED': const String.fromEnvironment('AUTH_OTP_ENABLED', defaultValue: 'false'),
    'MAPS_PROVIDER': const String.fromEnvironment('MAPS_PROVIDER', defaultValue: 'mock'),
    'LOGGING_LEVEL': const String.fromEnvironment('LOGGING_LEVEL', defaultValue: 'debug'),
  });
});

final localStoreProvider = Provider<LocalStore>((ref) => MemoryLocalStore());
final authenticationServiceProvider = Provider<AuthenticationService>((ref) => MockAuthenticationService());
final sessionManagerProvider = Provider<SessionManager>((ref) => SessionManager(
      ref.watch(localStoreProvider),
      ref.watch(authenticationServiceProvider),
    ));
final authSessionProvider = StateNotifierProvider<AuthController, AuthSession>(
  (ref) => AuthController(ref.watch(sessionManagerProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return switch (config.backendProvider) {
    BackendProvider.mock => MockApiClient(),
    BackendProvider.rest => RestApiClient(baseUrl: config.apiBaseUrl!),
    _ => throw UnsupportedError('Backend provider ${config.backendProvider.name} is not wired to ApiClient yet.'),
  };
});

final fileStorageProvider = Provider<FileStorage>((ref) => MockFileStorage());
final syncServiceProvider = Provider<SyncService>((ref) => MockSyncService());
final loggerProvider = Provider<AppLogger>((ref) => ConsoleAppLogger());
