import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class SellerProfileScreen extends ConsumerWidget {
  const SellerProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerProvider).seller;
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    return Scaffold(appBar: AppBar(title: Text(t('Shop profile', 'షాప్ ప్రొఫైల్'))), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: ListView(padding: const EdgeInsets.all(20), children: [
      CircleAvatar(radius: 44, child: seller?.shop.photoPath == null ? const Icon(Icons.store, size: 42) : const Icon(Icons.check, size: 42)), const SizedBox(height: 16), Text(seller?.shop.name ?? t('Your shop', 'మీ షాప్'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text(seller?.ownerName ?? t('Complete registration to publish your profile', 'మీ ప్రొఫైల్ ప్రచురించడానికి రిజిస్ట్రేషన్ పూర్తి చేయండి'), textAlign: TextAlign.center), const SizedBox(height: 20),
      Card(child: Column(children: [ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(t('Verification status', 'వెరిఫికేషన్ స్థితి')), trailing: Chip(label: Text(seller?.verificationStatus.name.toUpperCase() ?? t('PENDING', 'పెండింగ్')))), ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: Text(t('Seller trust score', 'సెల్లర్ ట్రస్ట్ స్కోర్')), trailing: Text(seller?.trustScore?.toStringAsFixed(0) ?? '--')), if (seller != null) ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(seller.shop.address), subtitle: Text('${seller.shop.latitude}, ${seller.shop.longitude}'))])),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => context.push('/seller/location'), icon: const Icon(Icons.pin_drop_outlined), label: Text(t('Manage shop location', 'షాప్ లొకేషన్ నిర్వహించండి'))), const SizedBox(height: 8), OutlinedButton.icon(onPressed: () => context.push('/seller/register'), icon: const Icon(Icons.edit_outlined), label: Text(t('Edit shop details', 'షాప్ వివరాలు మార్చండి'))), TextButton.icon(onPressed: () { ref.read(sellerProvider.notifier).signOut(); context.go('/seller/login'); }, icon: const Icon(Icons.logout), label: Text(t('Sign out', 'సైన్ అవుట్'))),
    ]))));
  }
}
