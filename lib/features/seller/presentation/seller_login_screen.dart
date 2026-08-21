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

  @override
  void dispose() {
    mobile.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sent = ref.watch(sellerProvider.select((value) => value.isOtpSent));
    return Scaffold(
      key: const Key('sellerLoginScreen'),
      appBar: AppBar(title: const Text('Seller sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.storefront, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text('Grow your local business', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Manage products, inventory and customer requests from one place.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              TextField(
                key: const Key('sellerLoginMobileField'),
                controller: mobile,
                keyboardType: TextInputType.phone,
                enabled: !sent,
                maxLength: 10,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!sent && !busy) _send();
                },
                decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  ', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              if (sent) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('sellerLoginOtpField'),
                  controller: otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!busy) _verify();
                  },
                  decoration: const InputDecoration(labelText: '6-digit OTP', helperText: 'Mock OTP: 123456', prefixIcon: Icon(Icons.password)),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('sellerLoginPrimaryAction'),
                onPressed: busy ? null : () => sent ? _verify() : _send(),
                child: Text(busy ? 'Please wait…' : sent ? 'Verify & continue' : 'Send OTP'),
              ),
              TextButton(
                key: const Key('sellerLoginRegister'),
                onPressed: () => context.push('/seller/register'),
                child: const Text('New seller? Register your shop'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!RegExp(r'^\d{10}$').hasMatch(mobile.text)) return _message('Enter a valid 10-digit mobile number');
    setState(() => busy = true);
    await ref.read(sellerProvider.notifier).sendOtp(mobile.text);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _verify() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => busy = true);
    final valid = await ref.read(sellerProvider.notifier).verifyOtp(otp.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (valid) context.go('/seller/dashboard'); else _message('Incorrect OTP. Use 123456');
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
