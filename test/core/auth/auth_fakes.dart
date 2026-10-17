import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/phone_auth.dart';

/// One recorded call: method, path, body, bearer token.
typedef AuthCall = (String method, String path, Object? body, String? token);

/// A scripted backend: handlers by "METHOD path"; unknown calls answer {}.
class FakeAuthApi implements ApiClient {
  final calls = <AuthCall>[];
  final handlers = <String, ApiResult<Object?> Function(Object? body)>{};

  void on(String key, ApiResult<Object?> Function(Object? body) answer) => handlers[key] = answer;

  Future<ApiResult<T>> _answer<T>(String method, String path, Object? body, ApiRequestOptions options) async {
    calls.add((method, path, body, options.authToken));
    final handler = handlers['$method $path'];
    if (handler == null) return ApiSuccess<T>(<String, Object?>{} as T);
    final result = handler(body);
    return switch (result) {
      ApiSuccess(:final data) => ApiSuccess<T>(data as T),
      ApiError(:final failure) => ApiError<T>(failure),
    };
  }

  List<AuthCall> to(String method, String path) => [for (final c in calls) if (c.$1 == method && c.$2 == path) c];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer<T>('GET', path, null, options);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer<T>('POST', path, body, options);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer<T>('PUT', path, body, options);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer<T>('PATCH', path, body, options);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer<T>('DELETE', path, null, options);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(Uri.parse('https://example.invalid/$fileName'));
}

ApiError<Object?> httpError(int status, String message, {Map<String, String> headers = const {}}) =>
    ApiError<Object?>(ApiFailure(
      status == 429 ? ApiFailureType.rateLimit : (status == 401 ? ApiFailureType.authentication : ApiFailureType.validation),
      message: message,
      statusCode: status,
      headers: headers,
    ));

ApiError<Object?> networkError() =>
    const ApiError<Object?>(ApiFailure(ApiFailureType.network, message: 'Connection refused'));

class FakePhoneAuth implements AskodoxPhoneAuth {
  FakePhoneAuth({this.available = true, this.startResult = const AskodoxPhoneCodeSent('vid-1', 7)});
  @override
  final bool available;
  AskodoxPhoneAuthStart startResult;
  final started = <String>[];
  final confirmed = <(String, String)>[];
  String? confirmError;
  int signOuts = 0;

  /// The late-event callback of the most recent start (a test fires a
  /// `codeSent` that arrives after the first answer, as after reCAPTCHA).
  void Function(AskodoxPhoneAuthStart event)? lastOnLate;

  /// When set, start() drives a REAL AskodoxPhoneVerificationSession through
  /// these callbacks (same ordering logic as the Firebase build).
  void Function(AskodoxPhoneVerificationSession session)? script;
  Duration grace = const Duration(milliseconds: 200);

  @override
  Future<AskodoxPhoneAuthStart> start(String e164,
      {int? resendToken, void Function(AskodoxPhoneAuthStart event)? onLate}) async {
    started.add(e164);
    lastOnLate = onLate;
    final drive = script;
    if (drive == null) return startResult;
    final session = AskodoxPhoneVerificationSession(grace: grace, onLate: onLate);
    drive(session);
    return session.result;
  }

  @override
  Future<String> confirm(String verificationId, String code) async {
    confirmed.add((verificationId, code));
    if (confirmError != null) throw AskodoxPhoneAuthError(confirmError!);
    return 'firebase-id-token';
  }

  @override
  Future<void> signOut() async => signOuts++;
}
