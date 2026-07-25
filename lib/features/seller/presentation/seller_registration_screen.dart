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
  final latitude = TextEditingController(text: '17.3850');
  final longitude = TextEditingController(text: '78.4867');
  String category = 'Groceries';
  String photo = '';
  String businessId = '';

  @override
  void dispose() {
    for (final controller in [shop, owner, mobile, address, latitude, longitude]) { controller.dispose(); }
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
            Row(children: [Expanded(child: _field(latitude, 'Latitude', Icons.my_location, keyboard: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 12), Expanded(child: _field(longitude, 'Longitude', Icons.my_location, keyboard: const TextInputType.numberWithOptions(decimal: true)))]),
            Card(child: ListTile(leading: CircleAvatar(child: Icon(photo.isEmpty ? Icons.add_a_photo_outlined : Icons.check)), title: Text(photo.isEmpty ? 'Add shop photo' : 'Shop photo selected'), subtitle: const Text('Mock image picker'), trailing: TextButton(onPressed: () => setState(() => photo = 'mock/shop-photo.jpg'), child: Text(photo.isEmpty ? 'Choose' : 'Change')))),
            Card(child: ListTile(leading: CircleAvatar(child: Icon(businessId.isEmpty ? Icons.badge_outlined : Icons.check)), title: Text(businessId.isEmpty ? 'Business registration or ID' : 'Business ID selected'), subtitle: const Text('Mock document upload'), trailing: TextButton(onPressed: () => setState(() => businessId = 'mock/business-id.pdf'), child: Text(businessId.isEmpty ? 'Upload' : 'Change')))),
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
    final lat = double.tryParse(latitude.text); final lng = double.tryParse(longitude.text);
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid latitude and longitude'))); return;
    }
    await ref.read(sellerProvider.notifier).register(Seller(
      id: 'seller-${DateTime.now().microsecondsSinceEpoch}', mobile: mobile.text.trim(), ownerName: owner.text.trim(), verificationStatus: VerificationStatus.pending,
      shop: Shop(id: 'shop-${DateTime.now().microsecondsSinceEpoch}', name: shop.text.trim(), category: category, address: address.text.trim(), latitude: lat, longitude: lng, photoPath: photo.isEmpty ? null : photo, businessIdPath: businessId.isEmpty ? null : businessId),
    ));
    if (mounted) context.go('/seller/dashboard');
  }
}
