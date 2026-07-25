import 'package:flutter/foundation.dart';

abstract interface class MonitoringService {
  void recordError(Object error, StackTrace stackTrace, {Map<String, Object?> context = const {}});
  void recordPerformance(String operation, Duration duration);
  void recordRelease(String version);
}

/// Safe local implementation. Firebase Crashlytics, Sentry, or another vendor
/// can implement [MonitoringService] without leaking vendor APIs into features.
class ConsoleMonitoringService implements MonitoringService {
  const ConsoleMonitoringService();

  @override
  void recordError(Object error, StackTrace stackTrace, {Map<String, Object?> context = const {}}) {
    debugPrint('PODX error: $error context=${_redact(context)}');
  }

  @override
  void recordPerformance(String operation, Duration duration) {
    debugPrint('PODX performance: $operation ${duration.inMilliseconds}ms');
  }

  @override
  void recordRelease(String version) => debugPrint('PODX release: $version');

  Map<String, Object?> _redact(Map<String, Object?> context) => {
        for (final entry in context.entries)
          entry.key: _sensitiveKeys.any(entry.key.toLowerCase().contains)
              ? '[REDACTED]'
              : entry.value,
      };
}

const _sensitiveKeys = ['token', 'password', 'otp', 'phone', 'email', 'location'];
