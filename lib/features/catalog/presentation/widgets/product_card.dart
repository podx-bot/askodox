import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/product.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/product/${product.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.65),
                  alignment: Alignment.center,
                  child: Text(product.icon, style: const TextStyle(fontSize: 56)),
                ),
                if (product.discountPercent > 0)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${product.discountPercent}% off', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.brand.name.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: .6)),
                const SizedBox(height: 3),
                Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Row(children: [
                  Text('₹${product.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  Text('₹${product.originalPrice.toStringAsFixed(0)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)),
                ]),
              ]),
            ),
          ]),
        ),
      );
}
