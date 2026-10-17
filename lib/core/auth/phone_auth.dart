import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/push_registration.dart' show AskodoxFirebaseConfig;
import 'auth_log.dart';

/// Firebase phone sign-in behind one seam (tests use a fake).
///
/// Firebase sends the SMS and proves the number; the app then hands the
/// Firebase ID token to ASKODOX (POST /onboarding/firebase/verify), which
/// verifies it on the server before any session exists. The code itself is
/// never stored or logged.
sealed class AskodoxPhoneAuthStart {
  const AskodoxPhoneAuthStart();
}

class AskodoxPhoneCodeSent extends AskodoxPhoneAuthStart {
  const AskodoxPhoneCodeSent(this.verificationId, this.resendToken);
  final String verificationId;
  final int? resendToken;
}

/// Android verified the SMS by itself (auto-retrieval / instant verification).
class AskodoxPhoneAutoVerified extends AskodoxPhoneAuthStart {
  const AskodoxPhoneAutoVerified(this.idToken);
  final String idToken;
}

class AskodoxPhoneAuthFailed extends AskodoxPhoneAuthStart {
  const AskodoxPhoneAuthFailed(this.code, [this.detail]);
  final String code;

  /// Firebase's own message (digits redacted) -- shown for 'unknown' errors.
  final String? detail;
}

/// ONE Firebase phone verification, whatever order its callbacks arrive in.
///
/// Firebase can call `verificationFailed` and still send the SMS and call
/// `codeSent` afterwards (seen on APK 1334 after the reCAPTCHA browser step:
/// "Firebase: unknown" while the SMS arrived). A one-shot "first callback
/// wins" result then hides the code step forever. Here:
/// * a SOFT failure (unknown / web-context / missing-activity ...) waits
///   [grace] for a `codeSent` before it is reported;
/// * `codeSent` / auto-verification arriving AFTER a reported failure are
///   delivered to [onLate] (the screen then opens the code step);
/// * a failure arriving after `codeSent` never overrides it (no false error,
///   no false success: the code step still needs the real SMS code).
class AskodoxPhoneVerificationSession {
  AskodoxPhoneVerificationSession({this.grace = const Duration(seconds: 25), this.onLate});

  static const softFailures = {
    'unknown',
    'web-context-cancelled',
    'web-context-already-presented',
    'web-internal-error',
    'web-network-request-failed',
    'missing-activity-for-recaptcha',
  };

  final Duration grace;
  final void Function(AskodoxPhoneAuthStart event)? onLate;
  final _done = Completer<AskodoxPhoneAuthStart>();
  Timer? _graceTimer;
  AskodoxPhoneAuthFailed? _pending;

  Future<AskodoxPhoneAuthStart> get result => _done.future;
  bool get settled => _done.isCompleted;

  void _settle(AskodoxPhoneAuthStart event) {
    if (!_done.isCompleted) {
      _graceTimer?.cancel();
      askodoxAuthLog('firebase.settled', {
        'result': switch (event) {
          AskodoxPhoneCodeSent() => 'code_sent',
          AskodoxPhoneAutoVerified() => 'auto_verified',
          AskodoxPhoneAuthFailed(:final code) => 'failed_$code',
        },
      });
      _done.complete(event);
    } else if (event is! AskodoxPhoneAuthFailed) {
      askodoxAuthLog('firebase.late_event', {'event': event is AskodoxPhoneCodeSent ? 'code_sent' : 'auto_verified'});
      onLate?.call(event);
    }
  }

  void codeSent(String verificationId, int? resendToken) {
    askodoxAuthLog('firebase.code_sent', {'after_failure': _pending != null || settled});
    _settle(AskodoxPhoneCodeSent(verificationId, resendToken));
  }

  void autoVerified(String idToken) {
    askodoxAuthLog('firebase.auto_verified', {'after_failure': _pending != null || settled});
    _settle(AskodoxPhoneAutoVerified(idToken));
  }

