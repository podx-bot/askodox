import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/home/data/greeting_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MockApiClient {
  final paths = <String>[];
  String text = 'Good morning Asha!';

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    paths.add(path);
    return ApiSuccess(<String, Object?>{'greeting': {'text': text}} as T);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('APK 1273: greeting comes from the configured engine with local hour, language and name', () async {
    final api = _Api();
    var now = DateTime(2026, 10, 1, 8, 30);
    final repo = GreetingRepository(api, clock: () => now);
    expect(await repo.next(language: 'ta', name: 'Asha Rao'), 'Good morning Asha!');
    final uri = Uri.parse(api.paths.single);
    expect(uri.path, '/api/greeting');
    expect(uri.queryParameters['local_hour'], '8');
    expect(uri.queryParameters['language'], 'ta');
    expect(uri.queryParameters['name'], 'Asha');
    expect(uri.queryParameters['returning'], 'false');

    // Not repeated within the gap; afterwards a returning-user greeting that
    // avoids the previous text.
    now = now.add(const Duration(hours: 1));
    expect(await repo.next(language: 'ta'), isNull);
    now = now.add(const Duration(hours: 5));
    api.text = 'Welcome back!';
    expect(await repo.next(language: 'ta'), 'Welcome back!');
    final second = Uri.parse(api.paths.last);
    expect(second.queryParameters['returning'], 'true');
    expect(second.queryParameters['last'], 'Good morning Asha!');
    expect(second.queryParameters['local_hour'], '14');
  });
}
