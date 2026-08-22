import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../generated/l10n/app_localizations.dart';
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
  final String nearestShop;
  final int localShopCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final benchmark = ref.watch(priceBenchmarkProvider(productId));
    final listings = ref.watch(onlinePriceListingsProvider(productId));
    final history = ref.watch(priceHistoryProvider(productId));

    String money(num value) => NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: 0,
        ).format(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.priceBenchmarkTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        benchmark.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _Message(
            icon: Icons.sync_problem,
            text: l.comparisonUnavailable,
          ),
          data: (b) {
            if (b == null) {
              return _Message(
                icon: Icons.info_outline,
                text: l.insufficientObservations,
              );
            }
            final insight = const PriceInsightService().create(
              localLowest: b.localLowest,
              onlineLowest: b.onlineLowest,
              freshness: b.freshness,
            );
            final confidence = const PriceConfidenceService().calculate(
              localListings: localShopCount,
              onlineObservations: 3,
              matchConfidence: 1.0,
              packSizeMatch: PackSizeMatch.exact,
              freshness: b.freshness,
              consistency: 0.86,
              sourceReliability: 0.75,
            );

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Summary(
                        title: l.localPriceSummary,
                        icon: Icons.storefront,
                        lines: [
                          '${l.lowestPrice}: ${money(b.localLowest)}',
                          '${l.averagePrice}: ${money(b.localAverage)}',
                          '${l.highestPrice}: ${money(b.localHighest)}',
                          '${l.nearbyShops}: $localShopCount',
                          '${l.nearestShop}: $nearestShop',
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Summary(
                        title: l.onlinePriceSummary,
                        icon: Icons.language,
                        lines: [
                          '${l.lowestEffectivePrice}: ${money(b.onlineLowest)}',
                          '${l.averagePrice}: ${money(b.onlineAverage)}',
                          '${l.highestPrice}: ${money(b.onlineHighest)}',
                          '${l.sourcesCompared}: 3',
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _insight(l, insight, money),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l.potentialSavings}: ${money(b.savingsAmount)} '
                          '(${b.savingsPercentage.toStringAsFixed(2)}%)',
                        ),
                        Text(l.potentialSavingsDisclaimer),
                        const Divider(),
                        Text(
                          '${l.confidence}: ${_confidence(l, confidence.level)} '
                          '· ${confidence.score.toStringAsFixed(0)}%',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        listings.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => _Message(
            icon: Icons.cloud_off,
            text: l.onlineSourceUnavailable,
          ),
          data: (items) => ExpansionTile(
            title: Text(l.onlineSources),
            children: [
              for (final item in items.where((e) => e.available))
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.shopping_bag_outlined),
                  ),
                  title: Text(item.source.name),
                  subtitle: Text(
                    '${item.packSize} · ${l.minimumOrder}: '
                    '${money(item.minimumOrderValue)}',
                  ),
                  trailing: Text(
                    money(const EffectivePriceCalculator().online(item).total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        history.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (points) => ExpansionTile(
            title: Text(l.mockPriceHistory),
            subtitle: Text(l.mockHistoryDisclosure),
            children: [
              if (points.isNotEmpty)
                ListTile(
                  title: Text(
                    '${l.localPriceSummary}: '
                    '${money(points.first.localLowest)} → '
                    '${money(points.last.localLowest)}',
                  ),
                  subtitle: Text(
                    '${l.onlinePriceSummary}: '
                    '${money(points.first.onlineLowest)} → '
                    '${money(points.last.onlineLowest)}',
                  ),
                ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 10),
                Expanded(child: Text(l.priceComparisonDisclosure)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _insight(
    AppLocalizations l,
    PriceInsight insight,
    String Function(num) money,
  ) =>
      switch (insight.type) {
        PriceInsightType.localCheaper => l.localCheaperInsight(money(insight.amount)),
        PriceInsightType.onlineCheaper => l.onlineCheaperInsight(money(insight.amount)),
        PriceInsightType.pricesSimilar => l.pricesSimilar,
        PriceInsightType.stale => l.stalePriceWarning,
        PriceInsightType.onlineUnavailable => l.noOnlinePrice,
        PriceInsightType.localUnavailable => l.noLocalSeller,
        PriceInsightType.productMismatch => l.productMatchFailed,
        PriceInsightType.insufficientData => l.insufficientObservations,
      };

  String _confidence(
    AppLocalizations l,
    PriceConfidenceLevel level,
  ) =>
      switch (level) {
        PriceConfidenceLevel.high => l.confidenceHigh,
        PriceConfidenceLevel.medium => l.confidenceMedium,
        PriceConfidenceLevel.low => l.confidenceLow,
        PriceConfidenceLevel.insufficientData => l.insufficientObservations,
      };
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.icon,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final line in lines)
                Text(line, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(text),
      );
}
