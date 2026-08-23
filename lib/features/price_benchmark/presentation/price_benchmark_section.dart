import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/price_benchmark_providers.dart';
import '../domain/price_benchmark_models.dart';
import '../domain/price_benchmark_services.dart';

class PriceBenchmarkSection extends ConsumerWidget {
  const PriceBenchmarkSection({
    required this.productId,
    required this.localShopCount,
    required this.nearestShop,
    super.key,
  });

  final String productId;
  final int localShopCount;
  final String nearestShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final benchmark = ref.watch(priceBenchmarkProvider(productId));
    final listings = ref.watch(onlinePriceListingsProvider(productId));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Price benchmark', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        benchmark.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _Message(icon: Icons.sync_problem, text: 'Price comparison is unavailable right now.'),
          data: (b) {
            if (b == null) {
              return const _Message(icon: Icons.info_outline, text: 'Not enough price observations yet.');
            }
            final insight = const PriceInsightService().create(
              localLowest: b.localLowest,
              onlineLowest: b.onlineLowest,
              freshness: b.freshness,
            );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Local lowest: ${money.format(b.localLowest)}'),
                    Text('Local average: ${money.format(b.localAverage)}'),
                    Text('Online lowest: ${money.format(b.onlineLowest)}'),
                    Text('Nearby shops: $localShopCount'),
                    Text('Nearest shop: $nearestShop'),
                    const Divider(),
                    Text(_insightText(insight, money), style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Potential saving: ${money.format(b.savingsAmount)} (${b.savingsPercentage.toStringAsFixed(1)}%)'),
                  ],
                ),
              ),
            );
          },
        ),
        listings.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const _Message(icon: Icons.cloud_off, text: 'Online price sources are unavailable.'),
          data: (items) => ExpansionTile(
            title: const Text('Online sources'),
            children: [
              for (final item in items.where((entry) => entry.available))
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
                  title: Text(item.source.name),
                  subtitle: Text(item.packSize),
                  trailing: Text(
                    money.format(const EffectivePriceCalculator().online(item).total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline),
                SizedBox(width: 10),
                Expanded(child: Text('Prices are observations and may change. Confirm the final price with the seller before completing the deal.')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _insightText(PriceInsight insight, NumberFormat money) {
    return switch (insight.type) {
      PriceInsightType.localCheaper => 'Local is cheaper by ${money.format(insight.amount)}',
      PriceInsightType.onlineCheaper => 'Online is cheaper by ${money.format(insight.amount)}',
      PriceInsightType.pricesSimilar => 'Local and online prices are similar',
      PriceInsightType.stale => 'Some price observations are old',
      PriceInsightType.onlineUnavailable => 'No online price is available',
      PriceInsightType.localUnavailable => 'No local seller price is available',
      PriceInsightType.productMismatch => 'The compared product or pack does not match',
      PriceInsightType.insufficientData => 'Not enough observations to compare',
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(text));
}
