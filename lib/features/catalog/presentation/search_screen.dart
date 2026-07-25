import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/catalog_providers.dart';
import '../domain/entities/catalog.dart';
import '../domain/entities/category.dart';
import 'widgets/product_card.dart';
import 'widgets/product_request_actions.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final products = ref.watch(filteredProductsProvider);
    final query = ref.watch(searchQueryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Find your product'), actions: [IconButton(onPressed: () {}, tooltip: 'Scan barcode', icon: const Icon(Icons.qr_code_scanner)), const SizedBox(width: 8)]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SearchBar(
                    controller: controller,
                    focusNode: focusNode,
                    autoFocus: false,
                    hintText: 'Search products or brands',
                    leading: const Icon(Icons.search),
                    trailing: query.isEmpty ? null : [IconButton(tooltip: 'Clear', onPressed: () { controller.clear(); ref.read(searchQueryProvider.notifier).state = ''; focusNode.requestFocus(); }, icon: const Icon(Icons.close))],
                    onChanged: (value) => ref.read(searchQueryProvider.notifier).state = value,
                  ),
                  if (focusNode.hasFocus && query.isNotEmpty)
                    catalog.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (data) => _Suggestions(query: query, catalog: data, onSelected: (value) { controller.text = value; controller.selection = TextSelection.collapsed(offset: value.length); ref.read(searchQueryProvider.notifier).state = value; focusNode.unfocus(); }),
                    ),
                  const SizedBox(height: 22),
                  Text(query.isEmpty ? 'Browse categories' : 'Search results', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  catalog.when(loading: () => const LinearProgressIndicator(), error: (_, __) => const Text('Could not load categories'), data: (data) => _CategoryFilters(categories: data.categories)),
                ]),
              ),
            ),
            products.when(
              loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SliverFillRemaining(child: Center(child: Text('Something went wrong'))),
              data: (items) => items.isEmpty
                  ? SliverFillRemaining(hasScrollBody: false, child: _EmptySearch(query: query))
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      sliver: SliverLayoutBuilder(builder: (context, constraints) {
                        final count = constraints.crossAxisExtent >= 900 ? 4 : constraints.crossAxisExtent >= 560 ? 3 : 2;
                        return SliverGrid.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .72),
                          itemCount: items.length,
                          itemBuilder: (context, index) => ProductCard(product: items[index]),
                        );
                      }),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.query, required this.catalog, required this.onSelected});
  final String query;
  final Catalog catalog;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final needle = query.toLowerCase();
    final values = <String>{
      ...catalog.products.where((item) => item.name.toLowerCase().contains(needle)).map((item) => item.name),
      ...catalog.brands.where((item) => item.name.toLowerCase().contains(needle)).map((item) => item.name),
      ...catalog.categories.where((item) => item.name.toLowerCase().contains(needle)).map((item) => item.name),
    }.take(5).toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(children: values.map((value) => ListTile(dense: true, leading: const Icon(Icons.north_west, size: 18), title: Text(value), onTap: () => onSelected(value))).toList()),
    );
  }
}

class _CategoryFilters extends ConsumerWidget {
  const _CategoryFilters({required this.categories});
  final List<ProductCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCategoryProvider);
    final subcategory = ref.watch(selectedSubcategoryProvider);
    final current = selected == null ? null : categories.where((item) => item.id == selected).first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) { ref.read(selectedCategoryProvider.notifier).state = null; ref.read(selectedSubcategoryProvider.notifier).state = null; }),
          const SizedBox(width: 8),
          ...categories.expand((category) => [ChoiceChip(avatar: Text(category.icon), label: Text(category.name), selected: selected == category.id, onSelected: (_) { ref.read(selectedCategoryProvider.notifier).state = category.id; ref.read(selectedSubcategoryProvider.notifier).state = null; }), const SizedBox(width: 8)]),
        ]),
      ),
      if (current != null) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: current.subcategories.map((item) => FilterChip(label: Text(item.name), selected: subcategory == item.id, onSelected: (value) => ref.read(selectedSubcategoryProvider.notifier).state = value ? item.id : null)).toList()),
      ],
    ]);
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No match for “$query”', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Try another name, or ask us to find it for you.', textAlign: TextAlign.center),
          const SizedBox(height: 22),
          const ProductRequestActions(compact: true),
        ]),
      );
}
