import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/catalog_providers.dart';
import 'widgets/product_card.dart';
import 'widgets/product_request_actions.dart';
import '../../buyer/application/buyer_providers.dart';
import '../../buyer/presentation/widgets/location_selector.dart';
import '../../search/application/product_discovery_controller.dart';
import '../../search/presentation/product_discovery_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(filteredProductsProvider);
    final query = ref.watch(searchQueryProvider).trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find your product'),
        actions: [
          IconButton(onPressed: () => context.push('/discover/barcode'), tooltip: 'Barcode search', icon: const Icon(Icons.qr_code_scanner)),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SearchBar(
                      controller: controller,
                      focusNode: focusNode,
                      hintText: 'What are you looking for?',
                      leading: const Icon(Icons.search),
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
                                icon: const Icon(Icons.close),
                              ),
                            ],
                      onChanged: (value) => ref.read(searchQueryProvider.notifier).state = value,
                      onSubmitted: (value) {
                        final normalized = value.trim();
                        if (normalized.isEmpty) return;
                        final recent = ref.read(recentSearchesProvider);
                        ref.read(recentSearchesProvider.notifier).state = [normalized, ...recent.where((item) => item != normalized)].take(8).toList();
                        ref.read(productDiscoveryControllerProvider.notifier).search(normalized);
                      },
                    ),
                    const SizedBox(height: 10),
                    const LocationSelector(),
                    const SizedBox(height: 12),
                    const DiscoveryTools(),
                    if (query.isEmpty && ref.watch(recentSearchesProvider).isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Recent searches', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ref.watch(recentSearchesProvider).map((value) => ActionChip(label: Text(value), onPressed: () { controller.text = value; ref.read(searchQueryProvider.notifier).state = value; ref.read(productDiscoveryControllerProvider.notifier).search(value); })).toList(),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text(query.isEmpty ? 'Ask for anything nearby' : 'Search results', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
              products.when(
                loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
                error: (_, __) => const SliverFillRemaining(child: Center(child: Text('Unable to load live results right now.'))),
                data: (items) {
                  if (query.isEmpty) {
                    return const SliverFillRemaining(hasScrollBody: false, child: _StartSearch());
                  }
                  if (items.isEmpty) {
                    return SliverFillRemaining(hasScrollBody: false, child: _EmptySearch(query: query));
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverLayoutBuilder(builder: (context, constraints) {
                      final count = constraints.crossAxisExtent >= 900 ? 4 : constraints.crossAxisExtent >= 560 ? 3 : 2;
                      return SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .72),
                        itemCount: items.length,
                        itemBuilder: (context, index) => ProductCard(product: items[index]),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartSearch extends StatelessWidget {
  const _StartSearch();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.travel_explore_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Tell ASKODOX what you need', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Search by text or voice. Your current location can be used to find nearby matches.', textAlign: TextAlign.center),
        ]),
      );
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
          Text('No live match yet for “$query”', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('We can keep this request and match it when a relevant seller or provider is available.', textAlign: TextAlign.center),
          const SizedBox(height: 22),
          const ProductRequestActions(compact: true),
        ]),
      );
}
