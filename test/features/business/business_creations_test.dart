import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/business/presentation/business_creations_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919800000000', role: UserRole.seller, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _Api implements ApiClient {
  _Api({this.aiReady = true});
  final bool aiReady;
  final items = <Map<String, Object?>>[];
  final posted = <Object?>[];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{
        'items': items,
        'capabilities': {
          'text_drafts': {'status': aiReady ? 'READY' : 'NOT_AVAILABLE', 'reason': 'no AI model is configured'},
          'image_generation': {'status': 'NOT_AVAILABLE', 'reason': 'No image-generation provider is configured.'},
          'video_generation': {'status': 'NOT_AVAILABLE', 'reason': 'ASKODOX does not generate video.'},
        },
      } as T);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posted.add(body);
    if (path.endsWith('/draft')) {
      return ApiSuccess(<String, Object?>{'text': 'Soft cotton sarees at Rs 500. [timings]', 'source': 'ai'} as T);
    }
    items.add({'id': items.length + 1, ...Map<String, Object?>.from(body as Map)});
    return ApiSuccess(<String, Object?>{} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_Api> _pump(WidgetTester tester, _Api api) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const BusinessCreationsScreen()),
    GoRoute(path: '/videos/native', builder: (_, __) => const Scaffold(body: Text('native video'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('AI draft from the owner facts -> saved -> shared only via the system sheet', (tester) async {
    final shared = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.askodox.app/device'), (call) async {
      if (call.method == 'shareText') shared.add(call.arguments);
      return true;
    });
    final api = await _pump(tester, _Api());
    expect(find.textContaining('No image-generation provider is configured'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('askodoxCreationImageGen'))).enabled, isFalse);

    await tester.tap(find.byKey(const Key('askodoxCreationAi')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxCreationAbout')), 'cotton sarees 500 rupees');
    await tester.tap(find.byKey(const Key('askodoxCreationDraft')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCreationAiNote')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCreationSave')));
    await tester.pumpAndSettle();
    expect((api.posted.last as Map)['source'], 'ai');
    expect((api.posted.last as Map)['body'], contains('[timings]'));
    expect(find.text('Soft cotton sarees at Rs 500. [timings]'), findsOneWidget);
    expect(shared, isEmpty, reason: 'nothing is shared or posted automatically');

    await tester.tap(find.byKey(const ValueKey('askodoxCreationShare-1')));
    await tester.pumpAndSettle();
    expect((shared.single as Map)['text'], contains('cotton sarees'));

    await tester.tap(find.byKey(const Key('askodoxCreationVideoUpload')));
    await tester.pumpAndSettle();
    expect(find.text('native video'), findsOneWidget);
  });

  testWidgets('AI drafting unavailable: said plainly, writing by hand still works', (tester) async {
    await _pump(tester, _Api(aiReady: false));
    expect(tester.widget<FilledButton>(find.byKey(const Key('askodoxCreationAi'))).onPressed, isNull);
    expect(find.byKey(const Key('askodoxCreationAiUnavailable')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCreationManual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCreationDraft')), findsNothing);
  });
}
