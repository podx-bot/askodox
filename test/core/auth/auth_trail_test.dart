import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_log.dart';

void main() {
  test('sign-in trail: ordered, timed, private fields left out, digits redacted, bounded', () {
    final trail = AskodoxAuthTrail()..reset();
    trail.add('send_otp.tap', {'number': '••••3210', 'path': 'firebase'});
    trail.add('app.lifecycle', {'state': 'paused'});
    trail.add('firebase.verification_failed',
        {'code': 'unknown', 'message': 'An internal error has occurred. [ Software caused connection abort ] 9876543210'});
    trail.add('verify_otp.tap', {'otp': '123456', 'token': 'abc'});
    final lines = trail.lines;
    expect(lines[0], matches(RegExp(r'^\+\d+ms send_otp\.tap path=firebase$')));
    expect(lines[1], endsWith('app.lifecycle state=paused'));
    expect(lines[2], contains('code=unknown message=An_internal_error_has_occurred._[_Software_caused_connection_abort_]_[redacted]'));
    expect(lines[3], endsWith('verify_otp.tap'));
    expect(lines.join(' '), isNot(contains('3210')));
    expect(lines.join(' '), isNot(contains('123456')));
    for (var i = 0; i < 100; i++) {
      trail.add('x.y');
    }
    expect(trail.lines, hasLength(AskodoxAuthTrail.maxLines));
    trail.reset();
    expect(trail.lines, isEmpty);
  });
}
