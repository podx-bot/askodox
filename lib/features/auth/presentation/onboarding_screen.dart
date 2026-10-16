import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/localization/askodox_language_catalog.dart';
import '../../../core/api/api_models.dart';
import '../../../core/auth/app_restart.dart';
import '../../../core/auth/auth_log.dart';
import '../../../core/auth/phone_auth.dart';
import '../../../core/auth/phone_number.dart';
import '../../../core/auth/sign_out.dart' show askodoxRestoreAccountData;
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/providers/backend_providers.dart';
import '../../home/domain/active_role.dart';
import '../../profile/data/user_profile_repository.dart';


/// Digits of the server's account id ("app-phone-919876543210" ->
/// "919876543210"); null when the server sent none (older backend).
String? askodoxAccountDigits(String? appUserId) {
  final m = RegExp(r'^app-phone-(\d{10,15})$').firstMatch((appUserId ?? '').trim());
  return m?.group(1);
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.signIn = false});

  /// Opened from an action that needs identity (send a request, contact a
  /// seller): straight to phone + OTP, then back to where the user was.
  final bool signIn;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Roles a new person can pick at sign-up (server key, app role, en, te).
/// "Buy & request" is always on; the others add sections later in Profile.
const askodoxSignUpRoles = <(String, AskodoxUserRole, String, String)>[
  ('buyer', AskodoxUserRole.buyer, 'Buy & request', 'కొనడం & అభ్యర్థించడం'),
  ('seller', AskodoxUserRole.seller, 'Sell products', 'ఉత్పత్తులు అమ్మడం'),
  ('service_provider', AskodoxUserRole.serviceProvider, 'Offer services', 'సేవలు అందించడం'),
  ('job_seeker', AskodoxUserRole.jobSeeker, 'Find work', 'పని వెతకడం'),
  ('delivery_partner', AskodoxUserRole.deliveryPartner, 'Deliver or drive', 'డెలివరీ / డ్రైవ్ చేయడం'),
];

