import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/seller_providers.dart';

class SellerInsightsScreen extends ConsumerWidget {
  const SellerInsightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(sellerProvider).insights;
    return Scaffold(appBar: AppBar(title: const Text('Seller insights')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Demand around your shop', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Mock trends based on nearby searches and watchlists.'), const SizedBox(height: 20),
      for (final insight in insights) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(contentPadding: const EdgeInsets.all(16), leading: CircleAvatar(child: Icon(_icon(insight.type))), title: Text(insight.productName, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(insight.title), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${insight.score}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const Text('demand')])))),
    ]))));
  }
  IconData _icon(String type) => switch (type) { 'search' => Icons.search, 'watchlist' => Icons.favorite_outline, 'missing' => Icons.add_business, _ => Icons.update };
}
