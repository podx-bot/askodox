import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';
import '../domain/entities/seller_models.dart';

class SellerRegistrationScreen extends ConsumerStatefulWidget {
  const SellerRegistrationScreen({super.key});
  @override
  ConsumerState<SellerRegistrationScreen> createState() => _SellerRegistrationScreenState();
}

class _SellerRegistrationScreenState extends ConsumerState<SellerRegistrationScreen> {
  final formKey = GlobalKey<FormState>();
  final shop = TextEditingController();
  final owner = TextEditingController();
  final mobile = TextEditingController();
  final address = TextEditingController();
  String category = 'Groceries';
  String photo = '';
  double latitude = 17.3850;
  double longitude = 78.4867;

  @override
  void dispose() {
    for (final controller in [shop, owner, mobile, address]) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Register your shop')),
        body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Shop profile', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('This information helps nearby customers discover and trust your business.'),
            const SizedBox(height: 24),
            _field(shop, 'Shop name', Icons.store_outlined),
            _field(owner, 'Owner name', Icons.person_outline),
            _field(mobile, 'Mobile number', Icons.phone_outlined, keyboard: TextInputType.phone),
            _field(address, 'Shop address', Icons.location_on_outlined, lines: 3),
            DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Business category', prefixIcon: Icon(Icons.category_outlined)), items: ['Groceries', 'Electronics', 'Fashion', 'Home & living', 'Other'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => category = value!)),
            const SizedBox(height: 14),
            Card(child: ListTile(leading: const Icon(Icons.my_location), title: const Text('GPS location'), subtitle: Text('${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'), trailing: TextButton(onPressed: () => setState(() { latitude = 17.4401; longitude = 78.3489; }), child: const Text('Use current')))),
            Card(child: ListTile(leading: CircleAvatar(child: Icon(photo.isEmpty ? Icons.add_a_photo_outlined : Icons.check)), title: Text(photo.isEmpty ? 'Add shop photo' : 'Shop photo selected'), subtitle: const Text('Mock image picker'), trailing: TextButton(onPressed: () => setState(() => photo = 'mock/shop-photo.jpg'), child: Text(photo.isEmpty ? 'Choose' : 'Change')))),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: const Text('Create seller account')),
          ])),
        ))),
      );

  Widget _field(TextEditingController controller, String label, IconData icon, {TextInputType? keyboard, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(controller: controller, keyboardType: keyboard, maxLines: lines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)), validator: (value) => value == null || value.trim().isEmpty ? '$label is required' : null),
  );

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    await ref.read(sellerProvider.notifier).register(ShopProfile(shopName: shop.text.trim(), ownerName: owner.text.trim(), mobile: mobile.text.trim(), address: address.text.trim(), latitude: latitude, longitude: longitude, photoPath: photo, category: category));
    if (mounted) context.go('/seller/dashboard');
  }
}
