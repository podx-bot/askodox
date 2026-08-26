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

  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override
  void dispose() {
    price.dispose();
    quantity.dispose();
    offer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final existing = ref.watch(sellerProvider).products.map((item) => item.catalogId).toSet();
    return Scaffold(
      appBar: AppBar(title: Text(t('Add product', 'ఉత్పత్తి జోడించండి'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(t('Master Product Catalog', 'మాస్టర్ ఉత్పత్తి కేటలాగ్'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(t('Select a standardized product. Products already in your shop cannot be added twice.', 'స్టాండర్డ్ ఉత్పత్తిని ఎంచుకోండి. మీ షాప్‌లో ఇప్పటికే ఉన్న ఉత్పత్తిని రెండోసారి జోడించలేరు.')),
              const SizedBox(height: 16),
              SearchBar(hintText: t('Search catalog', 'కేటలాగ్‌లో శోధించండి'), leading: const Icon(Icons.search), onChanged: (value) => setState(() => query = value.trim().toLowerCase())),
              const SizedBox(height: 12),
              catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(t('Could not load catalog', 'కేటలాగ్ లోడ్ కాలేదు')),
                data: (data) {
                  final products = data.products.where((item) => query.isEmpty || item.name.toLowerCase().contains(query) || item.brand.name.toLowerCase().contains(query)).toList();
                  return Column(children: [
                    for (final product in products)
                      Card(
                        color: selected?.id == product.id ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: RadioListTile<String>(
                          value: product.id,
                          groupValue: selected?.id,
                          onChanged: existing.contains(product.id) ? null : (_) => setState(() { selected = product; price.text = product.price.toStringAsFixed(0); }),
                          secondary: CircleAvatar(child: Text(product.icon)),
                          title: Text(product.name),
                          subtitle: Text(existing.contains(product.id) ? t('Already in your shop', 'ఇప్పటికే మీ షాప్‌లో ఉంది') : '${t('Suggested', 'సూచించిన ధర')} ₹${product.price.toStringAsFixed(0)}'),
                        ),
                      ),
                    if (products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          Text(t('Product not found in the master catalog.', 'మాస్టర్ కేటలాగ్‌లో ఉత్పత్తి కనబడలేదు.')),
                          TextButton.icon(onPressed: () => context.push('/seller/products/request'), icon: const Icon(Icons.add_circle_outline), label: Text(t('Request New Product', 'కొత్త ఉత్పత్తిని అభ్యర్థించండి'))),
                        ]),
                      ),
                  ]);
                },
              ),
              if (selected != null) ...[
                const SizedBox(height: 18),
                Text(t('Price, stock & offer', 'ధర, స్టాక్ & ఆఫర్'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Current selling price (₹)', 'ప్రస్తుత అమ్మక ధర (₹)'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<StockStatus>(initialValue: status, decoration: InputDecoration(labelText: t('Stock status', 'స్టాక్ స్థితి')), items: StockStatus.values.map((value) => DropdownMenuItem(value: value, child: Text(_stockLabel(value, te)))).toList(), onChanged: (value) => setState(() => status = value!)),
                const SizedBox(height: 12),
                TextField(controller: quantity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Available quantity', 'అందుబాటులో పరిమాణం'))),
                const SizedBox(height: 12),
                TextField(controller: offer, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Optional offer price (₹)', 'ఐచ్చిక ఆఫర్ ధర (₹)'))),
                const SizedBox(height: 8),
                Wrap(spacing: 10, children: [
                  OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.event), label: Text(offerStart == null ? t('Offer start', 'ఆఫర్ ప్రారంభం') : _date(offerStart!))),
                  OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_busy), label: Text(offerExpiry == null ? t('Offer expiry', 'ఆఫర్ ముగింపు') : _date(offerExpiry!))),
                ]),
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text(t('Add to my shop', 'నా షాప్‌కు జోడించండి'))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _stockLabel(StockStatus value, bool te) => switch (value) {
        StockStatus.inStock => te ? 'స్టాక్‌లో ఉంది' : 'In stock',
        StockStatus.lowStock => te ? 'తక్కువ స్టాక్' : 'Low stock',
        StockStatus.outOfStock => te ? 'స్టాక్ లేదు' : 'Out of stock',
      };

  String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null) setState(() { if (start) offerStart = picked; else offerExpiry = picked; });
  }

  void _add() {
    final amount = double.tryParse(price.text);
    final count = int.tryParse(quantity.text);
    final offerAmount = offer.text.trim().isEmpty ? null : double.tryParse(offer.text);
    if (selected == null || amount == null || amount <= 0 || count == null || count < 0 || (offerAmount != null && (offerAmount <= 0 || offerAmount >= amount)) || (offerExpiry != null && offerStart != null && offerExpiry!.isBefore(offerStart!))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Check price, stock, offer and dates', 'ధర, స్టాక్, ఆఫర్ మరియు తేదీలను తనిఖీ చేయండి'))));
      return;
    }
    final added = ref.read(sellerProvider.notifier).addProduct(selected!, price: amount, stockStatus: count == 0 ? StockStatus.outOfStock : status, quantity: count, offerPrice: offerAmount, offerStart: offerStart, offerExpiry: offerExpiry);
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('This product is already in your shop', 'ఈ ఉత్పత్తి ఇప్పటికే మీ షాప్‌లో ఉంది'))));
      return;
    }
    context.pop();
  }
}
