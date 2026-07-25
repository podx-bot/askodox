import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class RequestNewProductScreen extends ConsumerStatefulWidget {
  const RequestNewProductScreen({super.key});
  @override ConsumerState<RequestNewProductScreen> createState() => _RequestNewProductScreenState();
}
class _RequestNewProductScreenState extends ConsumerState<RequestNewProductScreen> {
  final name = TextEditingController(); String category = 'Groceries'; String? imagePath;
  @override void dispose() { name.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Request New Product')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('If a product is missing, submit it for admin verification. It will not be listed until approved.'), const SizedBox(height: 20), TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')), const SizedBox(height: 12),
    DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), items: ['Groceries', 'Electronics', 'Fashion', 'Home & living', 'Other'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => category = value!)), const SizedBox(height: 12),
    Card(child: ListTile(leading: Icon(imagePath == null ? Icons.add_photo_alternate_outlined : Icons.check_circle), title: Text(imagePath == null ? 'Upload image' : 'Image selected'), subtitle: const Text('Mock upload placeholder'), trailing: TextButton(onPressed: () => setState(() => imagePath = 'mock/new-product.jpg'), child: const Text('Choose')))), const SizedBox(height: 20),
    FilledButton(onPressed: () async { if (name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a product name'))); return; } await ref.read(sellerProvider.notifier).requestProduct(name: name.text.trim(), category: category, imagePath: imagePath); if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted for admin verification'))); context.pop(); } }, child: const Text('Submit for verification')),
  ]))));
}
