import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/update/askodox_update_service.dart';

void main() {
  const hex = 'e6b77aa2b91eca5b84a1b2c7c1a17b941bfaeb30d84ddf4e375dd7ee2c4661df';

  test('checksums are normalised from latest.json and GitHub asset digests', () {
    expect(askodoxNormalizeSha256('sha256:${hex.toUpperCase()}'), hex);
    expect(askodoxNormalizeSha256(hex), hex);
    expect(askodoxNormalizeSha256('md5:abc'), '');
    expect(askodoxNormalizeSha256(''), '');
  });

  test('an update installs only when the published checksum matches the download', () {
    expect(askodoxApkDigestMatches(hex, hex), isTrue);
    expect(askodoxApkDigestMatches('sha256:$hex', hex), isTrue);
    expect(askodoxApkDigestMatches(hex, hex.replaceFirst('e', 'f')), isFalse, reason: 'tampered / corrupted');
    expect(askodoxApkDigestMatches('', hex), isFalse, reason: 'no published checksum -> never installed');
  });

  test('manifest carries the checksum', () {
    final info = AskodoxUpdateInfo.fromJson({
      'version': '1.0.1324', 'build_number': 1324, 'apk_url': 'https://x/askodox-1324.apk', 'sha256': hex,
    });
    expect(info.sha256, hex);
    expect(AskodoxUpdateInfo.fromJson({'build_number': 1, 'apk_url': 'u'}).sha256, '');
  });
}
