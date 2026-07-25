import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/entities/product.dart';
import '../application/seller_providers.dart';

class AddSellerProductScreen extends ConsumerStatefulWidget {
  const AddSellerProductScreen({super.key});
  @override
  ConsumerState<AddSellerProductScreen> createState() => _AddSellerProductScreenState();
}

class _AddSellerProductScreenState extends ConsumerState<AddSellerProductScreen> {
  Product? selected;
  final price = TextEditingController();
  final stock = TextEditingController(text: '1');

  @override
  void dispose() { price.dispose(); stock.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final existing = ref.watch(sellerProvider).products.map((item) => item.catalogId).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('Add product')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Select from master catalog', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Choose a standardized PODX product, then set your shop price and availability.'),
        const SizedBox(height: 20),
        catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => const Text('Could not load catalog'),
          data: (data) => Column(children: data.products.map((product) => Card(
            color: selected?.id == product.id ? Theme.of(context).colorScheme.primaryContainer : null,
            child: RadioListTile<String>(value: product.id, groupValue: selected?.id, onChanged: existing.contains(product.id) ? null : (_) => setState(() { selected = product; price.text = product.price.toStringAsFixed(0); }), secondary: CircleAvatar(child: Text(product.icon)), title: Text(product.name), subtitle: Text(existing.contains(product.id) ? 'Already in your shop' : 'Suggested ₹${product.price.toStringAsFixed(0)}')),
          )).toList()),
        ),
        if (selected != null) ...[
          const SizedBox(height: 20),
          Text('Price & stock', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling price (₹)'))), const SizedBox(width: 12), Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')))]),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add to my shop')),
        ],
      ]))),
    );
  }

  void _add() {
    final amount = double.tryParse(price.text);
    final quantity = int.tryParse(stock.text);
    if (selected == null || amount == null || amount <= 0 || quantity == null || quantity < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price and stock quantity')));
      return;
    }
    ref.read(sellerProvider.notifier).addProduct(selected!, amount, quantity);
    context.pop();
  }
}
