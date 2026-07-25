enum AppEnvironment { development, staging, production }
enum BackendProvider { mock, supabase, firebase, rest, graphql }
enum LoggingLevel { debug, info, warning, error, none }

class AppConfig {
  const AppConfig({required this.environment, required this.backendProvider, required this.apiBaseUrl, required this.storageUrl, required this.authSettings, required this.mapsProvider, required this.loggingLevel});
  final AppEnvironment environment;
  final BackendProvider backendProvider;
  final Uri? apiBaseUrl;
  final Uri? storageUrl;
  final Map<String, String> authSettings;
  final String mapsProvider;
  final LoggingLevel loggingLevel;

  factory AppConfig.fromEnvironment(Map<String, String> values) {
    final environment = AppEnvironment.values.byName(values['APP_ENV'] ?? 'development');
    final provider = BackendProvider.values.byName(values['BACKEND_PROVIDER'] ?? 'mock');
    final config = AppConfig(environment: environment, backendProvider: provider, apiBaseUrl: Uri.tryParse(values['API_BASE_URL'] ?? ''), storageUrl: Uri.tryParse(values['STORAGE_URL'] ?? ''), authSettings: {'otpEnabled': values['AUTH_OTP_ENABLED'] ?? 'false'}, mapsProvider: values['MAPS_PROVIDER'] ?? 'mock', loggingLevel: LoggingLevel.values.byName(values['LOGGING_LEVEL'] ?? 'debug'));
    config.validate();
    return config;
  }

  void validate() {
    if (backendProvider != BackendProvider.mock && (apiBaseUrl == null || !apiBaseUrl!.hasScheme)) {
      throw const FormatException('API_BASE_URL is required and must be an absolute URL when a remote backend is selected.');
    }
    if (environment == AppEnvironment.production && backendProvider == BackendProvider.mock) {
      throw const FormatException('Production must select a non-mock BACKEND_PROVIDER.');
    }
  }

  static AppConfig development() => const AppConfig(environment: AppEnvironment.development, backendProvider: BackendProvider.mock, apiBaseUrl: null, storageUrl: null, authSettings: {'otpEnabled': 'false'}, mapsProvider: 'mock', loggingLevel: LoggingLevel.debug);
}
