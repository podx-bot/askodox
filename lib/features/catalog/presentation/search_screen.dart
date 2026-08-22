import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../config/theme/askodox_design_tokens.dart';
import '../../buyer/application/buyer_providers.dart';
import '../../buyer/presentation/widgets/location_selector.dart';
import '../../search/application/product_discovery_controller.dart';
import '../../search/domain/search_models.dart';
import '../../search/presentation/product_discovery_screen.dart';
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('askodoxSearchScreen'),
      appBar: AppBar(
        title: const Text('ASKODOX Search'),
        actions: [
          IconButton(
            onPressed: () => context.push('/discover/barcode'),
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: AskodoxDesignTokens.cardRadius,
                          gradient: LinearGradient(
                            colors: [
                              colors.primary.withValues(alpha: 0.18),
                              colors.surfaceContainerHighest.withValues(alpha: 0.55),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Find it with ${BrandConfig.displayName}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Products, brands and nearby options in one place.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            SearchBar(
                              key: const Key('askodoxSearchField'),
                              controller: controller,
                              focusNode: focusNode,
                              autoFocus: false,
                              hintText: 'Search products or brands',
                              leading: const Icon(Icons.search_rounded),
                              trailing: query.isEmpty
                                  ? null
                                  : [
                                      IconButton(
                                        tooltip: 'Clear',
                                        onPressed: () {
                                          controller.clear();
                                          ref.read(searchQueryProvider.notifier).state = '';
                                          focusNode.requestFocus();
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                              onChanged: (value) =>
                                  ref.read(searchQueryProvider.notifier).state = value,
                              onSubmitted: (value) {
                                final recent = ref.read(recentSearchesProvider);
                                ref.read(recentSearchesProvider.notifier).state = [
                                  value,
                                  ...recent.where((item) => item != value),
                                ].take(8).toList();
                                ref
                                    .read(productDiscoveryControllerProvider.notifier)
                                    .search(value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const LocationSelector(),
                      const SizedBox(height: 12),
                      const DiscoveryTools(),
                      if (query.isEmpty &&
                          ref.watch(recentSearchesProvider).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Recently searched',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Wrap(
                          spacing: 8,
                          children: ref
                              .watch(recentSearchesProvider)
                              .map(
                                (value) => ActionChip(
                                  label: Text(value),
                                  onPressed: () {
                                    controller.text = value;
                                    ref.read(searchQueryProvider.notifier).state = value;
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (query.isEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Smart suggestions',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ref
                              .watch(productDiscoveryRepositoryProvider)
                              .suggestions(ref.watch(recentSearchesProvider))
                              .map(
                                (suggestion) => ActionChip(
                                  avatar: Icon(
                                    switch (suggestion.source) {
                                      SuggestionSource.recent => Icons.history,
                                      SuggestionSource.trending => Icons.trending_up,
                                      SuggestionSource.watchlist => Icons.favorite_border,
                                      SuggestionSource.nearbyDemand =>
                                        Icons.near_me_outlined,
                                      SuggestionSource.popularBrand =>
                                        Icons.verified_outlined,
                                    },
                                    size: 17,
                                  ),
                                  label: Text(suggestion.label),
                                  tooltip: suggestion.source.name,
                                  onPressed: () {
                                    controller.text = suggestion.label;
                                    ref.read(searchQueryProvider.notifier).state =
                                        suggestion.label;
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (focusNode.hasFocus && query.isNotEmpty)
                        catalog.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (data) => _Suggestions(
                            query: query,
                            catalog: data,
                            onSelected: (value) {
                              controller.text = value;
                              controller.selection =
                                  TextSelection.collapsed(offset: value.length);
                              ref.read(searchQueryProvider.notifier).state = value;
                              focusNode.unfocus();
                            },
                          ),
                        ),
                      const SizedBox(height: 22),
                      Text(
                        query.isEmpty ? 'Browse categories' : 'Search results',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 14),
                      catalog.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Could not load categories'),
                        data: (data) =>
                            _CategoryFilters(categories: data.categories),
                      ),
                    ],
                  ),
                ),
              ),
              products.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SliverFillRemaining(
                  child: Center(child: Text('Something went wrong')),
                ),
                data: (items) => items.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptySearch(query: query),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final count = constraints.crossAxisExtent >= 900
                                ? 4
                                : constraints.crossAxisExtent >= 560
                                    ? 3
                                    : 2;
                            return SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: .72,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  ProductCard(product: items[index]),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.query,
    required this.catalog,
    required this.onSelected,
  });

  final String query;
  final Catalog catalog;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final needle = query.toLowerCase();
    final values = <String>{
      ...catalog.products
          .where((item) => item.name.toLowerCase().contains(needle))
          .map((item) => item.name),
      ...catalog.brands
          .where((item) => item.name.toLowerCase().contains(needle))
          .map((item) => item.name),
      ...catalog.categories
          .where((item) => item.name.toLowerCase().contains(needle))
          .map((item) => item.name),
    }.take(5).toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: values
            .map(
              (value) => ListTile(
                dense: true,
                leading: const Icon(Icons.north_west, size: 18),
                title: Text(value),
                onTap: () => onSelected(value),
              ),
            )
            .toList(),
      ),
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
    final current = selected == null
        ? null
        : categories.where((item) => item.id == selected).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selected == null,
                onSelected: (_) {
                  ref.read(selectedCategoryProvider.notifier).state = null;
                  ref.read(selectedSubcategoryProvider.notifier).state = null;
                },
              ),
              const SizedBox(width: 8),
              ...categories.expand(
                (category) => [
                  ChoiceChip(
                    avatar: Text(category.icon),
                    label: Text(category.name),
                    selected: selected == category.id,
                    onSelected: (_) {
                      ref.read(selectedCategoryProvider.notifier).state =
                          category.id;
                      ref.read(selectedSubcategoryProvider.notifier).state = null;
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: current.subcategories
                .map(
                  (item) => FilterChip(
                    label: Text(item.name),
                    selected: subcategory == item.id,
                    onSelected: (value) =>
                        ref.read(selectedSubcategoryProvider.notifier).state =
                            value ? item.id : null,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AskodoxDesignTokens.actionGradient,
                boxShadow: [
                  AskodoxDesignTokens.glow(
                    AskodoxDesignTokens.electricBlue,
                  ),
                ],
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No match for “$query”',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another name, or ask us to find it for you.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            const ProductRequestActions(compact: true),
          ],
        ),
      );
}
