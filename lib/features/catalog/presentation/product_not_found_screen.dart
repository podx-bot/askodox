import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/product_request_actions.dart';

class ProductNotFoundScreen extends StatelessWidget {
  const ProductNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/search'), icon: const Icon(Icons.arrow_back)), title: const Text('Product not found')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
                    child: const Icon(Icons.manage_search_rounded, size: 68),
                  ),
                  const SizedBox(height: 28),
                  Text('This product is not available in the PODX catalog yet.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('Tell us what you’re looking for. A photo helps local sellers identify it faster.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 28),
                  const ProductRequestActions(),
                ]),
              ),
            ),
          ),
        ),
      );
}
