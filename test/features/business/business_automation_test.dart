import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/business/presentation/business_automation_screen.dart';
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
  Object? saved;
  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{
        'item': {
          'status': 'DISABLED',
          'data': {'faq': {'delivery': 'Free delivery within 5 km.'}, 'business_hours': '09-21', 'handoff_words': []},
        },
        'platforms': {
          'askodox_chat': {'status': 'LIVE', 'reason': 'ASKODOX deal chats'},
          'instagram': {'status': 'EXTERNAL_SETUP_REQUIRED', 'reason': 'Meta App Review + Page token'},
          'snapchat': {'status': 'NOT_AVAILABLE', 'reason': 'no public messaging API'},
        },
        'note': 'Answers only from your approved FAQ.',
      } as T);

  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    saved = body;
    return ApiSuccess(<String, Object?>{'item': {}} as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{'status': 'handoff', 'text': null} as T);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('automation: ON/OFF, approved answers, save, preview, real platform status, history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const BusinessAutomationScreen()),
      GoRoute(path: '/deals', builder: (_, __) => const Scaffold(body: Text('conversations'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxAutoFaq-delivery')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('askodoxAutoReplyEnabled'))).value, isFalse);

    await tester.tap(find.byKey(const Key('askodoxAutoReplyEnabled')));
    await tester.tap(find.byKey(const Key('askodoxAutoFaqAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxAutoFaqTopic')), 'returns');
    await tester.enterText(find.byKey(const Key('askodoxAutoFaqAnswer')), '7-day returns.');
    await tester.tap(find.byKey(const Key('askodoxAutoFaqSave')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('askodoxAutoSave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAutoSave')));
    await tester.pumpAndSettle();
    final body = api.saved as Map;
    expect(body['enabled'], isTrue);
    expect(body['faq'], {'delivery': 'Free delivery within 5 km.', 'returns': '7-day returns.'});
    expect(body['business_hours'], '09-21');

    await tester.ensureVisible(find.byKey(const Key('askodoxAutoTryMessage')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxAutoTryMessage')), 'I want a refund');
    await tester.tap(find.byKey(const Key('askodoxAutoPreview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Handed over to you'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('askodoxPlatform-snapchat')));
    await tester.pumpAndSettle();
    expect(find.text('Connected (verified)'), findsOneWidget, reason: 'only ASKODOX chats are connected');
    expect(find.text('Needs your platform connection'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('askodoxAutoHistory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAutoHistory')));
    await tester.pumpAndSettle();
    expect(find.text('conversations'), findsOneWidget);
  });
}
