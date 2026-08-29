import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_models.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/providers/backend_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _completeKey = 'askodox.onboarding.complete';
  static const _mobileKey = 'askodox.profile.mobile';
  static const _nameKey = 'askodox.profile.name';
  static const _localeKey = 'askodox.locale';
  static const _supportedLanguages = {'en', 'te', 'hi'};

  final _mobile = TextEditingController(text: '+91');
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'askodox-name-focus');

  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  bool _usingDeviceLanguage = true;
  String _languageCode = 'en';
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_completeKey) == true) {
      context.go('/');
      return;
    }

    final saved = prefs.getString(_localeKey)?.trim();
    if (saved != null && _supportedLanguages.contains(saved)) {
      _languageCode = saved;
      _usingDeviceLanguage = false;
    } else {
      _languageCode = _deviceLanguageCode();
      _usingDeviceLanguage = true;
      ref.read(appSettingsProvider.notifier).useSystemLocale();
    }
    setState(() => _loading = false);
  }

  String _deviceLanguageCode() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return _supportedLanguages.contains(code) ? code : 'en';
  }

  @override
  void dispose() {
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
      'mobileTitle': {'en': 'Enter mobile number', 'te': 'మొబైల్ నంబర్ నమోదు చేయండి', 'hi': 'मोबाइल नंबर दर्ज करें'},
      'otpInfo': {
        'en': 'We will send a 6-digit verification code on WhatsApp.',
        'te': 'WhatsAppలో 6 అంకెల వెరిఫికేషన్ కోడ్ పంపిస్తాము.',
        'hi': 'हम WhatsApp पर 6 अंकों का सत्यापन कोड भेजेंगे।',
      },
      'mobile': {'en': 'Mobile number', 'te': 'మొబైల్ నంబర్', 'hi': 'मोबाइल नंबर'},
      'sendOtp': {'en': 'Send WhatsApp OTP', 'te': 'WhatsApp OTP పంపండి', 'hi': 'WhatsApp OTP भेजें'},
      'sending': {'en': 'Sending…', 'te': 'పంపుతోంది…', 'hi': 'भेज रहे हैं…'},
      'verifyTitle': {'en': 'Verify OTP', 'te': 'OTP వెరిఫై చేయండి', 'hi': 'OTP सत्यापित करें'},
      'codeSent': {'en': 'Enter the code sent to', 'te': 'ఈ నంబర్‌కు పంపిన కోడ్ నమోదు చేయండి', 'hi': 'इस नंबर पर भेजा गया कोड दर्ज करें'},
      'otp': {'en': '6-digit OTP', 'te': '6 అంకెల OTP', 'hi': '6 अंकों का OTP'},
      'verifyOtp': {'en': 'Verify OTP', 'te': 'OTP వెరిఫై చేయండి', 'hi': 'OTP सत्यापित करें'},
      'verifying': {'en': 'Verifying…', 'te': 'వెరిఫై అవుతోంది…', 'hi': 'सत्यापित हो रहा है…'},
      'resend': {'en': 'Resend OTP', 'te': 'OTP మళ్లీ పంపండి', 'hi': 'OTP फिर भेजें'},
      'profileTitle': {'en': 'Create your profile', 'te': 'మీ ప్రొఫైల్ సృష్టించండి', 'hi': 'अपना प्रोफ़ाइल बनाएं'},
      'profileInfo': {
        'en': 'You can add or change your photo and other details later in Profile.',
        'te': 'ఫోటో మరియు ఇతర వివరాలను తర్వాత Profileలో జోడించవచ్చు లేదా మార్చవచ్చు.',
        'hi': 'फोटो और दूसरी जानकारी बाद में Profile में जोड़ या बदल सकते हैं।',
      },
      'name': {'en': 'Your name', 'te': 'మీ పేరు', 'hi': 'आपका नाम'},
      'toAskodox': {'en': 'Continue to ASKODOX', 'te': 'ASKODOXకి కొనసాగండి', 'hi': 'ASKODOX पर जारी रखें'},
      'invalidMobile': {
        'en': 'Enter a valid mobile number with country code.',
        'te': 'కంట్రీ కోడ్‌తో సరైన మొబైల్ నంబర్ నమోదు చేయండి.',
        'hi': 'देश कोड के साथ सही मोबाइल नंबर दर्ज करें।',
      },
      'invalidOtp': {'en': 'Enter the 6-digit OTP.', 'te': '6 అంకెల OTP నమోదు చేయండి.', 'hi': '6 अंकों का OTP दर्ज करें।'},
      'invalidName': {'en': 'Enter your name.', 'te': 'మీ పేరు నమోదు చేయండి.', 'hi': 'अपना नाम दर्ज करें।'},
    };
    return values[key]?[_languageCode] ?? values[key]?['en'] ?? key;
  }

  String _languageName(String code) => switch (code) {
        'te' => 'తెలుగు',
        'hi' => 'हिन्दी',
        _ => 'English',
      };

  Future<void> _sendOtp() async {
    if (_mobile.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = _t('invalidMobile'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/send',
      body: {'mobile': _mobile.text.trim()},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      FocusScope.of(context).unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (mounted) setState(() => _step = 2);
    } else if (result is ApiError<Map<String, dynamic>>) {
      setState(() => _error = result.failure.message ?? result.failure.localizedMessage(_languageCode));
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.text.replaceAll(RegExp(r'\D'), '').length != 6) {
      setState(() => _error = _t('invalidOtp'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/verify',
      body: {'mobile': _mobile.text.trim(), 'otp': _otp.text.trim()},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      // Fully tear down the numeric OTP input connection before showing the name field.
      FocusScope.of(context).unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => _step = 3);
    } else if (result is ApiError<Map<String, dynamic>>) {
      setState(() => _error = result.failure.message ?? result.failure.localizedMessage(_languageCode));
    }
  }

  Future<void> _finish() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = _t('invalidName'));
      return;
    }
    FocusScope.of(context).unfocus();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mobileKey, _mobile.text.trim());
    await prefs.setString(_nameKey, _name.text.trim());
    await prefs.setBool(_completeKey, true);
    if (mounted) context.go('/');
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
    ref.read(appSettingsProvider.notifier).setLocale(Locale(code));
    setState(() {
      _languageCode = code;
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
                    Text('${_t('step')} ${_step + 1} ${_t('of')} 4', textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    if (_step == 0) ..._languageStep(context),
                    if (_step == 1) ..._mobileStep(),
                    if (_step == 2) ..._otpStep(),
                    if (_step == 3) ..._profileStep(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
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
        _languageButton('English', 'en'),
        _languageButton('తెలుగు', 'te'),
        _languageButton('हिन्दी', 'hi'),
      ];

  List<Widget> _mobileStep() => [
        Text(_t('mobileTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('otpInfo')),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('mobile-input'),
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: _t('mobile'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _sendOtp, child: Text(_busy ? _t('sending') : _t('sendOtp'))),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: Text('${_t('languageTitle')}: ${_usingDeviceLanguage ? '${_languageName(_deviceLanguageCode())} (Auto)' : _languageName(_languageCode)}'),
        ),
      ];

  List<Widget> _otpStep() => [
        Text(_t('verifyTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('${_t('codeSent')} ${_mobile.text.trim()}'),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('otp-input'),
          controller: _otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: _t('otp'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _verifyOtp, child: Text(_busy ? _t('verifying') : _t('verifyOtp'))),
        TextButton(onPressed: _busy ? null : _sendOtp, child: Text(_t('resend'))),
      ];

  List<Widget> _profileStep() => [
        Text(_t('profileTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_t('profileInfo')),
        const SizedBox(height: 18),
        TextField(
          key: UniqueKey(),
          focusNode: _nameFocus,
          controller: _name,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          enableSuggestions: true,
          autocorrect: false,
          onSubmitted: (_) => _finish(),
          decoration: InputDecoration(labelText: _t('name'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _finish, child: Text(_t('toAskodox'))),
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
