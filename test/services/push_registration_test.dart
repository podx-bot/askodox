import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/services/push_registration.dart';

class _Api implements ApiClient {
  final posts = <(String, Object?)>[];
  final deletes = <String>[];

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add((path, body));
    return ApiSuccess<T>(<String, Object?>{'registered': true} as T);
  }

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    deletes.add(path);
    return ApiSuccess<T>(<String, Object?>{} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Fcm implements AskodoxPushBackend {
  _Fcm({this.allow = true});
  final bool allow;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<AskodoxPushMessage>.broadcast();
  final opened = StreamController<AskodoxPushMessage>.broadcast();
  int inits = 0, deleted = 0;

  @override
  Future<bool> init() async {
    inits++;
    return true;
  }

  @override
  Future<bool> requestPermission() async => allow;
  @override
  Future<String?> token() async => 'fcm-token-0123456789-abcdef';
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<AskodoxPushMessage> get foregroundMessages => foreground.stream;
  @override
  Stream<AskodoxPushMessage> get openedMessages => opened.stream;
  @override
  Future<AskodoxPushMessage?> initialMessage() async => null;
  @override
  Future<void> deleteToken() async => deleted++;
}

void main() {
  AskodoxPushRegistration make(_Fcm fcm, _Api api, {bool configured = true, String? token = 't', List<AskodoxPushMessage>? shown}) =>
      AskodoxPushRegistration(
        backend: fcm,
        client: api,
        authToken: token,
        configured: configured,
        showForeground: (m) async => shown?.add(m),
      );

  test('without Firebase values in the build nothing is attempted', () async {
    final fcm = _Fcm(), api = _Api();
    expect(await make(fcm, api, configured: false).sync(), AskodoxPushState.notConfigured);
    expect(fcm.inits, 0);
    expect(api.posts, isEmpty);
  });

  test('signed out or permission denied: no token is sent', () async {
    final api = _Api();
    expect(await make(_Fcm(), api, token: null).sync(), AskodoxPushState.signedOut);
    expect(await make(_Fcm(allow: false), api).sync(), AskodoxPushState.permissionDenied);
    expect(api.posts, isEmpty);
  });

  test('registers the token, re-registers on refresh, shows foreground messages, routes taps', () async {
    final fcm = _Fcm(), api = _Api(), shown = <AskodoxPushMessage>[];
    final push = make(fcm, api, shown: shown);
    final routes = <String>[];
    push.openedRoutes.listen(routes.add);
    expect(await push.sync(), AskodoxPushState.registered);
    expect(api.posts.single.$1, '/api/me/push-token');
    expect(api.posts.single.$2, {'token': 'fcm-token-0123456789-abcdef', 'platform': 'android'});
    await push.sync();
    fcm.refresh.add('fcm-token-rotated-9876543210');
    fcm.foreground.add(const AskodoxPushMessage(title: 'ASKODOX', body: 'A partner accepted', route: '/mobility?tab=1'));
    fcm.opened.add(const AskodoxPushMessage(route: '/updates'));
    fcm.opened.add(const AskodoxPushMessage(route: 'https://evil.example'));
    await Future<void>.delayed(Duration.zero);
    expect(api.posts.last.$2, {'token': 'fcm-token-rotated-9876543210', 'platform': 'android'});
    expect(api.posts.where((p) => (p.$2 as Map)['token'] == 'fcm-token-0123456789-abcdef').length, 2,
        reason: 'sync is idempotent (same token re-sent, listeners added once)');
    expect(shown.single.body, 'A partner accepted');
    expect(routes, ['/updates'], reason: 'only in-app routes are opened');
    await push.unregister();
    expect(api.deletes.single, '/api/me/push-token');
    expect(fcm.deleted, 1);
  });
}
