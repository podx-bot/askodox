import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/profile/presentation/profile_memory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'phone-919800000000', role: UserRole.buyer, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

/// A fake /api/me/memory server that records every call.
class _MemoryApi implements ApiClient {
  bool enabled = true;
  final calls = <String>[];
  List<Map<String, Object?>> items = [
    {'id': 1, 'role': 'buyer', 'kind': 'need', 'category': 'electronics', 'subject': '43 inch TV',
      'details': {'budget': 30000}, 'status': 'active', 'visibility': 'private'},
    {'id': 2, 'role': 'service_taker', 'kind': 'need', 'category': 'services', 'subject': 'plumber',
      'details': <String, Object?>{}, 'status': 'updated', 'visibility': 'private'},
  ];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add('GET $path');
    return ApiSuccess(<String, Object?>{'enabled': enabled, 'items': items} as T);
  }

  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add('PUT $path $body');
    enabled = (body as Map)['enabled'] == true;
    return ApiSuccess(<String, Object?>{'enabled': enabled} as T);
  }

  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add('PATCH $path $body');
    final id = int.parse(path.split('/').last);
    items = [
      for (final i in items) i['id'] == id ? {...i, ...?(body as Map<String, Object?>?)} : i,
    ];
    return ApiSuccess(<String, Object?>{} as T);
  }

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add('DELETE $path');
    if (path.contains('confirm=DELETE')) {
      items = [];
    } else {
      final id = int.parse(path.split('/').last);
      items = [for (final i in items) if (i['id'] != id) i];
    }
    return ApiSuccess(<String, Object?>{} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_MemoryApi> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final api = _MemoryApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      apiClientProvider.overrideWithValue(api),
    ],
    child: const MaterialApp(home: ProfileMemoryScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('memory grouped by role (Service taker = services / jobs), with statuses', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('askodoxMemoryRole-buyer')), findsOneWidget);
    expect(find.text('Service taker (services / jobs)'), findsOneWidget);
    expect(find.text('43 inch TV'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);
    expect(find.textContaining('Never OTPs, passwords or card numbers'), findsOneWidget);
  });

  testWidgets('switch off, mark completed, correct, delete one, delete all (confirmed)', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byKey(const Key('askodoxMemoryEnabled')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('PUT /api/me/memory/settings {enabled: false}'));

    await tester.tap(find.byKey(const ValueKey('askodoxMemoryMenu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMemoryDone-1')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('PATCH /api/me/memory/1 {status: completed}'));
    expect(find.textContaining('Completed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('askodoxMemoryMenu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxMemoryEditField')), '50 inch TV');
    await tester.tap(find.byKey(const Key('askodoxMemoryEditSave')));
    await tester.pumpAndSettle();
    expect(find.text('50 inch TV'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('askodoxMemoryMenu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMemoryDelete-2')));
    await tester.pumpAndSettle();
    expect(find.text('plumber'), findsNothing);

    await tester.tap(find.byKey(const Key('askodoxMemoryDeleteAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMemoryDeleteAllConfirm')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('DELETE /api/me/memory?confirm=DELETE'));
    expect(find.byKey(const Key('askodoxMemoryEmpty')), findsOneWidget);
  });
}
