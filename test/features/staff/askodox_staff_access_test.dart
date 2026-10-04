import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/staff/askodox_staff_access.dart';

/// Answers the staff / early-access / feedback endpoints like the backend.
class _Api implements ApiClient {
  final gets = <String>[];
  final posts = <String, Object?>{};
  final tokens = <String?>[];
  bool staff = true;
  bool fail = false;

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    gets.add(path);
    tokens.add(options.authToken);
    if (fail) return ApiError(const ApiFailure(ApiFailureType.network, message: 'offline'));
    if (path.startsWith('/api/staff/me')) return ApiSuccess(<String, Object?>{'staff': staff} as T);
    return ApiSuccess(<String, Object?>{
      'active': true, 'label': 'Early Access', 'free_trial': true, 'feedback_prompt': true,
    } as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts[path] = body;
    tokens.add(options.authToken);
    if (fail) return ApiError(const ApiFailure(ApiFailureType.network, message: 'offline'));
    if (path == '/api/staff/handoff') return ApiSuccess(<String, Object?>{'code': 'one-time-code-123'} as T);
    return ApiSuccess(<String, Object?>{'ok': true, 'reference': 'fbk_1'} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final base = Uri.parse('https://api.example');

  test('only a signed-in number the server confirms is staff', () async {
    final api = _Api();
    final repo = AskodoxStaffRepository(api, base);
    expect(await repo.isStaff(null), isFalse, reason: 'guests never ask');
    expect(await repo.isStaff('OTP_VERIFIED'), isFalse, reason: 'placeholder is not a real session');
    expect(api.gets, isEmpty);
    expect(await repo.isStaff('real-token'), isTrue);
    api.staff = false;
    expect(await repo.isStaff('real-token'), isFalse);
    api.fail = true;
    expect(await repo.isStaff('real-token'), isFalse, reason: 'offline = no staff entry, no crash');
  });

  test('the workspace opens with a one-time code and the shared link -- never a stored token', () async {
    final api = _Api();
    final uri = await AskodoxStaffRepository(api, base)
        .workspaceUri('real-token', sharedUrl: 'https://www.amazon.in/dp/B0TEST1234?tag=x');
    expect(uri!.path, '/staff');
    final fragment = Uri.splitQueryString(uri.fragment);
    expect(fragment['code'], 'one-time-code-123');
    expect(fragment['url'], 'https://www.amazon.in/dp/B0TEST1234?tag=x');
    expect(uri.toString(), isNot(contains('real-token')));
    api.fail = true;
    expect(await AskodoxStaffRepository(api, base).workspaceUri('real-token'), isNull);
  });

  test('early access is read from the server and defaults to off when offline', () async {
    final api = _Api();
    final info = await AskodoxStaffRepository(api, base).earlyAccess(installId: 'abc', role: 'guest', city: 'Uyyuru');
    expect(info.active, isTrue);
    expect(info.freeTrial, isTrue);
    expect(api.gets.single, contains('install_id=abc'));
    api.fail = true;
    expect((await AskodoxStaffRepository(api, base).earlyAccess(installId: 'abc', role: 'guest')).active, isFalse);
  });

  test('feedback sends diagnostics only with consent and reports failure honestly', () async {
    final api = _Api();
    final repo = AskodoxStaffRepository(api, base);
    expect(await repo.sendFeedback(kind: 'bug', message: 'froze', diagnostics: {'screen': 'home'}), 'fbk_1');
    final body = api.posts['/api/feedback'] as Map<String, Object?>;
    expect(body['consent_diagnostics'], isFalse);
    expect(body.containsKey('diagnostics'), isFalse);
    await repo.sendFeedback(kind: 'bug', message: 'froze', consentDiagnostics: true, diagnostics: {'screen': 'home'});
    expect((api.posts['/api/feedback'] as Map)['diagnostics'], {'screen': 'home'});
    api.fail = true;
    expect(await repo.sendFeedback(kind: 'bug', message: 'x'), isNull);
  });

  test('the first https link is taken from shared text', () {
    expect(askodoxSharedLink('Look at this https://www.flipkart.com/x/p/itm123?pid=MOB1. Nice!'),
        'https://www.flipkart.com/x/p/itm123?pid=MOB1');
    expect(askodoxSharedLink('no link here, http://insecure.example'), isNull);
  });
}
