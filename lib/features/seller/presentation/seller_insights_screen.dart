import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/seller_providers.dart';
import '../../watchlist/application/watchlist_providers.dart';

class SellerInsightsScreen extends ConsumerWidget {
  const SellerInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(sellerProvider).insights;
    final demand = ref.watch(demandInsightsProvider);
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;

    return Scaffold(
      appBar: AppBar(title: Text(t('Seller insights', 'సెల్లర్ ఇన్‌సైట్స్'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t('Demand around your shop', 'మీ షాప్ చుట్టుపక్కల డిమాండ్'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(t(
                'Mock trends based on nearby searches and watchlists.',
                'దగ్గరలో జరిగిన సెర్చ్‌లు మరియు వాచ్‌లిస్ట్‌ల ఆధారంగా నమూనా ట్రెండ్స్.',
              )),
              const SizedBox(height: 20),
              for (final item in demand)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights),
                    title: Text(item.productName),
                    subtitle: Text(
                      te
                          ? '5 కి.మీ లో ${item.score.interestedBuyers} మంది కొనుగోలుదారులు ఆసక్తి చూపుతున్నారు · ఈ వారం ${item.score.watchlists} వాచ్‌లిస్ట్ జోడింపులు · ${item.score.requests} యాక్టివ్ ఉత్పత్తి రిక్వెస్టులు'
                          : '${item.score.interestedBuyers} buyers interested within 5 km · ${item.score.watchlists} watchlist additions this week · ${item.score.requests} active product requests',
                    ),
                    trailing: Chip(label: Text(item.score.level)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t(
                    'Suggested products to stock · Aggregated and privacy-safe',
                    'స్టాక్ చేయడానికి సూచించిన ఉత్పత్తులు · సమగ్రంగా, ప్రైవసీ సేఫ్‌గా',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final insight in insights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(child: Icon(_icon(insight.type))),
                      title: Text(insight.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(insight.title),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${insight.score}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          Text(t('demand', 'డిమాండ్')),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
        'search' => Icons.search,
        'watchlist' => Icons.favorite_outline,
        'missing' => Icons.add_business,
        _ => Icons.update,
      };
}
