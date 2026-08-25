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
  final shop = TextEditingController(); final owner = TextEditingController(); final mobile = TextEditingController(); final address = TextEditingController();
  final latitude = TextEditingController(text: '17.3850'); final longitude = TextEditingController(text: '78.4867');
  String category = 'Groceries'; String photo = ''; String businessId = '';
  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override
  void dispose() { for (final controller in [shop, owner, mobile, address, latitude, longitude]) { controller.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final categories = {'Groceries':'కిరాణా','Electronics':'ఎలక్ట్రానిక్స్','Fashion':'ఫ్యాషన్','Home & living':'హోమ్ & లివింగ్','Other':'ఇతర'};
    return Scaffold(
      appBar: AppBar(title: Text(t('Register your shop', 'మీ షాప్‌ను నమోదు చేయండి'))),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('Shop profile', 'షాప్ ప్రొఫైల్'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8), Text(t('This information helps nearby customers discover and trust your business.', 'ఈ సమాచారం దగ్గరలోని కస్టమర్లు మీ బిజినెస్‌ను కనుగొని నమ్మడానికి సహాయపడుతుంది.')),
          const SizedBox(height: 24),
          _field(shop, t('Shop name', 'షాప్ పేరు'), Icons.store_outlined), _field(owner, t('Owner name', 'యజమాని పేరు'), Icons.person_outline), _field(mobile, t('Mobile number', 'మొబైల్ నంబర్'), Icons.phone_outlined, keyboard: TextInputType.phone), _field(address, t('Shop address', 'షాప్ చిరునామా'), Icons.location_on_outlined, lines: 3),
          DropdownButtonFormField<String>(initialValue: category, decoration: InputDecoration(labelText: t('Business category', 'బిజినెస్ కేటగిరీ'), prefixIcon: const Icon(Icons.category_outlined)), items: categories.keys.map((value) => DropdownMenuItem(value: value, child: Text(te ? categories[value]! : value))).toList(), onChanged: (value) => setState(() => category = value!)),
          const SizedBox(height: 14), Row(children: [Expanded(child: _field(latitude, t('Latitude', 'అక్షాంశం'), Icons.my_location, keyboard: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 12), Expanded(child: _field(longitude, t('Longitude', 'రేఖాంశం'), Icons.my_location, keyboard: const TextInputType.numberWithOptions(decimal: true)))]),
          Card(child: ListTile(leading: CircleAvatar(child: Icon(photo.isEmpty ? Icons.add_a_photo_outlined : Icons.check)), title: Text(photo.isEmpty ? t('Add shop photo', 'షాప్ ఫోటో జోడించండి') : t('Shop photo selected', 'షాప్ ఫోటో ఎంపికైంది')), subtitle: Text(t('Mock image picker', 'టెస్ట్ ఇమేజ్ పికర్')), trailing: TextButton(onPressed: () => setState(() => photo = 'mock/shop-photo.jpg'), child: Text(photo.isEmpty ? t('Choose', 'ఎంచుకోండి') : t('Change', 'మార్చండి'))))),
          Card(child: ListTile(leading: CircleAvatar(child: Icon(businessId.isEmpty ? Icons.badge_outlined : Icons.check)), title: Text(businessId.isEmpty ? t('Business registration or ID', 'బిజినెస్ రిజిస్ట్రేషన్ లేదా ID') : t('Business ID selected', 'బిజినెస్ ID ఎంపికైంది')), subtitle: Text(t('Mock document upload', 'టెస్ట్ డాక్యుమెంట్ అప్‌లోడ్')), trailing: TextButton(onPressed: () => setState(() => businessId = 'mock/business-id.pdf'), child: Text(businessId.isEmpty ? t('Upload', 'అప్‌లోడ్') : t('Change', 'మార్చండి'))))),
          const SizedBox(height: 20), FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: Text(t('Create seller account', 'సెల్లర్ అకౌంట్ సృష్టించండి'))),
        ])),
      ))),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon, {TextInputType? keyboard, int lines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(controller: controller, keyboardType: keyboard, maxLines: lines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)), validator: (value) => value == null || value.trim().isEmpty ? te ? '$label అవసరం' : '$label is required' : null));

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    final lat = double.tryParse(latitude.text); final lng = double.tryParse(longitude.text);
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Enter valid latitude and longitude', 'సరైన అక్షాంశం మరియు రేఖాంశం నమోదు చేయండి')))); return; }
    await ref.read(sellerProvider.notifier).register(Seller(id: 'seller-${DateTime.now().microsecondsSinceEpoch}', mobile: mobile.text.trim(), ownerName: owner.text.trim(), verificationStatus: VerificationStatus.pending, shop: Shop(id: 'shop-${DateTime.now().microsecondsSinceEpoch}', name: shop.text.trim(), category: category, address: address.text.trim(), latitude: lat, longitude: lng, photoPath: photo.isEmpty ? null : photo, businessIdPath: businessId.isEmpty ? null : businessId)));
    if (mounted) context.go('/seller/dashboard');
  }
}
