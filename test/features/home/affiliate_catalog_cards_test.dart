import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

/// Records POST paths (click tracking).
class _Recorder implements ApiClient {
  final posts = <(String, Object?)>[];

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{} as T);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add((path, body));
    return ApiSuccess(<String, Object?>{'recorded': true} as T);
  }

  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => get<T>(path);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(Uri.parse('mock://$fileName'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A staff-catalog Meesho product exactly as /deals/discover returns it.
const _catalogRow = <String, Object?>{
  'id': 'catalog-7', 'match_id': 'catalog-7', 'provider_id': 'meesho', 'title': 'Women Cotton Kurti',
  'subtitle': 'Sri Fashions', 'price': 399, 'original_price': 999, 'discount_percent': 60, 'currency': 'INR',
  'price_verified': false, 'price_source': 'catalog', 'price_checked_at': '2026-10-03T12:00:00+00:00',
  'image_url': 'https://images.meesho.com/k.jpg', 'match_source': 'online', 'source': 'online',
  'origin': 'affiliate_catalog', 'source_name': 'Meesho', 'marketplace': 'meesho',
  'destination_url': 'https://www.meesho.com/women-cotton-kurti/p/4xyz',
  'web_fallback_url': 'https://www.meesho.com/women-cotton-kurti/p/4xyz', 'open_strategy': 'web',
  'affiliate': false, 'routing': 'organic', 'disclosure': '', 'sponsored': false, 'stock_status': 'IN_STOCK',
  'last_checked': '2026-10-03T12:00:00+00:00', 'demo': false,
};

void main() {
  test('catalog rows parse MRP, discount, stock, last checked and organic routing', () {
    final m = UniversalMatch.fromJson(_catalogRow);
    expect(m.source, 'online');
    expect(chatResultActionFor(m), ChatResultAction.openLink);
    expect(m.affiliate, isFalse, reason: 'organic routing is never labelled affiliate');
    expect(m.routing, 'organic');
    expect(askodoxPriceLabel(m, te: false), '₹399 (MRP ₹999, 60% off)');
    expect(askodoxPriceLabel(m, te: true), contains('తగ్గింపు'));
    expect(askodoxStockLabel(m, te: false), 'In stock');
    expect(askodoxCheckedLabel(m, te: false), startsWith('Checked 3 Oct'));
    // Round trip (History restore) keeps the new fields.
    final back = UniversalMatch.fromJson(m.toJson());
    expect(back.originalPrice, 999);
    expect(back.stockStatus, 'IN_STOCK');
    expect(back.lastChecked, isNotNull);
  });

  test('web-page prices stay "Page mentions" and unknown stock is never a fact', () {
    final web = UniversalMatch.fromJson(const {
      'id': 'marketplace-amazon-0', 'title': 'Cotton Kurti - Amazon.in', 'price': 499, 'price_verified': false,
      'price_source': 'page_text', 'source': 'online', 'marketplace': 'amazon', 'source_name': 'Amazon',
      'routing': 'organic', 'affiliate': false, 'destination_url': 'https://www.amazon.in/s?k=cotton+kurti',
    });
    expect(askodoxPriceLabel(web, te: false), 'Page mentions ₹499');
    expect(askodoxStockLabel(web, te: false), isNull);
    expect(askodoxCheckedLabel(web, te: false), isNull);
    final unknown = UniversalMatch.fromJson({..._catalogRow, 'stock_status': 'UNKNOWN', 'original_price': null});
    expect(askodoxStockLabel(unknown, te: false), isNull);
    expect(askodoxPriceLabel(unknown, te: false), '₹399');
  });

  test('external click tracking posts to the mounted /deals/external/click route', () async {
    final api = _Recorder();
    final repo = ApiUniversalMatchRepository(api, appUserId: 'app-1');
    final m = UniversalMatch.fromJson(_catalogRow);
    await repo.recordExternalClick(match: m, destinationUrl: m.destinationUrl!);
    expect(api.posts.single.$1, '/deals/external/click');
    expect((api.posts.single.$2 as Map)['provider_id'], 'meesho');
  });
}
