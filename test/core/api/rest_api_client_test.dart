import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';

void main() {
  test('GET joins base URL, path, and query parameters', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/debug/deal-inbox/app-buyer?limit=10');
      return http.Response(jsonEncode({'thread_count': 1}), 200, headers: {'content-type': 'application/json'});
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.get<Map<String, Object?>>(
      '/debug/deal-inbox/app-buyer',
      options: const ApiRequestOptions(query: {'limit': 10}),
    );

    expect(result, isA<ApiSuccess<Map<String, Object?>>>());
    expect((result as ApiSuccess<Map<String, Object?>>).data['thread_count'], 1);
  });

  test('POST sends JSON body and decodes JSON response', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), {
        'user_id': 'app-buyer',
        'request_id': 7,
        'other_user_id': 'app-seller',
        'message': 'Hello',
      });
      return http.Response(jsonEncode({'status': 'SENT'}), 200, headers: {'content-type': 'application/json'});
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.post<Map<String, Object?>>('/debug/deal-message', body: {
      'user_id': 'app-buyer',
      'request_id': 7,
      'other_user_id': 'app-seller',
      'message': 'Hello',
    });

    expect(result, isA<ApiSuccess<Map<String, Object?>>>());
    expect((result as ApiSuccess<Map<String, Object?>>).data['status'], 'SENT');
  });

  test('backend HTTP errors preserve detail message and status', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode({'detail': 'deal is not accepted yet'}), 409));
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.post<Map<String, Object?>>('/debug/deal-message', body: const {});

    expect(result, isA<ApiError<Map<String, Object?>>>());
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    expect(failure.statusCode, 409);
    expect(failure.message, 'deal is not accepted yet');
  });
}
