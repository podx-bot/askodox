import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:podx/core/auth/sms_code_listener.dart';
import 'package:podx/services/push_registration.dart' show AskodoxFirebaseConfig;

/// Emulator probe (CI firebase-receiver-ab): does Firebase Auth's own SMS
/// receiver crash when the SMS User Consent broadcast arrives, and does
/// `timeout: 0` (auto-retrieval off) prevent it? Uses a fictional +1 555
/// number: the reCAPTCHA is never completed and +1 is outside the project's
/// SMS region policy, so no SMS is ever sent to anyone. Test-only file.
const _timeoutSeconds = int.fromEnvironment('PROBE_TIMEOUT_SECONDS', defaultValue: 60);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Firebase receiver probe')))));
  final ok = await AskodoxFirebaseConfig.ensureInitialized();
  debugPrint('ASKODOX_PROBE firebase_init $ok timeout=$_timeoutSeconds');
  AndroidSmsUserConsent.instance.events.listen((e) => debugPrint('ASKODOX_PROBE consent ${e.event}'));
  await FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber: '+16505551234',
    timeout: Duration(seconds: _timeoutSeconds),
    verificationCompleted: (_) => debugPrint('ASKODOX_PROBE firebase completed'),
    verificationFailed: (e) => debugPrint('ASKODOX_PROBE firebase failed ${e.code}'),
    codeSent: (_, __) => debugPrint('ASKODOX_PROBE firebase code_sent'),
    codeAutoRetrievalTimeout: (_) => debugPrint('ASKODOX_PROBE firebase auto_retrieval_timeout'),
  );
  debugPrint('ASKODOX_PROBE firebase verify_requested');
  final started = await AndroidSmsUserConsent.instance.start();
  debugPrint('ASKODOX_PROBE consent_start $started');
}
