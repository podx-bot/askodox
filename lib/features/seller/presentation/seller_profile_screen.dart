import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class SellerProfileScreen extends ConsumerWidget {
  const SellerProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerProvider).seller;
    return Scaffold(appBar: AppBar(title: const Text('Shop profile')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: ListView(padding: const EdgeInsets.all(20), children: [
      CircleAvatar(radius: 44, child: seller?.shop.photoPath == null ? const Icon(Icons.store, size: 42) : const Icon(Icons.check, size: 42)), const SizedBox(height: 16), Text(seller?.shop.name ?? 'Your shop', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text(seller?.ownerName ?? 'Complete registration to publish your profile', textAlign: TextAlign.center), const SizedBox(height: 20),
      Card(child: Column(children: [ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('Verification status'), trailing: Chip(label: Text(seller?.verificationStatus.name.toUpperCase() ?? 'PENDING'))), ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: const Text('Seller trust score'), trailing: Text(seller?.trustScore?.toStringAsFixed(0) ?? '--')), if (seller != null) ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(seller.shop.address), subtitle: Text('${seller.shop.latitude}, ${seller.shop.longitude}'))])),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => context.push('/seller/register'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit shop details')), TextButton.icon(onPressed: () { ref.read(sellerProvider.notifier).signOut(); context.go('/seller/login'); }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
    ]))));
  }
}
