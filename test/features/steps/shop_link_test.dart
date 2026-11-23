import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/domain/shop_link_logic.dart';
import 'package:podx/features/steps/presentation/shop_link_steps_screen.dart';

/// Owner 2026-11-22: the shop's one free public page `askodox.com/s/<name>`, made in 3 steps. Made-up shop data only.
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp phone
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

const _shop = {'name': 'Test Chicken Centre', 'phone': '9400000401', 'template': 'meat_fish', 'address': 'Main road'};

void main() {
  group('slug rules (same as the server)', () {
    test('clean + problems', () {
      expect(askodoxCleanSlug(' Test Chicken & Mutton '), 'test-chicken-mutton');
      expect(askodoxCleanSlug('--a__b..c--'), 'a-b-c');
      expect(askodoxCleanSlug('చికెన్ షాప్'), '');
      expect(askodoxSlugProblem('ab'), 'too_short');
      expect(askodoxSlugProblem('admin'), 'reserved');
      expect(askodoxSlugProblem('askodox-deals'), 'reserved');
      expect(askodoxSlugProblem('test-chicken'), '');
      expect(askodoxSlugProblemText('', true), isNull);
      expect(askodoxShopLinkShareText('Shop', 'https://askodox.com/s/shop-1', false), contains('https://askodox.com/s/shop-1'));
      expect(askodoxLinkCount({'week': {'order_wa': 2, 'order_app': 1, 'view': 9}}, 'week', ['order_wa', 'order_app']), 3);
      expect(askodoxLinkCount(const {}, 'today', ['view']), 0);
    });
  });

  testWidgets('owner: what to show -> colour + name -> ✓ link with copy / QR / open', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'GET' && path.endsWith('/link')) {
        return {'link': null, 'can_change': true, 'suggested_slug': 'test-chicken-centre', 'has_upi': false, 'shop': _shop,
          'stats': {'today': {}, 'week': {}, 'month': {}}};
      }
      if (path.endsWith('/link/check')) return {'ok': true, 'problem': ''};
      if (method == 'PUT' && path.endsWith('/link')) {
        final b = body as Map;
        return {'link': {'slug': b['slug'], 'enabled': true, 'url': 'https://askodox.com/s/${b['slug']}', ...b}};
      }
      return {};
    });
    await _pump(tester, api, const AskodoxShopLinkStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxShopLink1')), findsOneWidget);
    expect(find.text('What should the link show?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('askodoxShopLinkShow-call')));
    await tester.tap(find.byKey(const Key('askodoxShopLinkShow-call')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxShopLinkNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxShopLink2')), findsOneWidget);
    expect(find.text('test-chicken-centre'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxShopLinkSlug')), 'AB');
    await tester.pump();
    expect(find.text('At least 3 letters (English)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxShopLinkSlug')), 'Test Chicken Vuyyuru');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(api.calls.containsKey('GET /api/pos/businesses/b1/link/check'), isTrue);
    await tester.tap(find.byKey(const Key('askodoxShopLinkColor-maroon')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxShopLinkSave')));
    await tester.pumpAndSettle();
    final sent = api.calls['PUT /api/pos/businesses/b1/link'] as Map;
    expect(sent['slug'], 'test-chicken-vuyyuru');
    expect(sent['show_call'], isFalse);
    expect(sent['color'], 'maroon');
    expect(sent['whatsapp'], '9400000401');
    expect(find.byKey(const Key('askodoxShopLink3')), findsOneWidget);
    expect(find.text('askodox.com/s/test-chicken-vuyyuru'), findsOneWidget);
    expect(find.byKey(const Key('askodoxShopLinkPoster')), findsOneWidget);
    expect(find.byKey(const Key('askodoxShopLinkSend')), findsOneWidget);
  });

  testWidgets('a manager: no link yet -> only the owner can make it; a made link opens on ✓', (tester) async {
    var made = false;
    final api = _Api((method, path, body) {
      if (path.endsWith('/link')) {
        return {
          'link': made ? {'slug': 'test-chicken', 'enabled': true, 'url': 'https://askodox.com/s/test-chicken'} : null,
          'can_change': false, 'suggested_slug': 'test-chicken', 'shop': _shop,
          'stats': {'today': {'view': 4}, 'week': {'view': 30, 'order_wa': 5}, 'month': {}},
        };
      }
      return {};
    });
    await _pump(tester, api, const AskodoxShopLinkStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxShopLinkNotOwner')), findsOneWidget);
    made = true;
    await _pump(tester, api, const AskodoxShopLinkStepsScreen(key: ValueKey('again'), businessId: 'b1'));
    expect(find.byKey(const Key('askodoxShopLink3')), findsOneWidget);
    expect(find.text('askodox.com/s/test-chicken'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a shop without a phone: the WhatsApp box starts with the owner number and says why', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/link')) {
        return {'link': null, 'can_change': true, 'suggested_slug': 'no-phone', 'has_upi': false,
          'whatsapp_default': '9400000411', 'shop': {'name': 'No Phone', 'phone': '', 'template': 'kirana'},
          'stats': {'today': {}, 'week': {}, 'month': {}}};
      }
      return {};
    });
    await _pump(tester, api, const AskodoxShopLinkStepsScreen(businessId: 'b2'));
    await tester.ensureVisible(find.byKey(const Key('askodoxShopLinkWhatsapp')));
    expect(find.text('9400000411'), findsOneWidget);
    expect(find.textContaining('Link orders come into your ASKODOX Live orders'), findsOneWidget);
  });
}
