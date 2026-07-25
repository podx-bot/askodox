import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../application/home_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(strings.appName, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            actions: [
              IconButton(tooltip: strings.notifications, onPressed: () {}, icon: const Badge(child: Icon(Icons.notifications_outlined))),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(strings.greeting, style: Theme.of(context).textTheme.bodyLarge),
                    Text(strings.discover, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 22),
                    Semantics(
                      button: true,
                      label: strings.searchHint,
                      child: TextField(
                        readOnly: true,
                        onTap: () => context.go('/search'),
                        decoration: InputDecoration(
                          hintText: strings.searchHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: const Icon(Icons.tune),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(title: strings.categories, action: strings.seeAll),
                    const SizedBox(height: 12),
                    const _Categories(),
                    const SizedBox(height: 28),
                    _SectionTitle(title: strings.featured, action: strings.seeAll),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),
            ),
          ),
          _Products(products: ref.watch(featuredProductsProvider)),
          const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
        TextButton(onPressed: () {}, child: Text(action)),
      ]);
}

class _Categories extends StatelessWidget {
  const _Categories();
  static const items = [('Groceries', Icons.local_grocery_store_outlined), ('Fashion', Icons.checkroom), ('Home', Icons.chair_outlined), ('Electronics', Icons.devices_outlined)];
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => Container(
            width: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(items[index].$2, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), Text(items[index].$1, maxLines: 1)]),
          ),
        ),
      );
}

class _Products extends StatelessWidget {
  const _Products({required this.products});
  final AsyncValue<List<Product>> products;
  @override
  Widget build(BuildContext context) => products.when(
        loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
        error: (_, __) => SliverToBoxAdapter(child: Center(child: Text(AppLocalizations.of(context)!.retry))),
        data: (items) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverLayoutBuilder(builder: (context, constraints) {
            final count = constraints.crossAxisExtent >= 1000 ? 4 : constraints.crossAxisExtent >= 600 ? 3 : 2;
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .78),
              itemCount: items.length,
              itemBuilder: (context, index) => _ProductCard(product: items[index]),
            );
          }),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {},
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Container(width: double.infinity, color: Theme.of(context).colorScheme.primaryContainer, alignment: Alignment.center, child: Text(product.icon, style: const TextStyle(fontSize: 52)))),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(product.shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('₹${product.price.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
          ]),
        ),
      );
}
