import 'api_models.dart';
class ApiRequestOptions { const ApiRequestOptions({this.headers = const {}, this.query = const {}, this.authToken, this.timeout = const Duration(seconds: 15), this.pageToken, this.pageSize, this.retryCount = 0}); final Map<String,String> headers; final Map<String,Object?> query; final String? authToken; final Duration timeout; final String? pageToken; final int? pageSize; final int retryCount; }
abstract interface class ApiClient {
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()});
  Future<ApiResult<Uri>> upload(String path, {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()});
}
class MockApiClient implements ApiClient {
  MockApiClient({this.delay = Duration.zero, this.failure}); final Duration delay; final ApiFailure? failure;
  Future<ApiResult<T>> _reply<T>([Object? body]) async { await Future<void>.delayed(delay); if (failure != null) return ApiError(failure!); return ApiSuccess(body as T); }
  @override Future<ApiResult<T>> get<T>(String path,{ApiRequestOptions options=const ApiRequestOptions()})=>_reply<T>();
  @override Future<ApiResult<T>> post<T>(String path,{Object? body,ApiRequestOptions options=const ApiRequestOptions()})=>_reply<T>(body);
  @override Future<ApiResult<T>> put<T>(String path,{Object? body,ApiRequestOptions options=const ApiRequestOptions()})=>_reply<T>(body);
  @override Future<ApiResult<T>> patch<T>(String path,{Object? body,ApiRequestOptions options=const ApiRequestOptions()})=>_reply<T>(body);
  @override Future<ApiResult<T>> delete<T>(String path,{ApiRequestOptions options=const ApiRequestOptions()})=>_reply<T>();
  @override Future<ApiResult<Uri>> upload(String path,{required List<int> bytes,required String fileName,ApiRequestOptions options=const ApiRequestOptions()})=>_reply(Uri.parse('mock://uploads/$fileName'));
}
