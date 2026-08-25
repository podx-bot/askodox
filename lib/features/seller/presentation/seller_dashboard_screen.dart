import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';
import '../domain/entities/seller_models.dart';

class SellerDashboardScreen extends ConsumerWidget {
  const SellerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerProvider);
    final products = seller.products;
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Seller dashboard', 'సెల్లర్ డ్యాష్‌బోర్డ్')),
        actions: [
          IconButton(tooltip: t('Shop profile', 'షాప్ ప్రొఫైల్'), onPressed: () => context.push('/seller/register'), icon: const Icon(Icons.store_outlined)),
          PopupMenuButton<String>(onSelected: (value) { if (value == 'logout') { ref.read(sellerProvider.notifier).signOut(); context.go('/seller/login'); } }, itemBuilder: (_) => [PopupMenuItem(value: 'logout', child: Text(t('Sign out', 'సైన్ అవుట్')))]),
        ],
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(te ? 'నమస్కారం, ${seller.seller?.ownerName ?? 'సెల్లర్'}!' : 'Hello, ${seller.seller?.ownerName ?? 'Seller'}!', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(seller.seller?.shop.name ?? t('Here is how your shop is doing today.', 'ఈరోజు మీ షాప్ పనితీరు ఇక్కడ చూడండి.'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, size) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: size.maxWidth >= 760 ? 4 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: size.maxWidth >= 760 ? 1.4 : 1.15,
            children: [
              _Metric(label: t('Total products', 'మొత్తం ఉత్పత్తులు'), value: products.length, icon: Icons.inventory_2_outlined, color: Colors.indigo),
              _Metric(label: t('Active products', 'యాక్టివ్ ఉత్పత్తులు'), value: products.where((item) => item.isActive).length, icon: Icons.check_circle_outline, color: Colors.green),
              _Metric(label: t('Out of stock', 'స్టాక్ లేదు'), value: products.where((item) => !item.isActive).length, icon: Icons.remove_shopping_cart_outlined, color: Colors.orange),
              _Metric(label: t('Price updates', 'ధర అప్‌డేట్లు'), value: products.where((item) => item.needsPriceRefresh).length, icon: Icons.update, color: Colors.blue),
              _Metric(label: t('New requests', 'కొత్త రిక్వెస్టులు'), value: seller.requests.where((item) => !item.isSellerSubmitted).length, icon: Icons.pending_actions_outlined, color: Colors.purple),
              _Metric(label: t('Verification', 'వెరిఫికేషన్'), value: seller.seller?.verificationStatus.index ?? 0, icon: Icons.verified_user_outlined, color: Colors.teal),
              _Metric(label: t('Trust score', 'ట్రస్ట్ స్కోర్'), value: seller.seller?.trustScore?.round() ?? 0, icon: Icons.workspace_premium_outlined, color: Colors.amber),
            ],
          )),
          const SizedBox(height: 28),
          Text(t('Business analytics', 'బిజినెస్ అనలిటిక్స్'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed:()=>context.push('/seller/analytics'),icon:const Icon(Icons.analytics_outlined),label:Text(t('Dashboard', 'డ్యాష్‌బోర్డ్'))),
            FilledButton.tonalIcon(onPressed:()=>context.push('/seller/analytics/products'),icon:const Icon(Icons.inventory_outlined),label:Text(t('Product performance', 'ఉత్పత్తుల పనితీరు'))),
            FilledButton.tonalIcon(onPressed:()=>context.push('/seller/analytics/market'),icon:const Icon(Icons.public),label:Text(t('Market intelligence', 'మార్కెట్ సమాచారం'))),
            FilledButton.tonalIcon(onPressed:()=>context.push('/seller/analytics/privacy'),icon:const Icon(Icons.privacy_tip_outlined),label:Text(t('Privacy', 'ప్రైవసీ'))),
          ]),
          const SizedBox(height: 28),
          Row(children: [Expanded(child: Text(t('Inventory overview', 'ఇన్వెంటరీ వివరాలు'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: () => context.push('/seller/products/add'), icon: const Icon(Icons.add), label: Text(t('Add product', 'ఉత్పత్తి జోడించండి')))]),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            for (var i = 0; i < products.take(4).length; i++) ...[
              ListTile(leading: CircleAvatar(child: Text(products[i].icon)), title: Text(products[i].name), subtitle: Text(products[i].stockStatus == StockStatus.outOfStock ? t('Out of stock', 'స్టాక్ లేదు') : te ? '${products[i].quantity} అందుబాటులో ఉన్నాయి' : '${products[i].quantity} available'), trailing: Text('₹${products[i].price.toStringAsFixed(0)}')),
              if (i != products.take(4).length - 1) const Divider(height: 1),
            ],
          ])),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => context.push('/seller/products'), icon: const Icon(Icons.inventory_2_outlined), label: Text(t('Manage all products', 'అన్ని ఉత్పత్తులను నిర్వహించండి'))),
        ]),
      )),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color), const Spacer(), Text('$value', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)), Text(label, maxLines: 1)])));
}