/// Seconds to wait from a 429 answer (Retry-After header, else "wait N seconds").
int? askodoxRetryAfterSeconds(ApiFailure failure) {
  final header = int.tryParse(failure.header('retry-after') ?? '');
  if (header != null) return header;
  final m = RegExp(r'(\d+)\s*second').firstMatch(failure.message ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _completeKey = 'askodox.onboarding.complete';
  static const _mobileKey = 'askodox.profile.mobile';
  static const _nameKey = 'askodox.profile.name';
  static const _localeKey = 'askodox.locale';
  // The real signed session token (POST /onboarding/otp/verify or
  // /onboarding/firebase/verify); main.dart reads it back on start.
  static const _tokenKey = 'askodox.auth.token';

  final _mobile = TextEditingController(text: '+91 ');
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'askodox-name-focus');
  String? _verifiedToken;
  // The server's ONE account id for this number ("app-phone-<digits>").
  String? _verifiedAccount;
  bool _returning = false;
  final Set<String> _roles = {'buyer'};

  // Which way the number is proven: Firebase phone sign-in (only when the
  // server says it is switched on AND this build has Firebase) or the
  // server's own code (WhatsApp / SMS).
  bool _useFirebase = false;
  bool _serverOtp = true;
  int _resendSeconds = 45;
  String? _verificationId;
  int? _resendToken;
  String? _e164;
  // How the last code was sent ("whatsapp", "sms", "firebase"); shown on the code step.
  String? _channel;
  int _attempt = 0;
  int _resendIn = 0;
  Timer? _resendTimer;

  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  bool _usingDeviceLanguage = true;
  String _languageCode = 'en';
  String? _error;
  bool _canRetry = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_completeKey) == true && !widget.signIn) {
      context.go('/');
      return;
    }
    if (widget.signIn) {
      _name.text = prefs.getString(_nameKey)?.trim() ?? '';
      final mobile = prefs.getString(_mobileKey)?.trim() ?? '';
      if (mobile.isNotEmpty) _mobile.text = askodoxE164(mobile) ?? mobile;
      _step = 1;
    }

    final saved = prefs.getString(_localeKey)?.trim();
    if (AskodoxLanguageCatalog.supports(saved)) {
      _languageCode = AskodoxLanguageCatalog.normalize(saved);
      _usingDeviceLanguage = false;
      // Language already chosen on this phone (e.g. after sign-out): start at
      // the number; the language stays one tap away.
      _step = 1;
    } else {
      _languageCode = _deviceLanguageCode();
      _usingDeviceLanguage = true;
      ref.read(appSettingsProvider.notifier).useSystemLocale();
    }
    setState(() => _loading = false);
    unawaited(_loadMethods());
  }

  /// Best effort: an older server (or the offline mock) without this route
  /// keeps the server code as the way in.
  Future<void> _loadMethods() async {
    ApiResult<Map<String, dynamic>> result;
    try {
      result = await ref.read(apiClientProvider).get<Map<String, dynamic>>('/onboarding/methods');
    } catch (_) {
      return;
    }
    if (!mounted || result is! ApiSuccess<Map<String, dynamic>>) return;
    final data = result.data;
    setState(() {
      _useFirebase = data['firebase_phone_auth'] == true && ref.read(askodoxPhoneAuthProvider).available;
      _serverOtp = data['server_otp'] != false;
      _resendSeconds = (data['resend_seconds'] as num?)?.toInt() ?? 45;
    });
  }

  String _deviceLanguageCode() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return AskodoxLanguageCatalog.supports(code)
        ? AskodoxLanguageCatalog.normalize(code)
        : AskodoxLanguageCatalog.english.code;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _mobile.dispose();
    _otp.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _t(String key) {
    const values = <String, Map<String, String>>{
      'step': {'en': 'Step', 'te': 'దశ', 'hi': 'चरण'},
      'of': {'en': 'of', 'te': 'లో', 'hi': 'में से'},
      'languageTitle': {'en': 'Language', 'te': 'భాష', 'hi': 'भाषा'},
      'autoSelected': {
        'en': 'Device language selected automatically',
        'te': 'డివైస్ భాష ఆటోమేటిక్‌గా ఎంపికైంది',
        'hi': 'डिवाइस की भाषा अपने-आप चुनी गई है',
      },
      'changeLanguage': {'en': 'Or choose another language', 'te': 'లేదా మరో భాషను ఎంచుకోండి', 'hi': 'या दूसरी भाषा चुनें'},
      'continue': {'en': 'Continue', 'te': 'కొనసాగించండి', 'hi': 'जारी रखें'},
      'mobileTitle': {'en': 'Sign in or create your account', 'te': 'సైన్ ఇన్ చేయండి లేదా ఖాతా సృష్టించండి', 'hi': 'साइन इन करें या खाता बनाएं'},
      'otpInfo': {
        'en': 'Enter your mobile number. We will send a 6-digit verification code.',
        'te': 'మీ మొబైల్ నంబర్ నమోదు చేయండి. 6 అంకెల వెరిఫికేషన్ కోడ్ పంపిస్తాము.',
        'hi': 'अपना मोबाइल नंबर दर्ज करें। हम 6 अंकों का सत्यापन कोड भेजेंगे।',
      },
      'countryHint': {
        'en': 'India: just the 10 digits. Other countries: start with + and the country code.',
        'te': 'భారత్: 10 అంకెలు చాలు. ఇతర దేశాలు: + మరియు కంట్రీ కోడ్‌తో మొదలుపెట్టండి.',
        'hi': 'भारत: सिर्फ़ 10 अंक। दूसरे देश: + और देश कोड से शुरू करें।',
      },
      'mobile': {'en': 'Mobile number', 'te': 'మొబైల్ నంబర్', 'hi': 'मोबाइल नंबर'},
      'sendOtp': {'en': 'Send OTP', 'te': 'OTP పంపండి', 'hi': 'OTP भेजें'},
      'sending': {'en': 'Sending…', 'te': 'పంపుతోంది…', 'hi': 'भेज रहे हैं…'},
      'verifyTitle': {'en': 'Verify OTP', 'te': 'OTP వెరిఫై చేయండి', 'hi': 'OTP सत्यापित करें'},
      'codeSent': {'en': 'Enter the code sent to', 'te': 'ఈ నంబర్‌కు పంపిన కోడ్ నమోదు చేయండి', 'hi': 'इस नंबर पर भेजा गया कोड दर्ज करें'},
      'otp': {'en': '6-digit OTP', 'te': '6 అంకెల OTP', 'hi': '6 अंकों का OTP'},
      'verifyOtp': {'en': 'Verify OTP', 'te': 'OTP వెరిఫై చేయండి', 'hi': 'OTP सत्यापित करें'},
      'verifying': {'en': 'Verifying…', 'te': 'వెరిఫై అవుతోంది…', 'hi': 'सत्यापित हो रहा है…'},
      'resend': {'en': 'Resend OTP', 'te': 'OTP మళ్లీ పంపండి', 'hi': 'OTP फिर भेजें'},
      'resendIn': {'en': 'Resend OTP in', 'te': 'OTP మళ్లీ పంపడానికి', 'hi': 'OTP फिर भेजें'},
      'changeNumber': {'en': 'Change number', 'te': 'నంబర్ మార్చండి', 'hi': 'नंबर बदलें'},
      'retry': {'en': 'Try again', 'te': 'మళ్లీ ప్రయత్నించండి', 'hi': 'फिर कोशिश करें'},
      'profileTitle': {'en': 'Create your profile', 'te': 'మీ ప్రొఫైల్ సృష్టించండి', 'hi': 'अपना प्रोफ़ाइल बनाएं'},
      'profileInfo': {
        'en': 'You can add or change your photo and other details later in Profile.',
        'te': 'ఫోటో మరియు ఇతర వివరాలను తర్వాత Profileలో జోడించవచ్చు లేదా మార్చవచ్చు.',
        'hi': 'फोटो और दूसरी जानकारी बाद में Profile में जोड़ या बदल सकते हैं।',
      },
      'name': {'en': 'Your name', 'te': 'మీ పేరు', 'hi': 'आपका नाम'},
      'roleTitle': {'en': 'What will you use ASKODOX for?', 'te': 'ASKODOX ని దేనికి వాడతారు?', 'hi': 'आप ASKODOX किसलिए इस्तेमाल करेंगे?'},
      'roleInfo': {
        'en': 'Pick all that fit. You can change this any time in Profile -> My roles.',
        'te': 'సరిపోయేవన్నీ ఎంచుకోండి. Profile -> నా పాత్రలు లో ఎప్పుడైనా మార్చవచ్చు.',
        'hi': 'जो भी लागू हों चुनें। Profile में कभी भी बदल सकते हैं।',
      },
      'toAskodox': {'en': 'Continue to ASKODOX', 'te': 'ASKODOXకి కొనసాగండి', 'hi': 'ASKODOX पर जारी रखें'},
      'invalidMobile': {
        'en': 'Enter a valid mobile number with country code.',
        'te': 'కంట్రీ కోడ్‌తో సరైన మొబైల్ నంబర్ నమోదు చేయండి.',
        'hi': 'देश कोड के साथ सही मोबाइल नंबर दर्ज करें।',
      },
      'invalidOtp': {'en': 'Enter the 6-digit OTP.', 'te': '6 అంకెల OTP నమోదు చేయండి.', 'hi': '6 अंकों का OTP दर्ज करें।'},
      'invalidName': {'en': 'Enter your name.', 'te': 'మీ పేరు నమోదు చేయండి.', 'hi': 'अपना नाम दर्ज करें।'},
      'network': {
        'en': 'No connection. Check the internet and try again.',
        'te': 'కనెక్షన్ లేదు. ఇంటర్నెట్ చూసి మళ్లీ ప్రయత్నించండి.',
        'hi': 'कनेक्शन नहीं है। इंटरनेट जांचें और फिर कोशिश करें।',
      },
      'waitResend': {
        'en': 'A code was sent a moment ago. Enter it, or wait to request a new one.',
        'te': 'కొద్దిసేపటి క్రితం కోడ్ పంపాం. దాన్ని నమోదు చేయండి, లేదా కొత్తది కోసం కొంచెం ఆగండి.',
        'hi': 'अभी-अभी कोड भेजा गया। उसे दर्ज करें, या नए के लिए थोड़ा रुकें।',
      },
      'welcomeBack': {'en': 'Welcome back', 'te': 'మళ్లీ స్వాగతం', 'hi': 'फिर से स्वागत है'},
      'sentWhatsapp': {'en': 'Code sent on WhatsApp.', 'te': 'WhatsAppలో కోడ్ పంపాం.', 'hi': 'WhatsApp पर कोड भेजा गया।'},
      'sentSms': {'en': 'Code sent by SMS.', 'te': 'SMS ద్వారా కోడ్ పంపాం.', 'hi': 'SMS से कोड भेजा गया।'},
      'sentFirebase': {'en': 'Code sent by SMS (Google).', 'te': 'SMS ద్వారా కోడ్ పంపాం (Google).', 'hi': 'SMS से कोड भेजा गया (Google)।'},
      'unexpected': {
        'en': 'Something went wrong while sending the code. Try again.',
        'te': 'కోడ్ పంపుతున్నప్పుడు సమస్య వచ్చింది. మళ్లీ ప్రయత్నించండి.',
        'hi': 'कोड भेजते समय समस्या हुई। फिर कोशिश करें।',
      },
    };
    return values[key]?[_languageCode] ?? values[key]?['en'] ?? key;
  }

  String _languageName(String code) => AskodoxLanguageCatalog.byCode(code).name;

  void _startCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds < 0 ? 0 : seconds);
    if (_resendIn == 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) timer.cancel();
    });
  }

  void _fail(ApiFailure failure, {required String stage}) {
    final network = failure.type == ApiFailureType.network || failure.type == ApiFailureType.timeout;
    askodoxAuthLog('$stage.failed', {'http': failure.statusCode ?? 'none', 'type': failure.type.name});
    _announce(network ? _t('network') : (failure.message ?? failure.localizedMessage(_languageCode)), retry: network);
  }

  void _say(String code, {required String stage}) {
    final (en, te) = askodoxPhoneAuthMessage(code);
    askodoxAuthLog('$stage.firebase_failed', {'code': code});
    // The Firebase error code is always shown so a problem can be reported exactly.
    _announce('${_languageCode == 'te' ? te : en} (Firebase: $code)',
        retry: code == 'network-request-failed' || code == 'timeout');
  }

  /// Every failure is visible: inline under the form AND as a snackbar above
  /// the keyboard (the inline text alone can sit behind the keyboard).
  void _announce(String message, {bool retry = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _canRetry = retry;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      key: const Key('askodoxSignInErrorSnack'),
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
  }

  /// Back to the number: any code request still on its way is ignored.
  void _changeNumber() {
    _attempt++;
    _resendTimer?.cancel();
    setState(() {
      _otp.clear();
      _verificationId = null;
      _resendIn = 0;
      _busy = false;
      _error = null;
      _step = 1;
    });
  }

  /// Send OTP: never ends silently. Any exception becomes a visible error.
  Future<void> _sendOtp({bool resend = false}) async {
    try {
      await _sendOtpSteps(resend: resend);
    } catch (error) {
      askodoxAuthLog('send_otp.exception', {'type': error.runtimeType.toString()});
      _announce('${_t('unexpected')} (${error.runtimeType})', retry: true);
    }
  }

  Future<void> _sendOtpSteps({bool resend = false}) async {
    final e164 = askodoxE164(_mobile.text);
    askodoxAuthLog('send_otp.tap', {
      'valid': e164 != null,
      'path': _useFirebase ? 'firebase' : 'server',
      'resend': resend,
      if (e164 != null) 'number': askodoxMaskedPhone(e164),
    });
    if (e164 == null) {
      _announce(_t('invalidMobile'));
      return;
    }
    final attempt = ++_attempt;
    setState(() {
      _e164 = e164;
      _busy = true;
      _error = null;
      _canRetry = false;
    });
    if (_useFirebase) {
      final started = await ref.read(askodoxPhoneAuthProvider).start(e164, resendToken: resend ? _resendToken : null);
      if (!mounted || attempt != _attempt) return;
      setState(() => _busy = false);
      switch (started) {
        case AskodoxPhoneCodeSent(:final verificationId, :final resendToken):
          askodoxAuthLog('send_otp.code_sent', {'path': 'firebase'});
          FocusScope.of(context).unfocus();
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _channel = 'firebase';
            _step = 2;
          });
          _startCountdown(_resendSeconds);
        case AskodoxPhoneAutoVerified(:final idToken):
          askodoxAuthLog('send_otp.auto_verified', {'path': 'firebase'});
          await _completeWithFirebase(idToken);
        case AskodoxPhoneAuthFailed(:final code):
          const setupProblems = {
            'not-configured', 'app-not-authorized', 'operation-not-allowed', 'missing-client-identifier',
            'invalid-app-credential', 'internal-error', 'no-id-token',
          };
          if (setupProblems.contains(code) && _serverOtp) {
            // Firebase is not ready for this app: the server's own code works.
            askodoxAuthLog('send_otp.firebase_fallback', {'code': code});
            setState(() => _useFirebase = false);
            return _sendOtpSteps(resend: resend);
          }
          _say(code, stage: 'send_otp');
      }
      return;
    }
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/send',
      body: {'mobile': e164},
    );
    if (!mounted || attempt != _attempt) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      askodoxAuthLog('send_otp.sent', {'path': 'server', 'channel': '${result.data['channel']}'});
      FocusScope.of(context).unfocus();
      setState(() {
        _channel = result.data['channel']?.toString();
        _step = 2;
      });
      _startCountdown((result.data['resend_after_seconds'] as num?)?.toInt() ?? _resendSeconds);
    } else if (result is ApiError<Map<String, dynamic>>) {
      final wait = result.failure.statusCode == 429 ? askodoxRetryAfterSeconds(result.failure) : null;
      if (wait != null) {
        // A code is already on its way: enter it, resend when the timer ends.
        askodoxAuthLog('send_otp.rate_limited', {'wait_s': wait});
        setState(() {
          _step = 2;
          _error = _t('waitResend');
        });
        _startCountdown(wait);
        return;
      }
      _fail(result.failure, stage: 'send_otp');
    }
  }

  /// Verify: never ends silently either (the code itself is never logged).
  Future<void> _verifyOtp() async {
    try {
      await _verifyOtpSteps();
    } catch (error) {
      askodoxAuthLog('verify_otp.exception', {'type': error.runtimeType.toString()});
      _announce('${_t('unexpected')} (${error.runtimeType})', retry: true);
    }
  }

  Future<void> _verifyOtpSteps() async {
    final code = _otp.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      _announce(_t('invalidOtp'));
      return;
    }
    askodoxAuthLog('verify_otp.tap', {'path': _useFirebase && _verificationId != null ? 'firebase' : 'server'});
    setState(() {
      _busy = true;
      _error = null;
      _canRetry = false;
    });
    if (_useFirebase && _verificationId != null) {
      try {
        final idToken = await ref.read(askodoxPhoneAuthProvider).confirm(_verificationId!, code);
        if (!mounted) return;
        await _completeWithFirebase(idToken);
      } on AskodoxPhoneAuthError catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        if (e.code == 'session-expired' || e.code == 'code-expired') _startCountdown(0);
        _say(e.code, stage: 'verify_otp');
      }
      return;
    }
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/verify',
      body: {'mobile': _e164 ?? askodoxE164(_mobile.text) ?? _mobile.text.trim(), 'otp': code},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      askodoxAuthLog('verify_otp.ok', {'path': 'server'});
      await _onVerified(result.data);
    } else if (result is ApiError<Map<String, dynamic>>) {
      final message = (result.failure.message ?? '').toLowerCase();
      if (message.contains('expired') || message.contains('request a new otp')) {
        // The old code is gone: a new one can be requested right away.
        _otp.clear();
        _startCountdown(0);
      }
      _fail(result.failure, stage: 'verify_otp');
    }
  }

  Future<void> _completeWithFirebase(String idToken) async {
    setState(() => _busy = true);
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/firebase/verify',
      body: {'id_token': idToken},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      await _onVerified(result.data);
    } else if (result is ApiError<Map<String, dynamic>>) {
      _fail(result.failure, stage: 'firebase_verify');
    }
  }

  /// A verified number: a returning person gets their profile back at once
  /// (nothing is created twice); a new person adds a name and roles.
  Future<void> _onVerified(Map<String, dynamic> data) async {
    _resendTimer?.cancel();
    _verifiedToken = data['token']?.toString();
    _verifiedAccount = data['app_user_id']?.toString();
    final profile = data['profile'] is Map ? Map<String, dynamic>.from(data['profile'] as Map) : const <String, dynamic>{};
    final savedName = (profile['name'] ?? '').toString().trim();
    _returning = data['returning'] == true && savedName.isNotEmpty;
    if (_returning) {
      _name.text = savedName;
      final language = (profile['language'] ?? '').toString();
      if (_usingDeviceLanguage && AskodoxLanguageCatalog.supports(language)) {
        _languageCode = AskodoxLanguageCatalog.normalize(language);
        ref.read(appSettingsProvider.notifier).setLocale(Locale(_languageCode));
      }
      await _finish();
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _nameFocus.requestFocus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_nameFocus.hasFocus) return;
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _nameDone() {
    if (_name.text.trim().length < 2) {
      setState(() => _error = _t('invalidName'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = 4;
    });
  }

  Future<void> _finish() async {
    if (_name.text.trim().length < 2) {
      setState(() {
        _error = _t('invalidName');
        _step = 3;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final prefs = await SharedPreferences.getInstance();
    final account = askodoxAccountDigits(_verifiedAccount) ?? (_e164 ?? _mobile.text.trim());
    // This account's own phone-side data (chats, saved options, roles) comes
    // back if it was put away at sign-out on this phone.
    final restored = await askodoxRestoreAccountData(prefs, 'phone-${account.replaceAll(RegExp(r'\D'), '')}');
    await prefs.setString(_mobileKey, account);
    await prefs.setString(_nameKey, _name.text.trim());
    final token = _verifiedToken?.trim();
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_tokenKey, token);
    }
    await prefs.setBool(_completeKey, true);
    // The session is live at once (no restart needed to act).
    await ref.read(authSessionProvider.notifier).completeOnboarding(
          mobile: account,
          displayName: _name.text.trim(),
          token: (token == null || token.isEmpty) ? null : token,
        );
    // A NEW person's name, language and roles go to the ONE stored profile;
    // a returning person's saved profile is never overwritten here.
    if (!_returning && token != null && token.isNotEmpty) {
      final roles = [for (final r in askodoxSignUpRoles) if (_roles.contains(r.$1)) r.$1];
      unawaited(ref
          .read(askodoxUserProfileProvider.notifier)
          .save({'name': _name.text.trim(), 'language': _languageCode, 'roles': roles})
          .catchError((Object _) => false));
      final controller = ref.read(askodoxRoleProvider.notifier);
      for (final r in askodoxSignUpRoles) {
        if (_roles.contains(r.$1) && r.$2 != AskodoxUserRole.buyer) controller.toggleOwned(r.$2, true);
      }
    }
    if (!mounted) return;
    if (restored && !widget.signIn && AskodoxAppRestart.restart(context)) return;
    if (widget.signIn && context.canPop()) {
      context.pop(true);
    } else {
      context.go('/');
    }
  }

  void _useDeviceLanguage() {
    final code = _deviceLanguageCode();
    ref.read(appSettingsProvider.notifier).useSystemLocale();
    setState(() {
      _languageCode = code;
      _usingDeviceLanguage = true;
      _step = 1;
      _error = null;
    });
  }

  void _chooseLanguage(String code) {
    final normalized = AskodoxLanguageCatalog.normalize(code);
    ref.read(appSettingsProvider.notifier).setLocale(Locale(normalized));
    setState(() {
      _languageCode = normalized;
      _usingDeviceLanguage = false;
      _step = 1;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: SizedBox(
                width: constraints.maxWidth > 520 ? 520 : double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.smart_toy_rounded, size: 72),
                    const SizedBox(height: 16),
                    const Text('ASKODOX', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('${_t('step')} ${_step + 1} ${_t('of')} 5', textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    if (_step == 0) ..._languageStep(context),
                    if (_step == 1) ..._mobileStep(),
                    if (_step == 2) ..._otpStep(),
                    if (_step == 3) ..._profileStep(),
                    if (_step == 4) ..._roleStep(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          key: const Key('askodoxSignInError'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                      if (_canRetry)
                        TextButton.icon(
                          key: const Key('askodoxSignInRetry'),
                          onPressed: _busy ? null : (_step == 2 ? _verifyOtp : _sendOtp),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_t('retry')),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _languageStep(BuildContext context) => [
        Text(_t('languageTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.language_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_t('autoSelected'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${_languageName(_deviceLanguageCode())} • Auto'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _useDeviceLanguage, child: Text('${_t('continue')} • ${_languageName(_deviceLanguageCode())}')),
        const SizedBox(height: 20),
        Text(_t('changeLanguage'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...AskodoxLanguageCatalog.all.map(
          (language) => _languageButton(language.name, language.code),
        ),
      ];

  List<Widget> _mobileStep() => [
        Text(_t('mobileTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('otpInfo')),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('mobile-input'),
          controller: _mobile,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          onSubmitted: (_) => _busy ? null : _sendOtp(),
          decoration: InputDecoration(
              labelText: _t('mobile'), helperText: _t('countryHint'), helperMaxLines: 2, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('askodoxSendOtp'),
          onPressed: _busy ? null : _sendOtp,
          child: _busy
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(_t('sending')),
                ])
              : Text(_t('sendOtp')),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: Text('${_t('languageTitle')}: ${_usingDeviceLanguage ? '${_languageName(_deviceLanguageCode())} (Auto)' : _languageName(_languageCode)}'),
        ),
      ];

  List<Widget> _otpStep() => [
        Text(_t('verifyTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('${_t('codeSent')} ${_e164 == null ? _mobile.text.trim() : askodoxDisplayPhone(_e164!)}',
            key: const Key('askodoxOtpSentTo')),
        if (_channel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                switch (_channel) {
                  'whatsapp' || 'whatsapp_template' => _t('sentWhatsapp'),
                  'firebase' => _t('sentFirebase'),
                  'sms' => _t('sentSms'),
                  _ => '',
                },
                key: const Key('askodoxOtpChannel'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF475467))),
          ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('otp-input'),
          controller: _otp,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          onChanged: (value) {
            if (value.length == 6 && !_busy) _verifyOtp();
          },
          decoration: InputDecoration(labelText: _t('otp'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('askodoxVerifyOtp'),
          onPressed: _busy ? null : _verifyOtp,
          child: _busy
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(_t('verifying')),
                ])
              : Text(_t('verifyOtp')),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(
            key: const Key('askodoxChangeNumber'),
            onPressed: _changeNumber,
            child: Text(_t('changeNumber')),
          ),
          TextButton(
            key: const Key('askodoxResendOtp'),
            onPressed: _busy || _resendIn > 0 ? null : () => _sendOtp(resend: true),
            child: Text(_resendIn > 0
                ? '${_t('resendIn')} 0:${_resendIn.toString().padLeft(2, '0')}'
                : _t('resend')),
          ),
        ]),
      ];

  List<Widget> _profileStep() => [
        Text(_t('profileTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('profileInfo')),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('name-input'),
          focusNode: _nameFocus,
          controller: _name,
          autofocus: true,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          enableSuggestions: true,
          autocorrect: true,
          onTap: () {
            if (!_nameFocus.hasFocus) _nameFocus.requestFocus();
          },
          onSubmitted: (_) => _nameDone(),
          decoration: InputDecoration(labelText: _t('name'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(key: const Key('askodoxNameNext'), onPressed: _nameDone, child: Text(_t('continue'))),
      ];

  List<Widget> _roleStep() => [
        Text(_t('roleTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('roleInfo')),
        const SizedBox(height: 14),
        for (final r in askodoxSignUpRoles)
          CheckboxListTile(
            key: ValueKey('askodoxSignUpRole-${r.$1}'),
            value: _roles.contains(r.$1),
            onChanged: r.$1 == 'buyer'
                ? null
                : (on) => setState(() => on == true ? _roles.add(r.$1) : _roles.remove(r.$1)),
            title: Text(_languageCode == 'te' ? r.$4 : r.$3),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('askodoxFinishSignUp'), onPressed: _busy ? null : _finish, child: Text(_t('toAskodox'))),
      ];

  Widget _languageButton(String label, String code) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton(
          onPressed: () => _chooseLanguage(code),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
          child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}
