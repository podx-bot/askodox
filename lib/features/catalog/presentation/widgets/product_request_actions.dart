import 'package:flutter/material.dart';

class ProductRequestActions extends StatelessWidget {
  const ProductRequestActions({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    void show(String message) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    final request = FilledButton.icon(
      onPressed: () => show('Product request saved. We’ll look for it nearby.'),
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('Request product'),
    );
    final upload = OutlinedButton.icon(
      onPressed: () => show('Image attached to your product request.'),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Upload product image'),
    );
    if (compact) return Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [request, upload]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [request, const SizedBox(height: 10), upload]);
  }
}
