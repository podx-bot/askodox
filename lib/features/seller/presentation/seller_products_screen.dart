import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';
import '../domain/entities/seller_models.dart';

class SellerProductsScreen extends ConsumerWidget {
  const SellerProductsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(sellerProvider).products;
    return Scaffold(
      appBar: AppBar(title: const Text('My products')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/seller/products/add'), icon: const Icon(Icons.add), label: const Text('Add product')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: products.isEmpty
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inventory_2_outlined, size: 64), SizedBox(height: 12), Text('No products yet')]))
        : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), itemCount: products.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
            final product = products[index];
            return Card(child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(radius: 28, child: Text(product.icon, style: const TextStyle(fontSize: 24))),
              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('₹${product.price.toStringAsFixed(0)}${product.offerPrice == null ? '' : '  •  Offer ₹${product.offerPrice!.toStringAsFixed(0)}'}  •  ${product.quantity}  •  ${_status(product.stockStatus)}'),
              trailing: PopupMenuButton<String>(onSelected: (value) => value == 'edit' ? _edit(context, ref, product) : _delete(context, ref, product), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))), PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')))]),
            ));
          }))),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SellerProduct product) async {
    final price = TextEditingController(text: product.price.toStringAsFixed(0));
    final stock = TextEditingController(text: '${product.quantity}');
    final offer = TextEditingController(text: product.offerPrice?.toStringAsFixed(0) ?? '');
    var status = product.stockStatus;
    final save = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, setModalState) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text('Update ${product.name}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 20), TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling price (₹)')), const SizedBox(height: 12), DropdownButtonFormField<StockStatus>(initialValue: status, decoration: const InputDecoration(labelText: 'Stock status'), items: StockStatus.values.map((item) => DropdownMenuItem(value: item, child: Text(_status(item)))).toList(), onChanged: (value) => setModalState(() => status = value!)), const SizedBox(height: 12), TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')), const SizedBox(height: 12), TextField(controller: offer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Optional offer price (₹)')), const SizedBox(height: 20), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save changes'))]))));
    if (save == true) { final quantity = int.tryParse(stock.text) ?? product.quantity; ref.read(sellerProvider.notifier).updateProduct(product.id, price: double.tryParse(price.text) ?? product.price, stockStatus: quantity == 0 ? StockStatus.outOfStock : status, quantity: quantity, offerPrice: double.tryParse(offer.text)); }
    price.dispose(); stock.dispose(); offer.dispose();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SellerProduct product) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete product?'), content: Text('${product.name} will be removed from your shop.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirmed == true) ref.read(sellerProvider.notifier).deleteProduct(product.id);
  }

  static String _status(StockStatus status) => switch (status) { StockStatus.inStock => 'In stock', StockStatus.lowStock => 'Low stock', StockStatus.outOfStock => 'Out of stock' };
}
