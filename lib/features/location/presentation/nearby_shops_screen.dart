import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../application/location_controller.dart';
import '../domain/geo_models.dart';

class NearbyShopsScreen extends ConsumerWidget {
  const NearbyShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final te = ref.watch(appSettingsProvider).locale?.languageCode == 'te';
    const radii = <double>[100, 200, 500, 1000, 2000, 5000, 10000, 25000, 50000, 7500];

    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'దగ్గరలోని దుకాణాలు' : 'Nearby shops'),
        actions: [
          IconButton(
            tooltip: te ? 'లొకేషన్ సెట్టింగ్స్' : 'Location settings',
            onPressed: () => context.push('/location'),
            icon: const Icon(Icons.location_on_outlined),
          ),
          IconButton(
            tooltip: te ? 'ఫిల్టర్లు' : 'Filters',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(te ? 'దగ్గరలోని ఫిల్టర్లు త్వరలో అందుబాటులో ఉంటాయి' : 'Nearby filters placeholder')),
            ),
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
                    '${_radius(state.radiusMetres)} ${te ? 'పరిధి' : 'radius'} · ${state.shops.length} ${te ? 'ఫలితాలు' : 'results'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SegmentedButton<MapDisplayMode>(
                  key: const Key('viewToggle'),
                  segments: [
                    ButtonSegment(value: MapDisplayMode.map, icon: const Icon(Icons.map_outlined), label: Text(te ? 'మ్యాప్' : 'Map')),
                    ButtonSegment(value: MapDisplayMode.list, icon: const Icon(Icons.list), label: Text(te ? 'జాబితా' : 'List')),
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
                      label: Text(radius == 7500 ? '${te ? 'కస్టమ్' : 'Custom'} (${_radius(radius)})' : _radius(radius)),
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
                    ? _MockMap(state: state, te: te)
                    : _ShopList(shops: state.shops, te: te),
          ),
          if (state.message != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                title: Text(state.message!),
                trailing: TextButton(onPressed: controller.refresh, child: Text(te ? 'మళ్లీ ప్రయత్నించండి' : 'Retry')),
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

class _MockMap extends ConsumerWidget {
  const _MockMap({required this.state, required this.te});
  final LocationState state;
  final bool te;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(locationControllerProvider.notifier);
    NearbyShop? selected;
    for (final shop in state.shops) {
      if (shop.id == state.selectedShopId) {
        selected = shop;
        break;
      }
    }
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        Semantics(
          label: te ? 'మ్యాప్ ప్రివ్యూ' : 'Mock map canvas',
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
                  Positioned(left: width * .42, top: 130.0, child: _Marker(icon: Icons.person_pin_circle, label: te ? 'మీరు' : 'You')),
                  for (var i = 0; i < state.shops.length; i++)
                    Positioned(
                      left: 40.0 + ((i * 95) % 260).toDouble(),
                      top: 220.0 + ((i % 2) * 90).toDouble(),
                      child: GestureDetector(
                        onTap: () => controller.selectShop(state.shops[i].id),
                        child: _Marker(icon: Icons.store, label: state.shops[i].name),
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
            heroTag: 'recenter',
            tooltip: te ? 'నా లొకేషన్‌కు తీసుకెళ్ళు' : 'Recenter',
            onPressed: () => controller.moveMap(state.defaultLocation?.point ?? const GeoPoint(17.4156, 78.4347)),
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
              label: Text(te ? 'ఈ ప్రాంతంలో వెతకండి' : 'Search this area'),
            ),
          ),
        ),
        Positioned(
          left: 24,
          bottom: selected == null ? 24.0 : 150.0,
          child: OutlinedButton.icon(
            onPressed: controller.saveSelectedArea,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(te ? 'ఈ ప్రాంతాన్ని సేవ్ చేయండి' : 'Save this area'),
          ),
        ),
        if (selected != null)
          Positioned(left: 16, right: 16, bottom: 12, child: _ShopCard(shop: selected, te: te)),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Tooltip(message: label, child: Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary));
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.colors);
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.primary.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.shortestSide * .3, paint);
    final road = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 4;
    for (double y = 70; y < size.height; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 35), road);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}

class _ShopList extends StatelessWidget {
  const _ShopList({required this.shops, required this.te});
  final List<NearbyShop> shops;
  final bool te;

  @override
  Widget build(BuildContext context) => shops.isEmpty
      ? _Empty(te: te)
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: shops.length,
          itemBuilder: (_, index) => _ShopCard(shop: shops[index], te: te),
        );
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop, required this.te});
  final NearbyShop shop;
  final bool te;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = shop.distanceMetres < 1000
        ? '${shop.distanceMetres.round()} m'
        : '${(shop.distanceMetres / 1000).toStringAsFixed(1)} km';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.storefront)),
              title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${shop.category} · $distance'),
              trailing: Chip(
                avatar: Icon(shop.verified ? Icons.verified : Icons.info_outline, size: 16),
                label: Text('${shop.trustScore}'),
              ),
            ),
            Wrap(spacing: 6, children: [
              Chip(label: Text(shop.isOpen ? (te ? 'తెరిచి ఉంది' : 'Open') : (te ? 'మూసి ఉంది' : 'Closed'))),
              Chip(label: Text('${shop.productCount} ${te ? 'వస్తువులు' : 'products'}')),
              Chip(label: Text('${shop.watchlistMatches} ${te ? 'మ్యాచ్‌లు' : 'matches'}')),
              Chip(label: Text('${shop.activeOffers} ${te ? 'ఆఫర్లు' : 'offers'}')),
            ]),
            Wrap(children: [
              TextButton(onPressed: () => context.push('/shop/${shop.id}'), child: Text(te ? 'దుకాణం చూడండి' : 'View shop')),
              TextButton(
                onPressed: () => ref.read(locationControllerProvider.notifier).selectShop(shop.id),
                child: Text(te ? 'మ్యాప్‌లో చూడండి' : 'View on map'),
              ),
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'call', child: Text(te ? 'కాల్' : 'Call (placeholder)')),
                  PopupMenuItem(value: 'navigate', child: Text(te ? 'దారి చూపించు' : 'Navigate (placeholder)')),
                  PopupMenuItem(value: 'follow', child: Text(te ? 'దుకాణాన్ని ఫాలో అవ్వండి' : 'Follow shop')),
                  PopupMenuItem(value: 'report', child: Text(te ? 'దుకాణాన్ని రిపోర్ట్ చేయండి' : 'Report shop')),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 64),
            Text(te ? 'దగ్గరలో దుకాణాలు లేవు' : 'No nearby shops'),
            Text(te ? 'పరిధిని పెంచండి లేదా వేరే లొకేషన్ ఎంచుకోండి.' : 'Try a larger radius or choose another location.'),
            FilledButton(onPressed: () => context.push('/location'), child: Text(te ? 'లొకేషన్ ఎంచుకోండి' : 'Choose location')),
          ],
        ),
      );
}
