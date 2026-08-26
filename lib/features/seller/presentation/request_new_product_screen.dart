import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class RequestNewProductScreen extends ConsumerStatefulWidget {
  const RequestNewProductScreen({super.key});
  @override ConsumerState<RequestNewProductScreen> createState() => _RequestNewProductScreenState();
}

class _RequestNewProductScreenState extends ConsumerState<RequestNewProductScreen> {
  final name = TextEditingController();
  String category = 'Groceries';
  String? imagePath;

  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override void dispose() { name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const categories = <String, String>{
      'Groceries': 'కిరాణా',
      'Electronics': 'ఎలక్ట్రానిక్స్',
      'Fashion': 'ఫ్యాషన్',
      'Home & living': 'హోమ్ & లివింగ్',
      'Other': 'ఇతర',
    };
    return Scaffold(
      appBar: AppBar(title: Text(t('Request New Product', 'కొత్త ఉత్పత్తిని అభ్యర్థించండి'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(t('If a product is missing, submit it for admin verification. It will not be listed until approved.', 'ఉత్పత్తి కనిపించకపోతే అడ్మిన్ వెరిఫికేషన్ కోసం పంపండి. ఆమోదం వచ్చే వరకు అది లిస్ట్‌లో కనిపించదు.')),
        const SizedBox(height: 20),
        TextField(controller: name, decoration: InputDecoration(labelText: t('Product name', 'ఉత్పత్తి పేరు'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: InputDecoration(labelText: t('Category', 'కేటగిరీ')),
          items: categories.keys.map((item) => DropdownMenuItem(value: item, child: Text(te ? categories[item]! : item))).toList(),
          onChanged: (value) => setState(() => category = value!),
        ),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: Icon(imagePath == null ? Icons.add_photo_alternate_outlined : Icons.check_circle),
          title: Text(imagePath == null ? t('Upload image', 'చిత్రాన్ని అప్‌లోడ్ చేయండి') : t('Image selected', 'చిత్రం ఎంపికైంది')),
          subtitle: Text(t('Mock upload placeholder', 'టెస్ట్ అప్‌లోడ్ ప్లేస్‌హోల్డర్')),
          trailing: TextButton(onPressed: () => setState(() => imagePath = 'mock/new-product.jpg'), child: Text(t('Choose', 'ఎంచుకోండి'))),
        )),
        const SizedBox(height: 20),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Enter a product name', 'ఉత్పత్తి పేరు నమోదు చేయండి'))));
            return;
          }
          await ref.read(sellerProvider.notifier).requestProduct(name: name.text.trim(), category: category, imagePath: imagePath);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Submitted for admin verification', 'అడ్మిన్ వెరిఫికేషన్ కోసం పంపబడింది'))));
            context.pop();
          }
        }, child: Text(t('Submit for verification', 'వెరిఫికేషన్ కోసం పంపండి'))),
      ]))),
    );
  }
}
