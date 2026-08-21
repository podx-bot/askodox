import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/seller_providers.dart';

class RequestNewProductScreen extends ConsumerStatefulWidget {
  const RequestNewProductScreen({super.key});

  @override
  ConsumerState<RequestNewProductScreen> createState() =>
      _RequestNewProductScreenState();
}

class _RequestNewProductScreenState extends ConsumerState<RequestNewProductScreen> {
  final name = TextEditingController();
  String category = 'Groceries';
  String? imagePath;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _chooseImageReference() async {
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ImageReferenceDialog(
        initialValue: imagePath ?? '',
      ),
    );

    if (!mounted || value == null) return;
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an image URL or reference.')),
      );
      return;
    }
    setState(() => imagePath = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Request New Product')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              key: const Key('sellerNewProductList'),
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'If a product is missing, submit it for admin verification. It will not be listed until approved.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('sellerNewProductName'),
                  controller: name,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('sellerNewProductCategory'),
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    'Groceries',
                    'Electronics',
                    'Fashion',
                    'Home & living',
                    'Other',
                  ]
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('sellerNewProductImageTile'),
                    leading: Icon(
                      imagePath == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.check_circle,
                    ),
                    title: Text(
                      imagePath == null ? 'Add image reference' : 'Image added',
                    ),
                    subtitle: Text(
                      imagePath ??
                          'Add a product image URL or local image reference for verification.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      key: const Key('sellerNewProductChooseImage'),
                      onPressed: _chooseImageReference,
                      child: Text(imagePath == null ? 'Add' : 'Change'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('sellerNewProductSubmit'),
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    if (name.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a product name')),
                      );
                      return;
                    }
                    await ref.read(sellerProvider.notifier).requestProduct(
                          name: name.text.trim(),
                          category: category,
                          imagePath: imagePath,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Submitted for admin verification'),
                        ),
                      );
                      context.pop();
                    }
                  },
                  child: const Text('Submit for verification'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ImageReferenceDialog extends StatefulWidget {
  const _ImageReferenceDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_ImageReferenceDialog> createState() => _ImageReferenceDialogState();
}

class _ImageReferenceDialogState extends State<_ImageReferenceDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add product image reference'),
        content: TextField(
          key: const Key('sellerNewProductImageReference'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Image URL or local reference',
            hintText: 'https://… or product-photo.jpg',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('sellerNewProductImageCancel'),
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('sellerNewProductImageSave'),
            onPressed: _submit,
            child: const Text('Use image'),
          ),
        ],
      );
}
