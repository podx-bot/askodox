import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class SellerLoginScreen extends ConsumerStatefulWidget {
  const SellerLoginScreen({super.key});
  @override
  ConsumerState<SellerLoginScreen> createState() => _SellerLoginScreenState();
}

class _SellerLoginScreenState extends ConsumerState<SellerLoginScreen> {
  final mobile = TextEditingController();
  final otp = TextEditingController();
  bool busy = false;
  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override
  void dispose() { mobile.dispose(); otp.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sent = ref.watch(sellerProvider.select((value) => value.isOtpSent));
    return Scaffold(
      appBar: AppBar(title: Text(t('Seller sign in', 'సెల్లర్ సైన్ ఇన్'))),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.storefront, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(t('Grow your local business', 'మీ లోకల్ బిజినెస్‌ను పెంచుకోండి'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t('Manage products, inventory and customer requests from one place.', 'ఉత్పత్తులు, స్టాక్ మరియు కస్టమర్ రిక్వెస్టులను ఒకే చోట నిర్వహించండి.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 32),
          TextField(controller: mobile, keyboardType: TextInputType.phone, enabled: !sent, maxLength: 10, decoration: InputDecoration(labelText: t('Mobile number', 'మొబైల్ నంబర్'), prefixText: '+91  ', prefixIcon: const Icon(Icons.phone_outlined))),
          if (sent) ...[const SizedBox(height: 12), TextField(controller: otp, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: t('6-digit OTP', '6 అంకెల OTP'), helperText: t('Mock OTP: 123456', 'టెస్ట్ OTP: 123456'), prefixIcon: const Icon(Icons.password)))],
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : () => sent ? _verify() : _send(), child: Text(busy ? t('Please wait…', 'దయచేసి వేచి ఉండండి…') : sent ? t('Verify & continue', 'వెరిఫై చేసి కొనసాగండి') : t('Send OTP', 'OTP పంపండి'))),
          TextButton(onPressed: () => context.push('/seller/register'), child: Text(t('New seller? Register your shop', 'కొత్త సెల్లరా? మీ షాప్‌ను నమోదు చేయండి'))),
        ]),
      ))),
    );
  }

  Future<void> _send() async {
    if (!RegExp(r'^\d{10}$').hasMatch(mobile.text)) return _message(t('Enter a valid 10-digit mobile number', 'సరైన 10 అంకెల మొబైల్ నంబర్ నమోదు చేయండి'));
    setState(() => busy = true); await ref.read(sellerProvider.notifier).sendOtp(mobile.text); if (mounted) setState(() => busy = false);
  }

  Future<void> _verify() async {
    setState(() => busy = true); final valid = await ref.read(sellerProvider.notifier).verifyOtp(otp.text); if (!mounted) return; setState(() => busy = false);
    if (valid) context.go('/seller/dashboard'); else _message(t('Incorrect OTP. Use 123456', 'OTP తప్పు. 123456 ఉపయోగించండి'));
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
