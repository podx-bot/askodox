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
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 52),
                const SizedBox(height: 12),
                const Text('డేటా తాత్కాలికంగా అందుబాటులో లేదు'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => ref.invalidate(sellerMetricsProvider), child: const Text('మళ్లీ ప్రయత్నించండి')),
              ],
            ),
          ),
        ),
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
