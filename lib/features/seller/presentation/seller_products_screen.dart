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
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    return Scaffold(
      appBar: AppBar(title: Text(t('My products', 'నా ఉత్పత్తులు'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/seller/products/add'), icon: const Icon(Icons.add), label: Text(t('Add product', 'ఉత్పత్తి జోడించండి'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: products.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inventory_2_outlined, size: 64), const SizedBox(height: 12), Text(t('No products yet', 'ఇంకా ఉత్పత్తులు లేవు'))]))
        : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), itemCount: products.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
            final product = products[index];
            return Card(child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(radius: 28, child: Text(product.icon, style: const TextStyle(fontSize: 24))),
              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('₹${product.price.toStringAsFixed(0)}${product.offerPrice == null ? '' : '  •  ${t('Offer', 'ఆఫర్')} ₹${product.offerPrice!.toStringAsFixed(0)}'}  •  ${product.quantity}  •  ${_status(product.stockStatus, te)}'),
              trailing: PopupMenuButton<String>(onSelected: (value) => value == 'edit' ? _edit(context, ref, product, te) : _delete(context, ref, product, te), itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t('Edit', 'మార్చండి')))), PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(t('Delete', 'తొలగించండి'))))]),
            ));
          }))),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SellerProduct product, bool te) async {
    String t(String en, String telugu) => te ? telugu : en;
    final price = TextEditingController(text: product.price.toStringAsFixed(0));
    final stock = TextEditingController(text: '${product.quantity}');
    final offer = TextEditingController(text: product.offerPrice?.toStringAsFixed(0) ?? '');
    var status = product.stockStatus;
    final save = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, setModalState) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(te ? '${product.name} అప్‌డేట్ చేయండి' : 'Update ${product.name}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 20), TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Selling price (₹)', 'అమ్మక ధర (₹)'))), const SizedBox(height: 12), DropdownButtonFormField<StockStatus>(initialValue: status, decoration: InputDecoration(labelText: t('Stock status', 'స్టాక్ స్థితి')), items: StockStatus.values.map((item) => DropdownMenuItem(value: item, child: Text(_status(item, te)))).toList(), onChanged: (value) => setModalState(() => status = value!)), const SizedBox(height: 12), TextField(controller: stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Stock quantity', 'స్టాక్ పరిమాణం'))), const SizedBox(height: 12), TextField(controller: offer, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Optional offer price (₹)', 'ఐచ్చిక ఆఫర్ ధర (₹)'))), const SizedBox(height: 20), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save changes', 'మార్పులు సేవ్ చేయండి')))]))));
    if (save == true) { final quantity = int.tryParse(stock.text) ?? product.quantity; ref.read(sellerProvider.notifier).updateProduct(product.id, price: double.tryParse(price.text) ?? product.price, stockStatus: quantity == 0 ? StockStatus.outOfStock : status, quantity: quantity, offerPrice: double.tryParse(offer.text)); }
    price.dispose(); stock.dispose(); offer.dispose();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SellerProduct product, bool te) async {
    String t(String en, String telugu) => te ? telugu : en;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(t('Delete product?', 'ఉత్పత్తిని తొలగించాలా?')), content: Text(te ? '${product.name} మీ షాప్ నుంచి తొలగించబడుతుంది.' : '${product.name} will be removed from your shop.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel', 'రద్దు'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Delete', 'తొలగించండి')))]));
    if (confirmed == true) ref.read(sellerProvider.notifier).deleteProduct(product.id);
  }

  static String _status(StockStatus status, bool te) => switch (status) { StockStatus.inStock => te ? 'స్టాక్‌లో ఉంది' : 'In stock', StockStatus.lowStock => te ? 'తక్కువ స్టాక్' : 'Low stock', StockStatus.outOfStock => te ? 'స్టాక్ లేదు' : 'Out of stock' };
}
