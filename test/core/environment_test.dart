import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/config/environment.dart';

void main() {
  test('development defaults are safe mock settings', () {
    final config = AppConfig.fromEnvironment(const {});
    expect(config.environment, AppEnvironment.development);
    expect(config.mockControlsEnabled, isTrue);
  });

  test('production rejects the mock backend', () {
    expect(
      () => AppConfig.fromEnvironment(const {'APP_ENV': 'production'}),
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
