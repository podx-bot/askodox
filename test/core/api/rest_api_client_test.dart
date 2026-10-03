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

  test('APK 1275: a query written in the path is sent as a query, not encoded into the path', () async {
    final seen = <Uri>[];
    final mock = MockClient((request) async {
      seen.add(request.url);
      return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://staging.example.com'), httpClient: mock);
    await client.get<Map<String, Object?>>('/api/greeting?language=te&local_hour=18&name=Manohar&last=');
    await client.get<Map<String, Object?>>('/api/discover/places?q=chicken%20shop&near=Vuyyuru',
        options: const ApiRequestOptions(query: {'limit': 5}));
    expect(seen[0].path, '/api/greeting', reason: 'it was /api/greeting%3Flanguage... -> 404 on the phone');
    expect(seen[0].queryParameters, {'language': 'te', 'local_hour': '18', 'name': 'Manohar', 'last': ''});
    expect(seen[1].path, '/api/discover/places');
    expect(seen[1].queryParameters, {'q': 'chicken shop', 'near': 'Vuyyuru', 'limit': '5'});
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

  test('validation failure preserves ASKODOX guidance headers', () async {
    final mock = MockClient((request) async => http.Response(
          jsonEncode({'detail': 'ASKODOX understood the message but the requirement is not ready to publish yet'}),
          422,
          headers: {
            'X-ASKODOX-Intent-Domain': 'commerce',
            'X-ASKODOX-Intent-Action': 'buy',
            'X-ASKODOX-Missing-Fields': 'location,timing',
          },
        ));
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.post<Map<String, Object?>>('/deals', body: const {});

    expect(result, isA<ApiError<Map<String, Object?>>>());
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    expect(failure.type, ApiFailureType.validation);
    expect(failure.statusCode, 422);
    expect(failure.header('X-ASKODOX-Intent-Domain'), 'commerce');
    expect(failure.header('x-askodox-intent-action'), 'buy');
    expect(failure.header('X-ASKODOX-Missing-Fields'), 'location,timing');
  });

  test('GET retries transient server failure when configured', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls += 1;
      if (calls == 1) return http.Response(jsonEncode({'detail': 'temporary'}), 503);
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.get<Map<String, Object?>>(
      '/health',
      options: const ApiRequestOptions(retryCount: 1),
    );

    expect(calls, 2);
    expect(result, isA<ApiSuccess<Map<String, Object?>>>());
  });

  test('POST does not retry without an idempotency key', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls += 1;
      return http.Response(jsonEncode({'detail': 'temporary'}), 503);
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.post<Map<String, Object?>>(
      '/payments',
      body: const {'amount': 100},
      options: const ApiRequestOptions(retryCount: 2),
    );

    expect(calls, 1);
    expect(result, isA<ApiError<Map<String, Object?>>>());
  });

  test('idempotent POST retries with stable request headers', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls += 1;
      expect(request.headers['x-request-id'], 'req-123');
      expect(request.headers['idempotency-key'], 'deal-123');
      if (calls == 1) return http.Response(jsonEncode({'detail': 'temporary'}), 503);
      return http.Response(jsonEncode({'status': 'accepted'}), 200);
    });
    final client = RestApiClient(baseUrl: Uri.parse('https://api.example.com'), httpClient: mock);

    final result = await client.post<Map<String, Object?>>(
      '/deals/accept',
      body: const {'deal_id': 123},
      options: const ApiRequestOptions(
        retryCount: 1,
        requestId: 'req-123',
        idempotencyKey: 'deal-123',
      ),
    );

    expect(calls, 2);
    expect(result, isA<ApiSuccess<Map<String, Object?>>>());
  });
}