  void failed(String code, [String? message]) {
    final detail = message == null ? null : askodoxRedactDigits(message).trim();
    askodoxAuthLog('firebase.verification_failed', {'code': code, 'settled': settled, 'message': detail ?? ''});
    if (_done.isCompleted) return; // never overrides a code that was already sent
    final failure = AskodoxPhoneAuthFailed(code, detail);
    if (softFailures.contains(code)) {
      _pending ??= failure;
      _graceTimer ??= Timer(grace, () => _settle(_pending!));
      return;
    }
    _settle(failure);
  }

  /// No answer at all in time: the pending soft failure, else 'timeout'.
  void expire() {
    askodoxAuthLog('firebase.expired', {'pending': _pending?.code ?? 'none', 'settled': settled});
    _settle(_pending ?? const AskodoxPhoneAuthFailed('timeout'));
  }

  void dispose() => _graceTimer?.cancel();
}

class AskodoxPhoneAuthError implements Exception {
  const AskodoxPhoneAuthError(this.code, [this.detail]);
  final String code;

  /// Firebase's own message (digits redacted) -- shown for 'unknown' errors.
  final String? detail;
  @override
  String toString() => 'AskodoxPhoneAuthError($code)';
}

abstract class AskodoxPhoneAuth {
  /// This build can use Firebase phone sign-in (Firebase values present).
  bool get available;

  /// Starts verification. [onLate] receives a `codeSent` / auto-verification
  /// that arrives after the returned result (see AskodoxPhoneVerificationSession).
  Future<AskodoxPhoneAuthStart> start(String e164,
      {int? resendToken, void Function(AskodoxPhoneAuthStart event)? onLate});

  /// The Firebase ID token for the typed code (throws [AskodoxPhoneAuthError]).
  Future<String> confirm(String verificationId, String code);

  Future<void> signOut();
}

class FirebasePhoneAuth implements AskodoxPhoneAuth {
  const FirebasePhoneAuth();

  @override
  bool get available => AskodoxFirebaseConfig.configured;

  @override
  Future<AskodoxPhoneAuthStart> start(String e164,
      {int? resendToken, void Function(AskodoxPhoneAuthStart event)? onLate}) async {
    try {
      if (!await AskodoxFirebaseConfig.ensureInitialized()) return const AskodoxPhoneAuthFailed('not-configured');
    } on FirebaseException catch (e) {
      return AskodoxPhoneAuthFailed('init-${e.code}');
    } catch (_) {
      return const AskodoxPhoneAuthFailed('init-failed');
    }
    try {
      return await _start(e164, resendToken, onLate);
    } on FirebaseAuthException catch (e) {
      askodoxAuthLog('firebase.start_exception', {'code': e.code});
      return AskodoxPhoneAuthFailed(e.code, e.message == null ? null : askodoxRedactDigits(e.message!));
    } on FirebaseException catch (e) {
      return AskodoxPhoneAuthFailed(e.code);
    } catch (e) {
      // Platform errors (e.g. a missing native config) must never leave the
      // button spinning silently.
      return AskodoxPhoneAuthFailed('platform-${e.runtimeType}');
    }
  }

