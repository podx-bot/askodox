import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/selling/presentation/my_listings_screen.dart';
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
  final patches = <(String, Object?)>[];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{
        'items': [
          {'id': 7, 'subject': 'walking shoes', 'price': 2200, 'stock_status': 'UNKNOWN'},
        ],
      } as T);

  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    patches.add((path, body));
    return ApiSuccess(<String, Object?>{'item': body} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('tapping a listing edits price, size and stock (no dead listing rows)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: MyListingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxEditListing-7')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxEditListingPrice')), '1800');
    await tester.enterText(find.byKey(const Key('askodoxEditListingVariant')), 'Size: 8, 9, 10');
    await tester.tap(find.text('In stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxEditListingSave')));
    await tester.pumpAndSettle();
    expect(api.patches.single.$1, '/api/products/mine/7');
    expect(api.patches.single.$2, {'price': 1800.0, 'variant': 'Size: 8, 9, 10', 'stock_status': 'IN_STOCK'});
    expect(find.textContaining('Saved. Buyers see the new details now.'), findsOneWidget);
  });
}
