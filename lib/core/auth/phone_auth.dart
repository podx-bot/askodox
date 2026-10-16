import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/push_registration.dart' show AskodoxFirebaseConfig;

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
  const AskodoxPhoneAuthFailed(this.code);
  final String code;
}

class AskodoxPhoneAuthError implements Exception {
  const AskodoxPhoneAuthError(this.code);
  final String code;
  @override
  String toString() => 'AskodoxPhoneAuthError($code)';
}

abstract class AskodoxPhoneAuth {
  /// This build can use Firebase phone sign-in (Firebase values present).
  bool get available;

  Future<AskodoxPhoneAuthStart> start(String e164, {int? resendToken});

  /// The Firebase ID token for the typed code (throws [AskodoxPhoneAuthError]).
  Future<String> confirm(String verificationId, String code);

  Future<void> signOut();
}

class FirebasePhoneAuth implements AskodoxPhoneAuth {
  const FirebasePhoneAuth();

  @override
  bool get available => AskodoxFirebaseConfig.configured;

  @override
  Future<AskodoxPhoneAuthStart> start(String e164, {int? resendToken}) async {
    if (!await AskodoxFirebaseConfig.ensureInitialized()) return const AskodoxPhoneAuthFailed('not-configured');
    final done = Completer<AskodoxPhoneAuthStart>();
    void finish(AskodoxPhoneAuthStart value) {
      if (!done.isCompleted) done.complete(value);
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          final user = (await FirebaseAuth.instance.signInWithCredential(credential)).user;
          final token = await user?.getIdToken();
          finish(token == null ? const AskodoxPhoneAuthFailed('no-id-token') : AskodoxPhoneAutoVerified(token));
        } on FirebaseAuthException catch (e) {
          finish(AskodoxPhoneAuthFailed(e.code));
        }
      },
      verificationFailed: (e) => finish(AskodoxPhoneAuthFailed(e.code)),
      codeSent: (verificationId, token) => finish(AskodoxPhoneCodeSent(verificationId, token)),
      codeAutoRetrievalTimeout: (_) {},
    );
    return done.future.timeout(const Duration(seconds: 90),
        onTimeout: () => const AskodoxPhoneAuthFailed('timeout'));
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
      throw AskodoxPhoneAuthError(e.code);
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
          'No connection. Check the internet and try again.',
          'కనెక్షన్ లేదు. ఇంటర్నెట్ చూసి మళ్లీ ప్రయత్నించండి.'
        ),
      'invalid-phone-number' => ('Enter a valid mobile number with country code.', 'కంట్రీ కోడ్‌తో సరైన మొబైల్ నంబర్ నమోదు చేయండి.'),
      _ => ('Verification failed. Try again.', 'ధృవీకరణ విఫలమైంది. మళ్లీ ప్రయత్నించండి.'),
    };
