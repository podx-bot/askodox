import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/staff/askodox_staff_access.dart';

void main() {
  group('phone page reader (Meesho refuses the server, not a phone)', () {
    final base = Uri.parse('https://www.meesho.com/af_invite/142910812');

    test('an invite page that forwards with meta refresh -> the product page', () {
      const html = '<html><head><meta http-equiv="refresh" content="0; url=/cotton-saree/p/4abcd?x=1&amp;y=2"></head></html>';
      expect(askodoxMetaRefreshTarget(html, base).toString(), 'https://www.meesho.com/cotton-saree/p/4abcd?x=1&y=2');
    });

    test('no refresh, or a non-https target -> nothing to follow', () {
      expect(askodoxMetaRefreshTarget('<html><title>Saree</title></html>', base), isNull);
      expect(askodoxMetaRefreshTarget('<meta http-equiv="refresh" content="0;url=http://x.example/a">', base), isNull);
    });

    test('only https pages are read', () async {
      expect(() => askodoxReadStorePage(Uri.parse('http://www.meesho.com/x')), throwsA(isA<FormatException>()));
    });
  });

  group('reading a store link until the product is there (owner 2026-11-06: no hand filling)', () {
    const invite = '<html><head><title>Meesho</title></head><body>Download the app</body></html>';
    const product = '<html><head><script type="application/ld+json">{"@type": "Product", "name": "Mug"}</script>'
        '</head><body></body></html>';
    const nextData = '<script id="__NEXT_DATA__" type="application/json">{"product_name":"Mug","min_product_price":99}</script>';

    test('an invite / open-in-app page is not a product page; product data is', () {
      expect(askodoxLooksLikeProductPage(invite), isFalse);
      expect(askodoxLooksLikeProductPage(product), isTrue);
      expect(askodoxLooksLikeProductPage(nextData), isTrue);
      expect(askodoxLooksLikeProductPage('<meta property="og:type" content="product">'), isTrue);
    });

    test('an app link gives back its https browser fallback, never the app', () {
      const link = 'intent://p/123#Intent;scheme=meesho;package=com.meesho.supply;'
          'S.browser_fallback_url=https%3A%2F%2Fwww.meesho.com%2Fmug%2Fp%2F123;end';
      expect(askodoxIntentFallback(link).toString(), 'https://www.meesho.com/mug/p/123');
      expect(askodoxIntentFallback('meesho://p/123'), isNull);
    });

    test('a page too big to send keeps only what the server reads', () {
      final big = '<html><head><title>Mug</title><meta property="og:title" content="Mug">$nextData</head>'
          '<body>${'x' * 5000}</body></html>';
      final compact = askodoxCompactStoreHtml(big, max: 1000);
      expect(compact.length, lessThan(1000));
      expect(compact, contains('og:title'));
      expect(compact, contains('__NEXT_DATA__'));
      expect(compact, isNot(contains('xxxx')));
      expect(askodoxCompactStoreHtml('<p>small</p>'), '<p>small</p>');
    });

    final url = Uri.parse('https://www.meesho.com/af_invite/142910812');

    test('the reader that finds the product wins, even when the other is slow', () async {
      final slow = Completer<AskodoxStorePage>();
      final page = await askodoxReadStoreBest(url,
          plain: (_) => slow.future,
          browser: (u) async => AskodoxStorePage(product, Uri.parse('https://www.meesho.com/mug/p/1')));
      expect(page.html, product);
      slow.complete(AskodoxStorePage(invite, url));
    });

    test('no product anywhere: the longest page that loaded is still sent', () async {
      final page = await askodoxReadStoreBest(url,
          plain: (_) async => throw const HttpExceptionLike('HTTP 403'),
          browser: (u) async => AskodoxStorePage(invite, u));
      expect(page.html, invite);
    });

    test('both readers fail: the failure reaches the page', () async {
      await expectLater(
          askodoxReadStoreBest(url,
              plain: (_) async => throw TimeoutException('slow'), browser: (_) async => throw TimeoutException('slow')),
          throwsA(isA<TimeoutException>()));
      expect(askodoxReadFailureText(TimeoutException('x')), 'timeout');
    });
  });

  group('page file boxes (owner 2026-11-06: the Video box did nothing)', () {
    test('a video box opens the video picker, photo boxes keep the photo picker', () {
      expect(askodoxWantsVideo(['video/mp4,video/webm,video/quicktime']), isTrue);
      expect(askodoxWantsVideo(['video/mp4', 'video/webm']), isTrue);
      expect(askodoxWantsVideo(['.mp4']), isTrue);
      expect(askodoxWantsVideo(['image/*']), isFalse);
      expect(askodoxWantsVideo(['image/*', 'video/mp4']), isFalse);
      expect(askodoxWantsVideo(const []), isFalse);
    });
  });
}

class HttpExceptionLike implements Exception {
  const HttpExceptionLike(this.message);
  final String message;
}
