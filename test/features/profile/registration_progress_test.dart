import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/profile/data/registration_repository.dart';
import 'package:podx/features/profile/presentation/registration_progress.dart';

class _Recorder implements ApiClient {
  final posts = <Object?>[];
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add(body);
    return ApiSuccess<T>(<String, Object?>{'verification': 'pending'} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('only a COMPLETE role that is not pending / verified can ask for verification', () {
    AskodoxRoleRegistration r(String status, String v) =>
        AskodoxRoleRegistration(role: 'cab_driver', missing: const [], status: status, verification: v);
    expect(r('complete', 'not_requested').canRequestVerification, isTrue);
    expect(r('complete', 'rejected').canRequestVerification, isTrue);
    expect(r('complete', 'pending').canRequestVerification, isFalse);
    expect(r('complete', 'verified').canRequestVerification, isFalse);
    expect(r('draft', 'not_requested').canRequestVerification, isFalse);
    expect(askodoxFieldLabel('operating_hours'), 'Operating hours');
  });

  testWidgets('drafts list what is missing; Verify sends the chosen kind and number', (tester) async {
    final client = _Recorder();
    const reg = AskodoxRegistration(basicsMissing: ['address'], complete: false, roles: [
      AskodoxRoleRegistration(role: 'restaurant', missing: ['operating_hours'], status: 'draft', verification: 'not_requested'),
      AskodoxRoleRegistration(role: 'cab_driver', missing: [], status: 'complete', verification: 'not_requested'),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        registrationProvider.overrideWith((ref) async => reg),
        registrationRepositoryProvider.overrideWithValue(RegistrationRepository(client, authToken: 't')),
      ],
      child: const MaterialApp(home: Scaffold(body: AskodoxRegistrationProgress())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Address'), findsOneWidget);
    expect(find.textContaining('Operating hours'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxRequestVerification-restaurant')), findsNothing,
        reason: 'a draft role cannot ask for verification');
    await tester.tap(find.byKey(const ValueKey('askodoxRequestVerification-cab_driver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxVerificationReference')), 'AP16AB1234');
    await tester.tap(find.byKey(const Key('askodoxVerificationSend')));
    await tester.pumpAndSettle();
    expect(client.posts.single, {'role': 'cab_driver', 'reference_kind': 'other', 'reference': 'AP16AB1234', 'note': ''});
    expect(find.text('Verification requested.'), findsOneWidget);
  });
}
