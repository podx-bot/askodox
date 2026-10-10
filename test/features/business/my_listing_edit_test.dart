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
  final deletes = <String>[];
  final posts = <(String, Object?)>[];

  static const _meat = {
    'key': 'meat_poultry',
    'name': {'en': 'Meat, chicken & fish'},
    'categories': [
      {
        'key': 'chicken',
        'name': {'en': 'Chicken'},
        'items': [
          {'key': 'chicken.curry_cut', 'name': {'en': 'Chicken curry cut'}, 'unit': 'kg', 'sizes': ['1 kg']},
        ],
      },
    ],
    'attributes': [
      {'key': 'cut', 'label': {'en': 'Cut'}, 'kind': 'choice', 'options': ['Curry cut', 'Boneless'], 'required': false},
      {'key': 'freshness', 'label': {'en': 'Fresh / frozen'}, 'kind': 'choice', 'options': ['Fresh', 'Frozen'],
        'required': true},
    ],
  };

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    if (path == '/api/catalog/templates') {
      return ApiSuccess(<String, Object?>{
        'items': [
          {'key': 'meat_poultry', 'name': {'en': 'Meat, chicken & fish'}, 'items': 1},
        ],
      } as T);
    }
    if (path == '/api/catalog/templates/meat_poultry') return ApiSuccess(Map<String, Object?>.of(_meat) as T);
    return ApiSuccess(<String, Object?>{
      'items': [
        {'id': 7, 'subject': 'walking shoes', 'price': 2200, 'stock_status': 'UNKNOWN'},
        {'id': 8, 'subject': 'mango pickle', 'price': 300, 'stock_status': 'IN_STOCK'},
      ],
    } as T);
  }

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    deletes.add(path);
    return ApiSuccess(<String, Object?>{'removed': true} as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add((path, body));
    return ApiSuccess(<String, Object?>{'published': [], 'drafts': [{'item_key': 'chicken.curry_cut'}], 'skipped': []} as T);
  }

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

  Future<_Api> pumpListings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: MyListingsScreen()),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('removing a listing asks first; Keep does nothing, Remove deletes', (tester) async {
    final api = await pumpListings(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxRemoveListing-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(api.deletes, isEmpty, reason: 'no accidental removal');
    await tester.tap(find.byKey(const ValueKey('askodoxRemoveListing-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxConfirmRemoveListing')));
    await tester.pumpAndSettle();
    expect(api.deletes, ['/api/products/mine/7']);
  });

  testWidgets('search narrows the listings', (tester) async {
    await pumpListings(tester);
    expect(find.byKey(const ValueKey('askodoxMyListing-8')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxListingSearch')), 'pickle');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMyListing-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyListing-7')), findsNothing);
  });

  testWidgets('ready-made catalog: category details from the template; a required detail missing stays a draft',
      (tester) async {
    final api = await pumpListings(tester);
    await tester.tap(find.byKey(const Key('askodoxOpenCatalogTemplates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogTemplate-meat_poultry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('askodoxCataloguePrice-chicken.curry_cut')), '240');
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueDetails-chicken.curry_cut')));
    await tester.pumpAndSettle();
    expect(find.text('Fresh / frozen *'), findsOneWidget, reason: 'category attribute, marked required');
    await tester.tap(find.byKey(const ValueKey('askodoxCatalogueAttr-cut-Curry cut')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxCatalogueDetailsDone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxCatalogueShopName')), 'Ravi Chicken');
    await tester.enterText(find.byKey(const Key('askodoxCatalogueShopAddress')), 'Vuyyuru');
    await tester.tap(find.byKey(const Key('askodoxCatalogueReviewButton')));
    await tester.pumpAndSettle();
    expect(find.text('0 will be published'), findsOneWidget, reason: 'required detail missing -> draft');
    expect(api.posts, isEmpty, reason: 'nothing is published before the seller taps Publish');
    await tester.tap(find.byKey(const Key('askodoxCataloguePublish')));
    await tester.pumpAndSettle();
    final body = api.posts.single.$2! as Map;
    expect(api.posts.single.$1, '/api/catalog/templates/meat_poultry/publish');
    expect((body['items'] as List).single['attributes'], {'cut': 'Curry cut'});
    expect(find.byKey(const Key('askodoxCatalogPublished')), findsOneWidget);
  });
}
