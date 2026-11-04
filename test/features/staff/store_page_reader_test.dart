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
}
