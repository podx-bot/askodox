import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/entities/product.dart';
import '../application/seller_providers.dart';
import '../domain/entities/seller_models.dart';

class AddSellerProductScreen extends ConsumerStatefulWidget {
  const AddSellerProductScreen({super.key});
  @override
  ConsumerState<AddSellerProductScreen> createState() => _AddSellerProductScreenState();
}

class _AddSellerProductScreenState extends ConsumerState<AddSellerProductScreen> {
  Product? selected;
  String query = '';
  StockStatus status = StockStatus.inStock;
  DateTime? offerStart;
  DateTime? offerExpiry;
  final price = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final offer = TextEditingController();

  @override
  void dispose() { price.dispose(); quantity.dispose(); offer.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final existing = ref.watch(sellerProvider).products.map((item) => item.catalogId).toSet();
    return Scaffold(appBar: AppBar(title: const Text('Add product')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Master Product Catalog', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Select a standardized product. Products already in your shop cannot be added twice.'), const SizedBox(height: 16),
      SearchBar(hintText: 'Search catalog', leading: const Icon(Icons.search), onChanged: (value) => setState(() => query = value.trim().toLowerCase())), const SizedBox(height: 12),
      catalog.when(loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => const Text('Could not load catalog'), data: (data) {
        final products = data.products.where((item) => query.isEmpty || item.name.toLowerCase().contains(query) || item.brand.name.toLowerCase().contains(query)).toList();
        return Column(children: [for (final product in products) Card(color: selected?.id == product.id ? Theme.of(context).colorScheme.primaryContainer : null, child: RadioListTile<String>(value: product.id, groupValue: selected?.id, onChanged: existing.contains(product.id) ? null : (_) => setState(() { selected = product; price.text = product.price.toStringAsFixed(0); }), secondary: CircleAvatar(child: Text(product.icon)), title: Text(product.name), subtitle: Text(existing.contains(product.id) ? 'Already in your shop' : 'Suggested ₹${product.price.toStringAsFixed(0)}'))), if (products.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Column(children: [const Text('Product not found in the master catalog.'), TextButton.icon(onPressed: () => context.push('/seller/products/request'), icon: const Icon(Icons.add_circle_outline), label: const Text('Request New Product'))]))]);
      }),
      if (selected != null) ...[
        const SizedBox(height: 18), Text('Price, stock & offer', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
        TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current selling price (₹)')), const SizedBox(height: 12),
        DropdownButtonFormField<StockStatus>(initialValue: status, decoration: const InputDecoration(labelText: 'Stock status'), items: StockStatus.values.map((value) => DropdownMenuItem(value: value, child: Text(_stockLabel(value)))).toList(), onChanged: (value) => setState(() => status = value!)), const SizedBox(height: 12),
        TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Available quantity')), const SizedBox(height: 12),
        TextField(controller: offer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Optional offer price (₹)')), const SizedBox(height: 8),
        Wrap(spacing: 10, children: [OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.event), label: Text(offerStart == null ? 'Offer start' : _date(offerStart!))), OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_busy), label: Text(offerExpiry == null ? 'Offer expiry' : _date(offerExpiry!)))]), const SizedBox(height: 20),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add to my shop')),
      ],
    ]))));
  }

  static String _stockLabel(StockStatus value) => switch (value) { StockStatus.inStock => 'In stock', StockStatus.lowStock => 'Low stock', StockStatus.outOfStock => 'Out of stock' };
  String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
  Future<void> _pickDate(bool start) async { final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (picked != null) setState(() { if (start) offerStart = picked; else offerExpiry = picked; }); }
  void _add() {
    final amount = double.tryParse(price.text); final count = int.tryParse(quantity.text); final offerAmount = offer.text.trim().isEmpty ? null : double.tryParse(offer.text);
    if (selected == null || amount == null || amount <= 0 || count == null || count < 0 || (offerAmount != null && (offerAmount <= 0 || offerAmount >= amount)) || (offerExpiry != null && offerStart != null && offerExpiry!.isBefore(offerStart!))) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check price, stock, offer and dates'))); return; }
    final added = ref.read(sellerProvider.notifier).addProduct(selected!, price: amount, stockStatus: count == 0 ? StockStatus.outOfStock : status, quantity: count, offerPrice: offerAmount, offerStart: offerStart, offerExpiry: offerExpiry);
    if (!added) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This product is already in your shop'))); return; }
    context.pop();
  }
}
