import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/shops/domain/shop_link_install.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shop link phase 2 (owner 2026-11-25): made-up names only.
class _Api implements ApiClient {
  final posts = <String, Object?>{};
  bool offline = false;

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    if (offline) throw const ApiFailure(ApiFailureType.network);
    posts[path] = body;
    return ApiSuccess({'business_id': 'b9', 'slug': 'sita-sweets', 'name': 'Sita Sweets'} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('com.askodox.app/device');

  void referrer(String? text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(device, (call) async {
      if (call.method != 'installReferrer') return null;
      if (text == null) throw PlatformException(code: 'none');
      return text;
    });
  }

  test('the shop link name is read only from a shop-link referrer', () {
    expect(askodoxShopLinkSlugFromReferrer('utm_source=shop_link&utm_campaign=sita-sweets'), 'sita-sweets');
    expect(askodoxShopLinkSlugFromReferrer('utm_source=shop_link_join&utm_campaign=Ravi-Kirana'), 'ravi-kirana');
    expect(askodoxShopLinkSlugFromReferrer('utm_source=google-play&utm_medium=organic'), isNull);
    expect(askodoxShopLinkSlugFromReferrer('utm_source=shop_link&utm_campaign=../admin'), isNull);
    expect(askodoxShopLinkSlugFromReferrer(''), isNull);
  });

  test('an install from a shop link is told once and that shop is kept to open', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _Api();
    referrer('utm_source=shop_link&utm_campaign=sita-sweets');
    await askodoxReportShopLinkInstall(api, prefs);
    expect(api.posts['/api/pos/shop-links/installed'], {'slug': 'sita-sweets'});
    expect(await askodoxTakeShopLinkToOpen(prefs), 'b9');
    expect(await askodoxTakeShopLinkToOpen(prefs), isNull, reason: 'opened once');
    api.posts.clear();
    await askodoxReportShopLinkInstall(api, prefs);
    expect(api.posts, isEmpty, reason: 'never counted twice');
  });

  test('offline or no referrer service: asked again on the next start; an ordinary install is never asked again', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _Api()..offline = true;
    referrer('utm_source=shop_link&utm_campaign=sita-sweets');
    await askodoxReportShopLinkInstall(api, prefs);
    expect(prefs.getBool(askodoxShopLinkInstallAskedKey), isNull);
    referrer(null);
    await askodoxReportShopLinkInstall(api, prefs);
    expect(prefs.getBool(askodoxShopLinkInstallAskedKey), isNull);
    referrer('utm_source=google-play&utm_medium=organic');
    await askodoxReportShopLinkInstall(api, prefs);
    expect(prefs.getBool(askodoxShopLinkInstallAskedKey), isTrue);
  });
}