  Future<AskodoxPhoneAuthStart> _start(
      String e164, int? resendToken, void Function(AskodoxPhoneAuthStart event)? onLate) async {
    // The callbacks stay registered after this method returns; the session
    // routes anything that arrives later to [onLate].
    final session = AskodoxPhoneVerificationSession(onLate: onLate);
    askodoxAuthLog('firebase.verify_start', {'resend': resendToken != null});
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          final user = (await FirebaseAuth.instance.signInWithCredential(credential)).user;
          final token = await user?.getIdToken();
          if (token == null) {
            session.failed('no-id-token');
          } else {
            session.autoVerified(token);
          }
        } on FirebaseAuthException catch (e) {
          session.failed(e.code, e.message);
        }
      },
      verificationFailed: (e) => session.failed(e.code, e.message),
      codeSent: (verificationId, token) => session.codeSent(verificationId, token),
      codeAutoRetrievalTimeout: (_) => askodoxAuthLog('firebase.auto_retrieval_timeout'),
    );
    askodoxAuthLog('firebase.verify_requested');
    // The reCAPTCHA browser step can take a while; the session itself waits.
    final expiry = Timer(const Duration(seconds: 120), session.expire);
    try {
      return await session.result;
    } finally {
      expiry.cancel();
    }
  }

  @override
  Future<String> confirm(String verificationId, String code) async {
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);
      final user = (await FirebaseAuth.instance.signInWithCredential(credential)).user;
      final token = await user?.getIdToken();
      if (token == null) throw const AskodoxPhoneAuthError('no-id-token');
      return token;
    } on FirebaseAuthException catch (e) {
      final detail = e.message == null ? null : askodoxRedactDigits(e.message!).trim();
      askodoxAuthLog('firebase.confirm_failed', {'code': e.code, 'message': detail ?? ''});
      throw AskodoxPhoneAuthError(e.code, detail);
    } on AskodoxPhoneAuthError {
      rethrow;
    } catch (e) {
      throw AskodoxPhoneAuthError('platform-${e.runtimeType}');
    }
  }

  @override
  Future<void> signOut() async {
    if (!AskodoxFirebaseConfig.configured) return;
    try {
      if (await AskodoxFirebaseConfig.ensureInitialized()) await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}

final askodoxPhoneAuthProvider = Provider<AskodoxPhoneAuth>((ref) => const FirebasePhoneAuth());

/// What to tell the person for a Firebase error code (English, Telugu).
(String, String) askodoxPhoneAuthMessage(String code) => switch (code) {
      'invalid-verification-code' => ('Incorrect OTP.', 'OTP తప్పు.'),
      'session-expired' || 'code-expired' => ('OTP expired. Request a new OTP.', 'OTP గడువు ముగిసింది. కొత్త OTP అడగండి.'),
      'too-many-requests' || 'quota-exceeded' => (
          'Too many attempts. Please wait and try again.',
          'చాలా ప్రయత్నాలు. కొద్దిసేపు ఆగి మళ్లీ ప్రయత్నించండి.'
        ),
      'network-request-failed' || 'timeout' => (
          'The connection to Google broke while sending the code. Check the internet, stay in ASKODOX until the code '
              'arrives, and try again.',
          'కోడ్ పంపుతున్నప్పుడు Googleతో కనెక్షన్ తెగిపోయింది. ఇంటర్నెట్ చూసి, కోడ్ వచ్చే వరకు ASKODOXలోనే ఉండి, మళ్లీ ప్రయత్నించండి.'
        ),
      'invalid-phone-number' => ('Enter a valid mobile number with country code.', 'కంట్రీ కోడ్‌తో సరైన మొబైల్ నంబర్ నమోదు చేయండి.'),
      'app-not-authorized' || 'invalid-app-credential' || 'missing-client-identifier' => (
          'This app is not yet authorised for phone sign-in in Firebase (release SHA fingerprints).',
          'Firebaseలో ఈ యాప్‌కు ఫోన్ సైన్-ఇన్ అనుమతి ఇంకా లేదు (release SHA fingerprints).'
        ),
      'operation-not-allowed' => (
          'Phone sign-in is not switched on in Firebase.',
          'Firebaseలో ఫోన్ సైన్-ఇన్ ఆన్ చేయలేదు.'
        ),
      _ => ('Verification failed. Try again.', 'ధృవీకరణ విఫలమైంది. మళ్లీ ప్రయత్నించండి.'),
    };

/// A Firebase failure caused by the network connection itself (the request
/// never got its answer) -- Firebase reports some of them as 'unknown' with the
/// socket error in its message ("Software caused connection abort" = Android
/// closed the app's connection, e.g. while the app was in the background
/// during the browser check). Never a sent code: the person must retry.
bool askodoxPhoneAuthNetworkFailure(String code, [String? detail]) {
  if (code == 'network-request-failed' || code == 'timeout') return true;
  if (code != 'unknown' && code != 'internal-error') return false;
  final text = (detail ?? '').toLowerCase();
  const signs = [
    'connection abort', 'connection reset', 'network', 'timeout', 'timed out', 'unable to resolve host',
    'failed to connect', 'unreachable', 'broken pipe', 'socket',
  ];
  return signs.any(text.contains);
}
