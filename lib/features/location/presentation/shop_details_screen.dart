import 'package:flutter/material.dart';

import '../data/mock_geo_repository.dart';

enum ShopProductSort { lowestPrice, highestPrice, recentlyUpdated, inStock, offers }

class ShopDetailsScreen extends StatefulWidget {
  const ShopDetailsScreen({required this.shopId, super.key});
  final String shopId;

  @override
  State<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends State<ShopDetailsScreen> {
  ShopProductSort sort = ShopProductSort.lowestPrice;

  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override
  Widget build(BuildContext context) {
    final shop = mockNearbyShops.where((s) => s.id == widget.shopId).firstOrNull;
    if (shop == null) {
      return Scaffold(
        body: Center(child: Text(t('Shop unavailable', 'షాప్ అందుబాటులో లేదు'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(shop.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.storefront, size: 80),
          ),
          const SizedBox(height: 16),
          Text(shop.businessName, style: Theme.of(context).textTheme.headlineSmall),
          Text(shop.address),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(shop.verified ? Icons.verified : Icons.info),
            title: Text(
              shop.verified ? t('Verified shop', 'వెరిఫైడ్ షాప్') : t('Verification pending', 'వెరిఫికేషన్ పెండింగ్'),
            ),
            subtitle: Text(
              te
                  ? 'ట్రస్ట్ స్కోర్ ${shop.trustScore} · ఉదయం 9:00–రాత్రి 9:00 వరకు తెరిచి ఉంటుంది\nసంప్రదింపు వివరాలు త్వరలో'
                  : 'Trust score ${shop.trustScore} · Open 9:00 AM–9:00 PM\nContact details coming soon',
            ),
          ),
          const Divider(),
          Text(t('Available categories', 'అందుబాటులో ఉన్న కేటగిరీలు'), style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(shop.category)),
              Chip(label: Text(t('Groceries', 'కిరాణా'))),
              Chip(label: Text(t('Household', 'గృహ అవసరాలు'))),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('Active offers', 'యాక్టివ్ ఆఫర్లు')),
            subtitle: Text(
              te
                  ? '${shop.activeOffers} ఆఫర్లు · ధరలు ఈరోజు అప్‌డేట్ అయ్యాయి'
                  : '${shop.activeOffers} offers · Prices refreshed today',
            ),
          ),
          DropdownButtonFormField<ShopProductSort>(
            initialValue: sort,
            decoration: InputDecoration(labelText: t('Sort products', 'ఉత్పత్తులను క్రమబద్ధీకరించండి')),
            items: ShopProductSort.values
                .map((value) => DropdownMenuItem(value: value, child: Text(_label(value))))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => sort = value);
            },
          ),
          ...List.generate(
            5,
            (index) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
              title: Text(te ? 'టెస్ట్ ఉత్పత్తి ${index + 1}' : 'Mock product ${index + 1}'),
              subtitle: Text(
                index.isEven
                    ? t('In stock · Updated today', 'స్టాక్‌లో ఉంది · ఈరోజు అప్‌డేట్ అయింది')
                    : t('Low stock · Updated yesterday', 'తక్కువ స్టాక్ · నిన్న అప్‌డేట్ అయింది'),
              ),
              trailing: Text('₹${99 + index * 45}'),
            ),
          ),
        ],
      ),
    );
  }

  String _label(ShopProductSort value) => switch (value) {
        ShopProductSort.lowestPrice => t('Lowest price', 'తక్కువ ధర'),
        ShopProductSort.highestPrice => t('Highest price', 'ఎక్కువ ధర'),
        ShopProductSort.recentlyUpdated => t('Recently updated', 'ఇటీవల అప్‌డేట్ చేసినవి'),
        ShopProductSort.inStock => t('In stock', 'స్టాక్‌లో ఉన్నవి'),
        ShopProductSort.offers => t('Offers', 'ఆఫర్లు'),
      };
}
