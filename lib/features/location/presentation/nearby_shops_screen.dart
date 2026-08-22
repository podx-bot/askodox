import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/location_controller.dart';
import '../domain/geo_models.dart';

class NearbyShopsScreen extends ConsumerWidget {
  const NearbyShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final radii = <double>[100, 200, 500, 1000, 2000, 5000, 7500, 10000, 25000, 50000];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby shops'),
        actions: [
          IconButton(
            tooltip: 'Location settings',
            onPressed: () => context.push('/location'),
            icon: const Icon(Icons.location_on_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_radius(state.radiusMetres)} radius · ${state.shops.length} results',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SegmentedButton<MapDisplayMode>(
                  key: const Key('viewToggle'),
                  segments: const [
                    ButtonSegment(value: MapDisplayMode.map, icon: Icon(Icons.map_outlined), label: Text('Map')),
                    ButtonSegment(value: MapDisplayMode.list, icon: Icon(Icons.list), label: Text('List')),
                  ],
                  selected: {state.mode},
                  onSelectionChanged: (value) => controller.toggleMode(value.first),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                for (final radius in radii)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_radius(radius)),
                      selected: state.radiusMetres == radius,
                      onSelected: (_) => controller.setRadius(radius),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.mode == MapDisplayMode.map
                    ? _MapPreview(state: state)
                    : _ShopList(shops: state.shops),
          ),
          if (state.message != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                title: Text(state.message!),
                trailing: TextButton(onPressed: controller.refresh, child: const Text('Retry')),
              ),
            ),
        ],
      ),
    );
  }

  static String _radius(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km';
}

class _MapPreview extends ConsumerWidget {
  const _MapPreview({required this.state});
  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(locationControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Nearby map preview'),
              subtitle: Text('${state.shops.length} shops in this search area'),
              trailing: IconButton(
                tooltip: 'Recenter',
                onPressed: () => controller.moveMap(state.defaultLocation?.point ?? const GeoPoint(17.4156, 78.4347)),
                icon: const Icon(Icons.my_location),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final shop in state.shops)
                    ListTile(
                      leading: const Icon(Icons.store),
                      title: Text(shop.name),
                      subtitle: Text('${shop.category} · ${(shop.distanceMetres / 1000).toStringAsFixed(1)} km'),
                      selected: state.selectedShopId == shop.id,
                      onTap: () => controller.selectShop(shop.id),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('searchArea'),
                      onPressed: controller.searchThisArea,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Search this area'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: controller.saveSelectedArea,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save area'),
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

class _ShopList extends StatelessWidget {
  const _ShopList({required this.shops});
  final List<NearbyShop> shops;

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) {
      return const Center(child: Text('No nearby shops. Try a larger radius.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: shops.length,
      itemBuilder: (_, index) => _ShopCard(shop: shops[index]),
    );
  }
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});
  final NearbyShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.storefront)),
        title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${shop.category} · ${shop.distanceMetres < 1000 ? '${shop.distanceMetres.round()} m' : '${(shop.distanceMetres / 1000).toStringAsFixed(1)} km'}\n${shop.productCount} products · ${shop.activeOffers} offers',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/shop/${shop.id}'),
      ),
    );
  }
}
