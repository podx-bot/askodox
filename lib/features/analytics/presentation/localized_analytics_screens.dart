import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/analytics_providers.dart';
import 'analytics_screens.dart';
import 'analytics_widgets.dart';

class LocalizedSellerAnalyticsScreen extends ConsumerWidget {
  const LocalizedSellerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    if (!te) return const SellerAnalyticsScreen();

    final metrics = ref.watch(sellerMetricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('సెల్లర్ అనలిటిక్స్')),
      body: metrics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(sellerMetricsProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('మీ బిజినెస్ పనితీరు', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('ప్రైవసీ-సేఫ్ సమగ్ర డేటాతో మీ షాప్ పనితీరును చూడండి.'),
            const SizedBox(height: 16),
            const SimpleLineChart(values: [34, 49, 42, 68, 61, 84, 92], summary: 'ఎంగేజ్‌మెంట్ ట్రెండ్'),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('ఇంకా అనలిటిక్స్ డేటా లేదు.')))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 135,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => MetricTrendCard(metric: items[i].metric),
              ),
          ],
        ),
      ),
    );
  }
}

class LocalizedProductPerformanceScreen extends ConsumerWidget {
  const LocalizedProductPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    if (!te) return const ProductPerformanceScreen();

    final products = ref.watch(productPerformanceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ఉత్పత్తుల పనితీరు')),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(productPerformanceProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('వ్యూస్, సెర్చ్‌లు, వాచ్‌లిస్ట్‌లు, రిక్వెస్టులు మరియు కన్వర్షన్ సంకేతాలను ఒకే చోట చూడండి.'),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('ఇంకా ఉత్పత్తి పనితీరు డేటా లేదు.')))
            else
              for (final p in items)
                Card(
                  child: ExpansionTile(
                    title: Text(p.name),
                    subtitle: Text('₹${p.price.toStringAsFixed(0)} · ${p.inStock ? 'స్టాక్‌లో ఉంది' : 'స్టాక్ లేదు'} · ${_teluguValue(p.demand.name)}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            Text('వ్యూస్ ${p.views}'),
                            Text('సెర్చ్‌లు ${p.searchAppearances}'),
                            Text('పోలికలు ${p.comparisonViews}'),
                            Text('వాచ్‌లిస్ట్‌లు ${p.watchlistAdds}'),
                            Text('రిక్వెస్టులు ${p.requests}'),
                            Text('ఆఫర్ క్లిక్స్ ${p.offerClicks}'),
                            Text('కన్వర్షన్ ${p.conversionProxy.toStringAsFixed(1)}%'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class LocalizedSellerMarketAnalyticsScreen extends ConsumerWidget {
  const LocalizedSellerMarketAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    if (!te) return const SellerMarketAnalyticsScreen();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('మార్కెట్ అనలిటిక్స్'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'ధర పోలిక'),
              Tab(text: 'డిమాండ్'),
              Tab(text: 'ఏరియా'),
              Tab(text: 'క్యాంపెయిన్‌లు'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LocalizedPrices(),
            _LocalizedDemand(),
            _LocalizedAreas(),
            _LocalizedCampaigns(),
          ],
        ),
      ),
    );
  }
}

class _LocalizedPrices extends ConsumerWidget {
  const _LocalizedPrices();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(priceCompetitivenessProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(priceCompetitivenessProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final p in items)
              Card(
                child: ListTile(
                  title: Text(p.product),
                  subtitle: Text('మీ ధర ₹${p.sellerPrice.toStringAsFixed(0)} · దగ్గర ధర ₹${p.lowest.toStringAsFixed(0)}–₹${p.highest.toStringAsFixed(0)} · సగటు ₹${p.average.toStringAsFixed(0)}\n${p.suggestion}'),
                  trailing: Chip(label: Text(_teluguValue(p.label.name))),
                ),
              ),
          ],
        ),
      );
}

class _LocalizedDemand extends ConsumerWidget {
  const _LocalizedDemand();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(demandAnalyticsProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(demandAnalyticsProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const SimpleLineChart(values: [42, 56, 51, 78, 92, 88, 110], summary: 'ఎంచుకున్న కాలంలో సమగ్ర డిమాండ్ ట్రెండ్'),
            for (final d in items)
              Card(
                child: ListTile(
                  title: Text(d.product),
                  subtitle: Text('సెర్చ్‌లు ${d.searches} · వాచ్‌లిస్ట్‌లు ${d.watchlists} · రిక్వెస్టులు ${d.requests}\nబయర్ ఇంటెంట్ ${d.buyerIntents} · సరఫరా ${d.supply} · నిష్పత్తి ${d.ratio.toStringAsFixed(1)}'),
                  trailing: Chip(label: Text(_teluguValue(d.level.name))),
                ),
              ),
          ],
        ),
      );
}

class _LocalizedAreas extends ConsumerWidget {
  const _LocalizedAreas();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(areaAnalyticsProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(areaAnalyticsProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final a in items)
              Card(
                child: ListTile(
                  title: Text(a.area),
                  subtitle: Text('${a.activeSellers} సెల్లర్లు · ${a.availability}% అందుబాటు · సగటు ₹${a.averagePrice.toStringAsFixed(0)}\n${a.requests} రిక్వెస్టులు · ${a.supplyGaps} సరఫరా లోపాలు · డిమాండ్ ${a.demand}'),
                ),
              ),
          ],
        ),
      );
}

class _LocalizedCampaigns extends ConsumerWidget {
  const _LocalizedCampaigns();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(campaignAnalyticsProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, () => ref.invalidate(campaignAnalyticsProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final x in items)
              Card(
                child: ListTile(
                  title: Text(x.name),
                  subtitle: Text('${_teluguValue(x.status)}\n${x.impressions} ఇంప్రెషన్స్ · ${x.views} వ్యూస్ · ${x.clicks} క్లిక్స్ · ${x.followers} ఫాలోస్ · ${x.requests} రిక్వెస్టులు\nCTR ${x.clickThroughRate.toStringAsFixed(1)}% · ఎంగేజ్‌మెంట్ ${x.engagementRate.toStringAsFixed(1)}%'),
                ),
              ),
          ],
        ),
      );
}

Widget _retry(BuildContext context, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 52),
            const SizedBox(height: 12),
            const Text('డేటా తాత్కాలికంగా అందుబాటులో లేదు'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: retry, child: const Text('మళ్లీ ప్రయత్నించండి')),
          ],
        ),
      ),
    );

String _teluguValue(String value) {
  switch (value.toLowerCase()) {
    case 'high':
      return 'ఎక్కువ';
    case 'medium':
      return 'మధ్యస్థ';
    case 'low':
      return 'తక్కువ';
    case 'veryhigh':
    case 'very_high':
      return 'చాలా ఎక్కువ';
    case 'active':
      return 'యాక్టివ్';
    case 'completed':
      return 'పూర్తైంది';
    case 'paused':
      return 'పాజ్‌లో ఉంది';
    case 'competitive':
      return 'పోటీ ధర';
    case 'expensive':
      return 'ధర ఎక్కువ';
    case 'cheap':
      return 'ధర తక్కువ';
    default:
      return value;
  }
}
