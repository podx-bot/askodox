import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/config/environment.dart';

void main() {
  test('development defaults are safe mock settings', () {
    final config = AppConfig.fromEnvironment(const {});
    expect(config.environment, AppEnvironment.development);
    expect(config.mockControlsEnabled, isTrue);
  });

  test('production permits local matching fallback without developer controls', () {
    final config = AppConfig.fromEnvironment(const {
      'APP_ENV': 'production',
      'BACKEND_PROVIDER': 'mock',
    });
    expect(config.environment, AppEnvironment.production);
    expect(config.backendProvider, BackendProvider.mock);
    expect(config.developerToolsEnabled, isFalse);
    expect(config.mockControlsEnabled, isFalse);
  });

  test('production remote backend still requires an absolute API URL', () {
    expect(
      () => AppConfig.fromEnvironment(const {
        'APP_ENV': 'production',
        'BACKEND_PROVIDER': 'rest',
      }),
      throwsFormatException,
    );
  });

  test('unknown environment has an actionable validation failure', () {
    expect(
      () => AppConfig.fromEnvironment(const {'APP_ENV': 'preview'}),
      throwsA(isA<FormatException>().having((error) => error.message, 'message', contains('APP_ENV'))),
    );
  });
}
