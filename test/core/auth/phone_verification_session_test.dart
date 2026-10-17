import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_log.dart';
import 'package:podx/core/auth/phone_auth.dart';

/// Every order in which Firebase's verifyPhoneNumber callbacks can arrive.
void main() {
  const grace = Duration(milliseconds: 60);
  final logs = <String>[];
  late void Function(String) previous;
  setUp(() {
    logs.clear();
    previous = askodoxAuthLogSink;
    askodoxAuthLogSink = logs.add;
  });
  tearDown(() => askodoxAuthLogSink = previous);

  test('codeSent alone opens the code step', () async {
    final s = AskodoxPhoneVerificationSession(grace: grace)..codeSent('vid', 1);
    final r = await s.result;
    expect(r, isA<AskodoxPhoneCodeSent>());
    expect((r as AskodoxPhoneCodeSent).verificationId, 'vid');
  });

  test('APK 1334: "unknown" around reCAPTCHA, then codeSent -> the code step, no error', () async {
    final late = <AskodoxPhoneAuthStart>[];
    final s = AskodoxPhoneVerificationSession(grace: grace, onLate: late.add)
      ..failed('unknown', 'An internal error has occurred.');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.codeSent('vid-after-recaptcha', 9);
    final r = await s.result;
    expect(r, isA<AskodoxPhoneCodeSent>(), reason: 'the verification id from Firebase is kept');
    expect((r as AskodoxPhoneCodeSent).verificationId, 'vid-after-recaptcha');
    expect(late, isEmpty);
  });

  test('"unknown" and no codeSent: reported after the grace window, with Firebase message', () async {
    final s = AskodoxPhoneVerificationSession(grace: grace)..failed('unknown', 'Error for +91 98765 43210');
    final r = await s.result as AskodoxPhoneAuthFailed;
    expect(r.code, 'unknown');
    expect(r.detail, isNot(contains('98765')), reason: 'digits redacted');
  });

  test('hard failure is immediate; a codeSent that still arrives goes to onLate', () async {
    final late = <AskodoxPhoneAuthStart>[];
    final s = AskodoxPhoneVerificationSession(grace: grace, onLate: late.add)..failed('too-many-requests');
    expect((await s.result as AskodoxPhoneAuthFailed).code, 'too-many-requests');
    s.codeSent('vid-late', null);
    expect(late.single, isA<AskodoxPhoneCodeSent>());
  });

  test('a failure after codeSent never overrides it (no false error)', () async {
    final late = <AskodoxPhoneAuthStart>[];
    final s = AskodoxPhoneVerificationSession(grace: grace, onLate: late.add)
      ..codeSent('vid', 1)
      ..failed('session-expired');
    expect(await s.result, isA<AskodoxPhoneCodeSent>());
    expect(late, isEmpty);
  });

  test('auto-verification after a soft failure wins; expire reports pending / timeout', () async {
    final s = AskodoxPhoneVerificationSession(grace: const Duration(seconds: 5))
      ..failed('web-context-cancelled')
      ..autoVerified('id-token');
    expect(await s.result, isA<AskodoxPhoneAutoVerified>());
    final pending = AskodoxPhoneVerificationSession(grace: const Duration(seconds: 5))..failed('unknown');
    pending.expire();
    expect((await pending.result as AskodoxPhoneAuthFailed).code, 'unknown');
    final silent = AskodoxPhoneVerificationSession()..expire();
    expect((await silent.result as AskodoxPhoneAuthFailed).code, 'timeout');
  });

  test('logs carry codes and order, never numbers', () async {
    final s = AskodoxPhoneVerificationSession(grace: grace)..failed('unknown', 'msg 9876543210');
    s.codeSent('vid', 1);
    await s.result;
    expect(logs.any((l) => l.contains('firebase.verification_failed') && l.contains('code=unknown')), isTrue);
    expect(logs.any((l) => l.contains('firebase.code_sent') && l.contains('after_failure=true')), isTrue);
    expect(logs.join('\n'), isNot(contains('9876543210')));
  });
}
