import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_models.dart';

class ApiRequestOptions {
  const ApiRequestOptions({
    this.headers = const {},
    this.query = const {},
    this.authToken,
    this.timeout = const Duration(seconds: 15),
    this.pageToken,
    this.pageSize,
    this.retryCount = 0,
    this.requestId,
    this.idempotencyKey,
  });

  final Map<String, String> headers;
  final Map<String, Object?> query;
  final String? authToken;
  final Duration timeout;
  final String? pageToken;
  final int? pageSize;
  final int retryCount;
  final String? requestId;
  final String? idempotencyKey;
}

abstract interface class ApiClient {
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<Uri>> upload(String path, {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()});
}

class RestApiClient implements ApiClient {
  RestApiClient({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  Uri _uri(String path, ApiRequestOptions options) {
    final cleanBasePath = baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final query = <String, String>{
      ...baseUrl.queryParameters,
      for (final entry in options.query.entries)
        if (entry.value != null) entry.key: '${entry.value}',
      if (options.pageToken != null) 'page_token': options.pageToken!,
      if (options.pageSize != null) 'page_size': '${options.pageSize}',
    };
    return baseUrl.replace(path: '$cleanBasePath$cleanPath', queryParameters: query.isEmpty ? null : query);
  }

  Map<String, String> _headers(ApiRequestOptions options, {bool jsonBody = false}) => {
        'Accept': 'application/json',
        if (jsonBody) 'Content-Type': 'application/json',
        if (options.authToken != null && options.authToken!.isNotEmpty) 'Authorization': 'Bearer ${options.authToken}',
        if (options.requestId != null && options.requestId!.trim().isNotEmpty) 'X-Request-ID': options.requestId!.trim(),
        if (options.idempotencyKey != null && options.idempotencyKey!.trim().isNotEmpty) 'Idempotency-Key': options.idempotencyKey!.trim(),
        ...options.headers,
      };

  bool _canRetry(String method, ApiRequestOptions options) {
    final normalized = method.toUpperCase();
    if (normalized == 'GET') return true;
    return options.idempotencyKey != null && options.idempotencyKey!.trim().isNotEmpty;
  }

  bool _retryableStatus(int statusCode) => statusCode == 408 || statusCode == 429 || statusCode >= 500;

  Future<ApiResult<T>> _request<T>(
    String method,
    String path, {
    Object? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    final uri = _uri(path, options);
    var retriesUsed = 0;
    final canRetry = _canRetry(method, options);
    while (true) {
      try {
        final request = http.Request(method, uri)..headers.addAll(_headers(options, jsonBody: body != null));
        if (body != null) request.body = jsonEncode(body);
        final streamed = await _http.send(request).timeout(options.timeout);
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final Object? decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
          return ApiSuccess<T>(decoded as T);
        }
        if (canRetry && _retryableStatus(response.statusCode) && retriesUsed < options.retryCount) {
          retriesUsed += 1;
          continue;
        }
        final message = _errorMessage(response.body);
        final failure = mapApiError(message, statusCode: response.statusCode);
        return ApiError<T>(ApiFailure(
          failure.type,
          message: message,
          statusCode: response.statusCode,
          cause: response.body,
        ));
      } on TimeoutException catch (error) {
        if (canRetry && retriesUsed < options.retryCount) {
          retriesUsed += 1;
          continue;
        }
        return ApiError<T>(ApiFailure(ApiFailureType.timeout, message: 'The request timed out.', cause: error));
      } on http.ClientException catch (error) {
        if (canRetry && retriesUsed < options.retryCount) {
          retriesUsed += 1;
          continue;
        }
        return ApiError<T>(ApiFailure(ApiFailureType.network, message: error.message, cause: error));
      } on FormatException catch (error) {
        return ApiError<T>(ApiFailure(ApiFailureType.server, message: 'Backend returned invalid JSON.', cause: error));
      } catch (error) {
        if (canRetry && retriesUsed < options.retryCount) {
          retriesUsed += 1;
          continue;
        }
        return ApiError<T>(mapApiError(error));
      }
    }
  }

  String _errorMessage(String body) {
    if (body.trim().isEmpty) return 'Backend request failed.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'] ?? decoded['message'] ?? decoded['error'];
        if (detail != null) return '$detail';
      }
    } catch (_) {}
    return body.length > 300 ? '${body.substring(0, 300)}…' : body;
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _request<T>('GET', path, options: options);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _request<T>('POST', path, body: body, options: options);

  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _request<T>('PUT', path, body: body, options: options);

  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _request<T>('PATCH', path, body: body, options: options);

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _request<T>('DELETE', path, options: options);

  @override
  Future<ApiResult<Uri>> upload(
    String path, {
    required List<int> bytes,
    required String fileName,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    final uri = _uri(path, options);
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers(options))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final response = await http.Response.fromStream(await _http.send(request).timeout(options.timeout));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _errorMessage(response.body);
        final failure = mapApiError(message, statusCode: response.statusCode);
        return ApiError<Uri>(ApiFailure(failure.type, message: message, statusCode: response.statusCode));
      }
      final decoded = jsonDecode(response.body);
      final value = decoded is Map ? decoded['url'] ?? decoded['uri'] : null;
      final uploaded = value == null ? null : Uri.tryParse('$value');
      return uploaded == null
          ? const ApiError<Uri>(ApiFailure(ApiFailureType.server, message: 'Upload response did not include a URL.'))
          : ApiSuccess<Uri>(uploaded);
    } on TimeoutException catch (error) {
      return ApiError<Uri>(ApiFailure(ApiFailureType.timeout, message: 'The upload timed out.', cause: error));
    } on http.ClientException catch (error) {
      return ApiError<Uri>(ApiFailure(ApiFailureType.network, message: error.message, cause: error));
    } catch (error) {
      return ApiError<Uri>(mapApiError(error));
    }
  }
}

class MockApiClient implements ApiClient {
  MockApiClient({this.delay = Duration.zero, this.failure});
  final Duration delay;
  final ApiFailure? failure;

  Future<ApiResult<T>> _reply<T>([Object? body]) async {
    await Future<void>.delayed(delay);
    if (failure != null) return ApiError(failure!);
    return ApiSuccess(body as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _reply<T>();
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) => _reply<T>(body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) => _reply<T>(body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) => _reply<T>(body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _reply<T>();
  @override
  Future<ApiResult<Uri>> upload(String path, {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _reply(Uri.parse('mock://uploads/$fileName'));
}
