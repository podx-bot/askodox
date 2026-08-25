import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../buyer/application/buyer_providers.dart';
import '../../buyer/domain/entities/buyer_models.dart';
import '../../buyer/presentation/widgets/location_selector.dart';
import '../application/catalog_providers.dart';
import '../domain/entities/product.dart';
import 'product_not_found_screen.dart';
import '../../watchlist/application/watchlist_providers.dart';
import '../../watchlist/domain/watchlist_models.dart';
import '../../price_benchmark/presentation/price_benchmark_section.dart';

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';
String _t(BuildContext context, String en, String te) => _te(context) ? te : en;

class ProductDetailsScreen extends ConsumerWidget {
  const ProductDetailsScreen({required this.productId, super.key});
  final String productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(productByIdProvider(productId)).when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const ProductNotFoundScreen(),
        data: (p) => p == null ? const ProductNotFoundScreen() : _Comparison(product: p),
      );
}

class _Comparison extends ConsumerWidget {
  const _Comparison({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(priceListingsProvider(product.id));
    final location = ref.watch(buyerLocationProvider);
    final radius = ref.watch(radiusKmProvider);
    final filter = ref.watch(searchFilterProvider);
    final sort = ref.watch(comparisonSortProvider);
    final watched = ref.watch(watchlistProvider).any((e) => e.productId == product.id);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/search'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_t(context, 'Compare local prices', 'లోకల్ ధరలను పోల్చండి')),
        actions: [
          IconButton(
            tooltip: watched
                ? _t(context, 'Remove from Watchlist', 'వాచ్‌లిస్ట్ నుంచి తొలగించండి')
                : _t(context, 'Add to Watchlist', 'వాచ్‌లిస్ట్‌కు జోడించండి'),
            icon: Icon(watched ? Icons.favorite : Icons.favorite_outline),
            onPressed: () {
              final c = ref.read(watchlistProvider.notifier);
              watched
                  ? c.remove(product.id)
                  : c.add(
                      WatchlistItem(
                        productId: product.id,
                        productName: product.name,
                        brand: product.brand.name,
                        variant: product.tags.take(2).join(' · '),
                        image: product.icon,
                        createdAt: DateTime.now(),
                      ),
                    );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    watched
                        ? _t(context, 'Removed from Watchlist', 'వాచ్‌లిస్ట్ నుంచి తొలగించబడింది')
                        : _t(context, 'Added to Watchlist', 'వాచ్‌లిస్ట్‌కు జోడించబడింది'),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(_t(context, 'Could not load nearby prices', 'దగ్గరలోని ధరలను లోడ్ చేయలేకపోయాం'))),
        data: (all) {
          final results = matchNearby(listings: all, location: location, radiusKm: radius, filter: filter, sort: sort);
          final prices = results.map((e) => e.listing.effectivePrice).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.center,
                                child: Text(product.icon, style: const TextStyle(fontSize: 55)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.brand.name.toUpperCase(),
                                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                    Text(product.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                    Text(product.tags.take(2).join(' · ')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const LocationSelector(),
                          PriceBenchmarkSection(
                            productId: product.id,
                            localShopCount: results.length,
                            nearestShop: results.isEmpty ? '—' : results.reduce((a, b) => a.distanceKm < b.distanceKm ? a : b).listing.shopName,
                          ),
                          const SizedBox(height: 12),
                          if (prices.isNotEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _Stat(_t(context, 'Lowest', 'తక్కువ'), '₹${prices.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}'),
                                    _Stat(_t(context, 'Highest', 'ఎక్కువ'), '₹${prices.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}'),
                                    _Stat(_t(context, 'Average', 'సగటు'), '₹${(prices.reduce((a, b) => a + b) / prices.length).toStringAsFixed(0)}'),
                                    _Stat(_t(context, 'Shops', 'షాపులు'), '${prices.length}'),
                                  ],
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<SearchSortOption>(
                                  value: sort,
                                  decoration: InputDecoration(labelText: _t(context, 'Sort by', 'క్రమపరచండి')),
                                  items: SearchSortOption.values
                                      .map((e) => DropdownMenuItem(value: e, child: Text(_sortName(context, e))))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) ref.read(comparisonSortProvider.notifier).state = v;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () => _filters(context, ref),
                                icon: const Icon(Icons.filter_list),
                                label: Text(_t(context, 'Filters', 'ఫిల్టర్లు')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _te(context)
                                ? '${results.length} షాపులు అందుబాటులో ఉన్నాయి · దగ్గరది ${results.isEmpty ? '—' : '${results.map((e) => e.distanceKm).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} km'}'
                                : '${results.length} available shops · nearest ${results.isEmpty ? '—' : '${results.map((e) => e.distanceKm).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} km'}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  results.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(_t(context, 'No in-stock sellers match this radius and filters.', 'ఈ పరిధి మరియు ఫిల్టర్లకు సరిపడే స్టాక్ ఉన్న సెల్లర్లు లేరు.')),
                          ),
                        )
                      : SliverList.builder(
                          itemCount: results.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                            child: _SellerCard(result: results[i], all: results, index: i),
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _sortName(BuildContext context, SearchSortOption e) => switch (e) {
        SearchSortOption.lowestPrice => _t(context, 'Lowest price', 'తక్కువ ధర'),
        SearchSortOption.nearestShop => _t(context, 'Nearest shop', 'దగ్గర షాప్'),
        SearchSortOption.highestTrust => _t(context, 'Highest trust score', 'అత్యధిక ట్రస్ట్ స్కోర్'),
        SearchSortOption.bestOffer => _t(context, 'Best offer', 'ఉత్తమ ఆఫర్'),
        SearchSortOption.recentlyUpdated => _t(context, 'Recently updated', 'ఇటీవల అప్‌డేట్ చేసినవి'),
      };

  Future<void> _filters(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
        context: context,
        builder: (context) => Consumer(
          builder: (context, ref, _) {
            final f = ref.watch(searchFilterProvider);
            void set(SearchFilter n) => ref.read(searchFilterProvider.notifier).state = n;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_t(context, 'Filter shops', 'షాపులను ఫిల్టర్ చేయండి'), style: Theme.of(context).textTheme.titleLarge),
                    SwitchListTile(title: Text(_t(context, 'In stock only', 'స్టాక్‌లో ఉన్నవి మాత్రమే')), value: f.inStockOnly, onChanged: (v) => set(f.copyWith(inStockOnly: v))),
                    SwitchListTile(title: Text(_t(context, 'Offers only', 'ఆఫర్లు ఉన్నవి మాత్రమే')), value: f.offersOnly, onChanged: (v) => set(f.copyWith(offersOnly: v))),
                    SwitchListTile(title: Text(_t(context, 'Verified sellers only', 'వెరిఫైడ్ సెల్లర్లు మాత్రమే')), value: f.verifiedOnly, onChanged: (v) => set(f.copyWith(verifiedOnly: v))),
                    DropdownButtonFormField<String?>(
                      decoration: InputDecoration(labelText: _t(context, 'Shop category', 'షాప్ కేటగిరీ')),
                      value: f.shopCategory,
                      items: [
                        DropdownMenuItem(value: null, child: Text(_t(context, 'All categories', 'అన్ని కేటగిరీలు'))),
                        const DropdownMenuItem(value: 'Kirana', child: Text('Kirana')),
                        const DropdownMenuItem(value: 'Supermarket', child: Text('Supermarket')),
                        const DropdownMenuItem(value: 'Hypermarket', child: Text('Hypermarket')),
                      ],
                      onChanged: (v) => set(SearchFilter(inStockOnly: f.inStockOnly, offersOnly: f.offersOnly, verifiedOnly: f.verifiedOnly, shopCategory: v)),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: () => Navigator.pop(context), child: Text(_t(context, 'Show results', 'ఫలితాలు చూపండి'))),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _SellerCard extends ConsumerWidget {
  const _SellerCard({required this.result, required this.all, required this.index});
  final NearbySellerResult result;
  final List<NearbySellerResult> all;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = result.listing;
    final lowest = all.map((e) => e.listing.effectivePrice).reduce((a, b) => a < b ? a : b);
    final nearest = all.map((e) => e.distanceKm).reduce((a, b) => a < b ? a : b);
    final trusted = all.map((e) => e.listing.trustScore).reduce((a, b) => a > b ? a : b);
    final freshness = switch (l.freshness(DateTime.now())) {
      PriceFreshness.today => _t(context, 'Updated today', 'ఈరోజు అప్‌డేట్'),
      PriceFreshness.withinThreeDays => _t(context, 'Updated within 3 days', '3 రోజుల్లో అప్‌డేట్'),
      PriceFreshness.withinSevenDays => _t(context, 'Updated within 7 days', '7 రోజుల్లో అప్‌డేట్'),
      PriceFreshness.old => _t(context, 'Old price', 'పాత ధర'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.shopName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                if (l.verified) Chip(avatar: const Icon(Icons.verified, size: 16), label: Text(_t(context, 'Verified', 'వెరిఫైడ్'))),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                if (l.effectivePrice == lowest) Chip(label: Text(_t(context, 'Lowest Price', 'తక్కువ ధర'))),
                if (result.distanceKm == nearest) Chip(label: Text(_t(context, 'Nearest Shop', 'దగ్గర షాప్'))),
                if (l.trustScore == trusted) Chip(label: Text(_t(context, 'Most Trusted', 'అత్యంత నమ్మకమైనది'))),
                if (l.offerPrice != null) Chip(label: Text(_t(context, 'Best Value', 'ఉత్తమ విలువ'))),
              ],
            ),
            Row(
              children: [
                Text('₹${l.effectivePrice.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (l.offerPrice != null) ...[
                  const SizedBox(width: 8),
                  Text('₹${l.price.toStringAsFixed(0)}', style: const TextStyle(decoration: TextDecoration.lineThrough)),
                ],
                const Spacer(),
                Text('${result.distanceKm.toStringAsFixed(1)} km'),
              ],
            ),
            Text(
              '${l.inStock ? _t(context, 'In stock', 'స్టాక్‌లో ఉంది') : _t(context, 'Out of stock', 'స్టాక్ లేదు')} · $freshness · ${_t(context, 'Trust', 'ట్రస్ట్')} ${l.trustScore}/5 · ${l.isOpen ? _t(context, 'Open', 'తెరిచి ఉంది') : _t(context, 'Closed', 'మూసి ఉంది')}',
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _snack(context, _t(context, 'Calling is a placeholder', 'కాలింగ్ ప్రస్తుతం ప్లేస్‌హోల్డర్ మాత్రమే')),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(_t(context, 'Call', 'కాల్')),
                ),
                TextButton.icon(
                  onPressed: () => _snack(context, _t(context, 'Navigation is a placeholder', 'నావిగేషన్ ప్రస్తుతం ప్లేస్‌హోల్డర్ మాత్రమే')),
                  icon: const Icon(Icons.directions_outlined),
                  label: Text(_t(context, 'Navigate', 'నావిగేట్')),
                ),
                TextButton(
                  onPressed: () => _snack(context, _t(context, 'Shop details opened', 'షాప్ వివరాలు తెరవబడ్డాయి')),
                  child: Text(_t(context, 'View Shop', 'షాప్ చూడండి')),
                ),
                TextButton(
                  onPressed: () => _report(context, ref, l),
                  child: Text(_t(context, 'Report Wrong Price', 'తప్పు ధరను రిపోర్ట్ చేయండి')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _report(BuildContext context, WidgetRef ref, ProductPriceListing listing) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_t(context, 'Report wrong price', 'తప్పు ధరను రిపోర్ట్ చేయండి')),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: _t(context, 'What is wrong?', 'ఏం తప్పు ఉంది?'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(_t(context, 'Cancel', 'రద్దు'))),
          FilledButton(
            onPressed: () {
              ref.read(buyerRepositoryProvider).reportWrongPrice(
                    WrongPriceReport(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      listingId: listing.id,
                      reason: controller.text,
                      createdAt: DateTime.now(),
                    ),
                  );
              Navigator.pop(c);
              _snack(context, _t(context, 'Thank you. Report submitted.', 'ధన్యవాదాలు. రిపోర్ట్ సమర్పించబడింది.'));
            },
            child: Text(_t(context, 'Submit', 'సమర్పించండి')),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}
