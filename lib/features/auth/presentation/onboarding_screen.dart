import 'package:flutter/material.dart';
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

  final _mobile = TextEditingController(text: '+91');
  final _otp = TextEditingController();
  final _name = TextEditingController();
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
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
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _mobile.dispose();
    _otp.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_mobile.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Enter a valid mobile number with country code.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/send',
      body: {'mobile': _mobile.text.trim()},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      setState(() => _step = 2);
    } else if (result is ApiError<Map<String, dynamic>>) {
      setState(() => _error = result.failure.message ?? result.failure.localizedMessage('en'));
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.text.replaceAll(RegExp(r'\D'), '').length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final result = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/onboarding/otp/verify',
      body: {'mobile': _mobile.text.trim(), 'otp': _otp.text.trim()},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ApiSuccess<Map<String, dynamic>>) {
      setState(() => _step = 3);
    } else if (result is ApiError<Map<String, dynamic>>) {
      setState(() => _error = result.failure.message ?? result.failure.localizedMessage('en'));
    }
  }

  Future<void> _finish() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mobileKey, _mobile.text.trim());
    await prefs.setString(_nameKey, _name.text.trim());
    await prefs.setBool(_completeKey, true);
    if (mounted) context.go('/');
  }

  void _chooseLanguage(String code) {
    ref.read(appSettingsProvider.notifier).setLocale(Locale(code));
    setState(() { _step = 1; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.smart_toy_rounded, size: 72),
                  const SizedBox(height: 16),
                  const Text('ASKODOX', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Step ${_step + 1} of 4', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  if (_step == 0) ...[
                    const Text('Choose your language', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _languageButton('English', 'en'),
                    _languageButton('తెలుగు', 'te'),
                    _languageButton('हिन्दी', 'hi'),
                  ] else if (_step == 1) ...[
                    const Text('Enter mobile number', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('We will send a 6-digit verification code on WhatsApp.'),
                    const SizedBox(height: 18),
                    TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _busy ? null : _sendOtp, child: Text(_busy ? 'Sending…' : 'Send WhatsApp OTP')),
                  ] else if (_step == 2) ...[
                    const Text('Verify OTP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Enter the code sent to ${_mobile.text.trim()}'),
                    const SizedBox(height: 18),
                    TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit OTP', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _busy ? null : _verifyOtp, child: Text(_busy ? 'Verifying…' : 'Verify OTP')),
                    TextButton(onPressed: _busy ? null : _sendOtp, child: const Text('Resend OTP')),
                  ] else ...[
                    const Text('Create your profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('You can add or change your photo and other details later in Profile.'),
                    const SizedBox(height: 18),
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _finish, child: const Text('Continue to ASKODOX')),
                  ],
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
    );
  }

  Widget _languageButton(String label, String code) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton(
          onPressed: () => _chooseLanguage(code),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
          child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}
