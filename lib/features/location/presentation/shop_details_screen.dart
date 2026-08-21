import 'package:flutter/material.dart';

import '../data/mock_geo_repository.dart';

enum ShopProductSort {
  lowestPrice,
  highestPrice,
  recentlyUpdated,
  inStock,
  offers,
}

class ShopDetailsScreen extends StatefulWidget {
  const ShopDetailsScreen({required this.shopId, super.key});

  final String shopId;

  @override
  State<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends State<ShopDetailsScreen> {
  ShopProductSort sort = ShopProductSort.lowestPrice;

  static const _products = <_ShopProduct>[
    _ShopProduct('Mock product 1', 99, true, 0, false),
    _ShopProduct('Mock product 2', 279, false, 1, true),
    _ShopProduct('Mock product 3', 189, true, 0, true),
    _ShopProduct('Mock product 4', 369, false, 2, false),
    _ShopProduct('Mock product 5', 144, true, 1, false),
  ];

  @override
  Widget build(BuildContext context) {
    final shop = mockNearbyShops.where((s) => s.id == widget.shopId).firstOrNull;
    if (shop == null) {
      return const Scaffold(body: Center(child: Text('Shop unavailable')));
    }

    final products = [..._products]..sort(_compareProducts);

    return Scaffold(
      appBar: AppBar(title: Text(shop.name)),
      body: ListView(
        key: const Key('shopDetailsList'),
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
            title: Text(shop.verified ? 'Verified shop' : 'Verification pending'),
            subtitle: Text(
              'Trust score ${shop.trustScore} · Open 9:00 AM–9:00 PM',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('shopDetailsCall'),
                onPressed: () => _message('Shop contact is not published yet'),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call'),
              ),
              OutlinedButton.icon(
                key: const Key('shopDetailsNavigate'),
                onPressed: () => _message('Opening directions is not configured yet'),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Directions'),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Available categories', style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(shop.category)),
              const Chip(label: Text('Groceries')),
              const Chip(label: Text('Household')),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active offers'),
            subtitle: Text('${shop.activeOffers} offers · Prices refreshed today'),
          ),
          DropdownButtonFormField<ShopProductSort>(
            key: const Key('shopProductSort'),
            initialValue: sort,
            decoration: const InputDecoration(labelText: 'Sort products'),
            items: ShopProductSort.values
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => sort = value);
            },
          ),
          const SizedBox(height: 8),
          for (final product in products)
            ListTile(
              key: Key('shopProduct-${product.name}'),
              leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
              title: Text(product.name),
              subtitle: Text(
                '${product.inStock ? 'In stock' : 'Low stock'} · '
                '${product.updatedDaysAgo == 0 ? 'Updated today' : 'Updated ${product.updatedDaysAgo} day${product.updatedDaysAgo == 1 ? '' : 's'} ago'}'
                '${product.offer ? ' · Offer' : ''}',
              ),
              trailing: Text('₹${product.price.toStringAsFixed(0)}'),
            ),
        ],
      ),
    );
  }

  int _compareProducts(_ShopProduct a, _ShopProduct b) => switch (sort) {
        ShopProductSort.lowestPrice => a.price.compareTo(b.price),
        ShopProductSort.highestPrice => b.price.compareTo(a.price),
        ShopProductSort.recentlyUpdated => a.updatedDaysAgo.compareTo(b.updatedDaysAgo),
        ShopProductSort.inStock => _boolRank(b.inStock).compareTo(_boolRank(a.inStock)),
        ShopProductSort.offers => _boolRank(b.offer).compareTo(_boolRank(a.offer)),
      };

  int _boolRank(bool value) => value ? 1 : 0;

  String _label(ShopProductSort value) => switch (value) {
        ShopProductSort.lowestPrice => 'Lowest price',
        ShopProductSort.highestPrice => 'Highest price',
        ShopProductSort.recentlyUpdated => 'Recently updated',
        ShopProductSort.inStock => 'In stock',
        ShopProductSort.offers => 'Offers',
      };

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ShopProduct {
  const _ShopProduct(
    this.name,
    this.price,
    this.inStock,
    this.updatedDaysAgo,
    this.offer,
  );

  final String name;
  final double price;
  final bool inStock;
  final int updatedDaysAgo;
  final bool offer;
}
