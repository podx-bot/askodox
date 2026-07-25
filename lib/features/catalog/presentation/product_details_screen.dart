import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/catalog_providers.dart';
import '../domain/entities/product.dart';
import 'product_not_found_screen.dart';

class ProductDetailsScreen extends ConsumerWidget {
  const ProductDetailsScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(productByIdProvider(productId)).when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const ProductNotFoundScreen(),
        data: (product) => product == null ? const ProductNotFoundScreen() : _ProductDetails(product: product),
      );
}

class _ProductDetails extends StatefulWidget {
  const _ProductDetails({required this.product});
  final Product product;

  @override
  State<_ProductDetails> createState() => _ProductDetailsState();
}

class _ProductDetailsState extends State<_ProductDetails> {
  bool notify = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/search'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Product details'),
        actions: [IconButton(onPressed: () {}, tooltip: 'Share', icon: const Icon(Icons.ios_share_outlined)), const SizedBox(width: 8)],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 720;
              final image = Container(
                constraints: BoxConstraints(minHeight: wide ? 520 : 330),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.7), borderRadius: BorderRadius.circular(28)),
                alignment: Alignment.center,
                child: Hero(tag: 'product-${product.id}', child: Text(product.icon, style: TextStyle(fontSize: wide ? 150 : 110))),
              );
              final info = Padding(
                padding: EdgeInsets.all(wide ? 32 : 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(product.brand.name.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    if (product.brand.verified) ...[const SizedBox(width: 5), Icon(Icons.verified, size: 17, color: Theme.of(context).colorScheme.primary)],
                  ]),
                  const SizedBox(height: 10),
                  Text(product.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Row(children: [const Icon(Icons.star_rounded, color: Color(0xFFFFB400), size: 21), Text(' ${product.rating}  ·  ${product.reviewCount} reviews')]),
                  const SizedBox(height: 22),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹${product.price.toStringAsFixed(0)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(width: 10),
                    Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('₹${product.originalPrice.toStringAsFixed(0)}', style: const TextStyle(decoration: TextDecoration.lineThrough))),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('${product.discountPercent}% off', style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 24),
                  Text('About this product', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(product.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: product.inStock
                        ? FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to your watchlist'))), icon: const Icon(Icons.favorite_border), label: const Text('Add to watchlist'))
                        : FilledButton.icon(
                            onPressed: () {
                              setState(() => notify = true);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We’ll notify you when it’s back.')));
                            },
                            icon: Icon(notify ? Icons.notifications_active : Icons.notifications_outlined),
                            label: Text(notify ? 'Notification on' : 'Notify me'),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Center(child: Text(product.inStock ? 'Available from sellers near you' : 'Currently unavailable nearby', style: Theme.of(context).textTheme.bodySmall)),
                ]),
              );
              return Padding(
                padding: const EdgeInsets.all(20),
                child: wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: image), Expanded(child: info)]) : Column(children: [image, const SizedBox(height: 22), info]),
              );
            }),
          ),
        ),
      ),
    );
  }
}
