import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/explore_service.dart';
import '../../location/application/location_controller.dart';
import '../application/conversation_archive.dart';

final exploreServiceProvider = Provider<ExploreService>((ref) => const ExploreService());

class _ExploreFeedQuery {
  const _ExploreFeedQuery(this.location, this.latitude, this.longitude);
  final String location;
  final double? latitude;
  final double? longitude;

  @override
  bool operator ==(Object other) =>
      other is _ExploreFeedQuery &&
      other.location == location &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(location, latitude, longitude);
}

final _exploreFeedProvider =
    FutureProvider.autoDispose.family<List<ExploreItem>, _ExploreFeedQuery>(
  (ref, query) => ref.watch(exploreServiceProvider).feed(
        location: query.location,
        latitude: query.latitude,
        longitude: query.longitude,
      ),
);

/// Explore: real discovery that always continues in the SAME ASKODOX chat.
/// Selecting a tile or listing asks ASKODOX in Main Chat, which runs the
/// usual understanding → questions → multi-source results pipeline. It is
/// not a separate shopping experience.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  void _ask(BuildContext context, WidgetRef ref, String prompt) {
    ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(prompt);
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final location = ref.watch(locationControllerProvider);
    final place = location.displayLocation?.trim() ?? '';
    final near = place.isEmpty ? '' : (te ? ' $place దగ్గర' : ' near $place');
    final point = location.defaultLocation?.point;
    final feed = ref.watch(_exploreFeedProvider(
        _ExploreFeedQuery(place, point?.latitude, point?.longitude)));

    final tiles = <(IconData, String, String)>[
      (Icons.shopping_bag_outlined, t('Products', 'ఉత్పత్తులు'), t('Show me popular products$near', '$near ప్రసిద్ధ ఉత్పత్తులు చూపించు')),
      (Icons.home_repair_service_outlined, t('Services', 'సర్వీసులు'), t('Show me trusted local services$near', '$near నమ్మకమైన స్థానిక సర్వీసులు చూపించు')),
      (Icons.work_outline_rounded, t('Jobs', 'ఉద్యోగాలు'), t('Show me local job openings$near', '$near స్థానిక ఉద్యోగాలు చూపించు')),
      (Icons.local_shipping_outlined, t('Rides & delivery', 'రైడ్స్ & డెలివరీ'), t('I need a ride or delivery$near', '$near రైడ్ లేదా డెలివరీ కావాలి')),
      (Icons.local_offer_outlined, t('Deals & offers', 'డీల్స్ & ఆఫర్లు'), t('Show me today\'s deals and offers$near', '$near నేటి డీల్స్ మరియు ఆఫర్లు చూపించు')),
      (Icons.recycling_rounded, t('Used / second-hand', 'వాడినవి / సెకండ్ హ్యాండ్'), t('Show me used and second-hand items$near', '$near వాడిన వస్తువులు చూపించు')),
      (Icons.person_outline_rounded, t('Individual sellers', 'వ్యక్తిగత విక్రేతలు'), t('Show me one-time sellers$near', '$near వ్యక్తిగత విక్రేతలను చూపించు')),
      (Icons.inventory_2_outlined, t('Surplus / open-box', 'సర్ప్లస్ / ఓపెన్-బాక్స్'), t('Show me surplus, clearance and open-box stock$near', '$near క్లియరెన్స్ / ఓపెన్-బాక్స్ స్టాక్ చూపించు')),
      (Icons.storefront_outlined, t('Local opportunities', 'స్థానిక అవకాశాలు'), t('What local opportunities are there$near?', '$near ఏ స్థానిక అవకాశాలు ఉన్నాయి?')),
      (Icons.play_circle_outline_rounded, t('Videos & reviews', 'వీడియోలు & రివ్యూలు'), t('Show me product reviews and comparison videos', 'ఉత్పత్తి రివ్యూలు మరియు పోలిక వీడియోలు చూపించు')),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(t('Explore', 'ఎక్స్‌ప్లోర్'),
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            t('Discover anything -- ASKODOX finds it for you in chat.',
                'ఏదైనా కనుగొనండి -- ASKODOX చాట్‌లో మీకు వెతికి చూపిస్తుంది.'),
            style: const TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icon, label, prompt) in tiles)
                ActionChip(
                  key: ValueKey('exploreTile-$label'),
                  avatar: Icon(icon, size: 18, color: const Color(0xFF1769FF)),
                  label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () => _ask(context, ref, prompt),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(t('On ASKODOX now', 'ఇప్పుడు ASKODOXలో'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
          const SizedBox(height: 10),
          feed.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => _empty(t),
            data: (items) => items.isEmpty
                ? _empty(t)
                : Column(children: [
                    for (final item in items)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE5EAF2)),
                        ),
                        child: ListTile(
                          key: ValueKey('exploreItem-${item.id}'),
                          leading: Icon(_segmentIcon(item.segment), color: const Color(0xFF1769FF)),
                          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            [_segmentLabel(item.segment, t), if (item.subtitle.isNotEmpty) item.subtitle]
                                .join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF713BFF)),
                          onTap: () => _ask(context, ref, item.prompt),
                        ),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _empty(String Function(String, String) t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          t('Nothing listed nearby yet -- pick a category above and ASKODOX will search local, online and video sources.',
              'ఇంకా దగ్గరలో ఏమీ లిస్ట్ కాలేదు -- పై వర్గాన్ని ఎంచుకోండి; ASKODOX స్థానిక, ఆన్‌లైన్ మరియు వీడియో మూలాల్లో వెతుకుతుంది.'),
          style: const TextStyle(color: Color(0xFF667085)),
        ),
      );

  static IconData _segmentIcon(String segment) => switch (segment) {
        'used' => Icons.recycling_rounded,
        'surplus' => Icons.inventory_2_outlined,
        'deals' => Icons.local_offer_outlined,
        'individual' => Icons.person_outline_rounded,
        'nearby_external' => Icons.near_me_rounded,
        _ => Icons.verified_rounded,
      };

  static String _segmentLabel(String segment, String Function(String, String) t) => switch (segment) {
        'used' => t('Used', 'వాడినది'),
        'surplus' => t('Open-box / clearance', 'ఓపెన్-బాక్స్ / క్లియరెన్స్'),
        'deals' => t('Deal', 'డీల్'),
        'individual' => t('Individual seller', 'వ్యక్తిగత విక్రేత'),
        'nearby_external' => t('Nearby shop', 'దగ్గరలోని షాప్'),
        _ => t('ASKODOX seller', 'ASKODOX విక్రేత'),
      };
}
