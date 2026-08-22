import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/location_controller.dart';
import '../domain/geo_models.dart';

class NearbyShopsScreen extends ConsumerWidget {
  const NearbyShopsScreen({super.key});

  static const List<double> _radiusOptions = <double>[
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    25000,
    50000,
    7500,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby shops'),
        actions: [
          IconButton(
            key: const Key('nearbyLocationSettings'),
            tooltip: 'Location settings',
            onPressed: () => context.push('/location'),
            icon: const Icon(Icons.location_on_outlined),
          ),
          IconButton(
            key: const Key('nearbyFilters'),
            tooltip: 'Filters',
            onPressed: () => _showFilters(context, ref),
            icon: const Icon(Icons.filter_list),
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
                    ButtonSegment(
                      value: MapDisplayMode.map,
                      icon: Icon(Icons.map_outlined),
                      label: Text('Map'),
                    ),
                    ButtonSegment(
                      value: MapDisplayMode.list,
                      icon: Icon(Icons.list),
                      label: Text('List'),
                    ),
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
                for (final radius in _radiusOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('nearbyRadius-${radius.round()}'),
                      label: Text(
                        radius == 7500
                            ? 'Custom (${_radius(radius)})'
                            : _radius(radius),
                      ),
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
                    ? _MockMap(state: state)
                    : _ShopList(shops: state.shops),
          ),
          if (state.message != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                title: Text(state.message!),
                trailing: TextButton(
                  key: const Key('nearbyRetry'),
                  onPressed: controller.refresh,
                  child: const Text('Retry'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _showFilters(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(locationControllerProvider);
          final controller = ref.read(locationControllerProvider.notifier);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Nearby filters', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const Text('Search radius'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final radius in _radiusOptions)
                        ChoiceChip(
                          key: Key('nearbyFilterRadius-${radius.round()}'),
                          label: Text(_radius(radius)),
                          selected: state.radiusMetres == radius,
                          onSelected: (_) => controller.setRadius(radius),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<MapDisplayMode>(
                    key: const Key('nearbyFilterViewMode'),
                    segments: const [
                      ButtonSegment(value: MapDisplayMode.map, label: Text('Map'), icon: Icon(Icons.map_outlined)),
                      ButtonSegment(value: MapDisplayMode.list, label: Text('List'), icon: Icon(Icons.list)),
                    ],
                    selected: {state.mode},
                    onSelectionChanged: (value) => controller.toggleMode(value.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('nearbyApplyFilters'),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Show results'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _radius(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km';
}

class _MockMap extends ConsumerWidget {
  const _MockMap({required this.state});

  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(locationControllerProvider.notifier);
    final selected = state.shops
        .where((shop) => shop.id == state.selectedShopId)
        .firstOrNull;

    return Stack(
      children: [
        Semantics(
          label: 'Mock map canvas',
          child: Container(
            key: const Key('mockMap'),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: CustomPaint(
              painter: _MapPainter(Theme.of(context).colorScheme),
              child: Stack(
                children: [
                  Positioned(
                    left: MediaQuery.sizeOf(context).width * .42,
                    top: 130,
                    child: const _Marker(
                      icon: Icons.person_pin_circle,
                      label: 'You',
                    ),
                  ),
                  for (var index = 0; index < state.shops.length; index++)
                    Positioned(
                      left: 40.0 + ((index * 95) % 260).toDouble(),
                      top: 220.0 + ((index % 2) * 90).toDouble(),
                      child: GestureDetector(
                        key: Key('nearbyMapMarker-${state.shops[index].id}'),
                        onTap: () => controller.selectShop(state.shops[index].id),
                        child: _Marker(
                          icon: Icons.store,
                          label: state.shops[index].name,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 24,
          top: 24,
          child: FloatingActionButton.small(
            key: const Key('nearbyRecenter'),
            heroTag: 'recenter',
            tooltip: 'Recenter',
            onPressed: () => controller.moveMap(
              state.defaultLocation?.point ?? const GeoPoint(17.4156, 78.4347),
            ),
            child: const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: 24,
          child: Center(
            child: FilledButton.icon(
              key: const Key('searchArea'),
              onPressed: controller.searchThisArea,
              icon: const Icon(Icons.refresh),
              label: const Text('Search this area'),
            ),
          ),
        ),
        Positioned(
          left: 24,
          bottom: selected == null ? 24 : 150,
          child: OutlinedButton.icon(
            key: const Key('nearbySaveArea'),
            onPressed: controller.saveSelectedArea,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save this area'),
          ),
        ),
        if (selected != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: _ShopCard(shop: selected),
          ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Icon(
          icon,
          size: 44,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.colors);

  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final circlePaint = Paint()
      ..color = colors.primary.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide * .3,
      circlePaint,
    );

    final roadPaint = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 4;
    for (double y = 70; y < size.height; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 35), roadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}

class _ShopList extends StatelessWidget {
  const _ShopList({required this.shops});

  final List<NearbyShop> shops;

  @override
  Widget build(BuildContext context) => shops.isEmpty
      ? const _Empty()
      : ListView.builder(
          key: const Key('nearbyShopList'),
          padding: const EdgeInsets.all(12),
          itemCount: shops.length,
          itemBuilder: (_, index) => _ShopCard(shop: shops[index]),
        );
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});

  final NearbyShop shop;

  String get _distanceLabel => shop.distanceMetres < 1000
      ? '${shop.distanceMetres.round()} m'
      : '${(shop.distanceMetres / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        key: Key('nearbyShopCard-${shop.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(
                  shop.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${shop.category} · $_distanceLabel'),
                trailing: Chip(
                  avatar: Icon(
                    shop.verified ? Icons.verified : Icons.info_outline,
                    size: 16,
                  ),
                  label: Text('${shop.trustScore}'),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  Chip(label: Text(shop.isOpen ? 'Open' : 'Closed')),
                  Chip(label: Text('${shop.productCount} products')),
                  Chip(label: Text('${shop.watchlistMatches} matches')),
                  Chip(label: Text('${shop.activeOffers} offers')),
                ],
              ),
              Wrap(
                children: [
                  TextButton(
                    key: Key('nearbyViewShop-${shop.id}'),
                    onPressed: () => context.push('/shop/${shop.id}'),
                    child: const Text('View shop'),
                  ),
                  TextButton(
                    key: Key('nearbyViewOnMap-${shop.id}'),
                    onPressed: () {
                      final controller = ref.read(locationControllerProvider.notifier);
                      controller.selectShop(shop.id);
                      controller.toggleMode(MapDisplayMode.map);
                    },
                    child: const Text('View on map'),
                  ),
                  PopupMenuButton<String>(
                    key: Key('nearbyMore-${shop.id}'),
                    onSelected: (value) {
                      final controller = ref.read(locationControllerProvider.notifier);
                      switch (value) {
                        case 'call':
                          _message(context, 'Calling ${shop.name} is not connected yet.');
                        case 'navigate':
                          controller.selectShop(shop.id);
                          controller.toggleMode(MapDisplayMode.map);
                          _message(context, 'Showing ${shop.name} on the map.');
                        case 'follow':
                          _message(context, '${shop.name} follow preference saved for this demo.');
                        case 'report':
                          _message(context, 'Report option opened for ${shop.name}.');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'call', child: Text('Call')),
                      PopupMenuItem(value: 'navigate', child: Text('Navigate')),
                      PopupMenuItem(value: 'follow', child: Text('Follow shop')),
                      PopupMenuItem(value: 'report', child: Text('Report shop')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 64),
            const Text('No nearby shops'),
            const Text('Try a larger radius or choose another location.'),
            FilledButton(
              key: const Key('nearbyChooseLocation'),
              onPressed: () => context.push('/location'),
              child: const Text('Choose location'),
            ),
          ],
        ),
      );
}
