import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/guide/in_app_guide.dart';

/// Header Menu: ONE list of the places that already exist (no new screens,
/// no duplicate entry points -- each item opens the existing route).
class AskodoxMenuEntry {
  const AskodoxMenuEntry(this.key, this.route, this.icon, this.en, this.te);
  final String key;
  final String route;
  final IconData icon;
  final String en;
  final String te;
}

const askodoxHeaderMenuEntries = <AskodoxMenuEntry>[
  AskodoxMenuEntry('business', '/business', Icons.storefront_outlined, 'My Business', 'నా వ్యాపారం'),
  AskodoxMenuEntry('listings', '/listings/mine', Icons.inventory_2_outlined, 'Listings & catalog', 'లిస్టింగ్‌లు & కేటలాగ్'),
  AskodoxMenuEntry('enquiries', '/orders/incoming', Icons.mark_email_unread_outlined, 'Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు'),
  AskodoxMenuEntry('roles', '/profile/roles', Icons.badge_outlined, 'Business & roles', 'వ్యాపారం & పాత్రలు'),
  AskodoxMenuEntry('opportunities', '/opportunities', Icons.work_outline_rounded, 'Services & opportunities', 'సేవలు & అవకాశాలు'),
  AskodoxMenuEntry('mobility', '/mobility', Icons.local_shipping_outlined, 'Rides, parcels & delivery', 'రైడ్స్, పార్సెల్స్ & డెలివరీ'),
  AskodoxMenuEntry('studio_videos', '/videos/native', Icons.video_library_outlined, 'My Studio · My videos', 'నా స్టూడియో · నా వీడియోలు'),
  AskodoxMenuEntry('studio_creations', '/business/creations', Icons.auto_awesome_outlined, 'My Studio · My creations', 'నా స్టూడియో · నా క్రియేషన్స్'),
  AskodoxMenuEntry('orders', '/orders/mine', Icons.receipt_long_outlined, 'My requests & orders', 'నా అభ్యర్థనలు & ఆర్డర్లు'),
  AskodoxMenuEntry('saved', '/watchlist', Icons.bookmark_border_rounded, 'Saved & history', 'సేవ్ చేసినవి & చరిత్ర'),
  AskodoxMenuEntry('memory', '/profile/memory', Icons.psychology_outlined, 'Privacy · Memory & personalization', 'గోప్యత · మెమరీ & వ్యక్తిగతీకరణ'),
  AskodoxMenuEntry('privacy', '/privacy', Icons.privacy_tip_outlined, 'Privacy & data', 'గోప్యత & డేటా'),
];

class AskodoxHeaderMenuButton extends StatelessWidget {
  const AskodoxHeaderMenuButton({super.key, required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('askodoxHeaderMenu'),
        tooltip: te ? 'మెనూ' : 'Menu',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.menu_rounded, color: Color(0xFF10204A)),
        onPressed: () async {
          final route = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheet) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
                child: ListView(shrinkWrap: true, children: [
                  for (final e in askodoxHeaderMenuEntries)
                    ListTile(
                      key: ValueKey('askodoxMenu-${e.key}'),
                      dense: true,
                      leading: Icon(e.icon),
                      title: Text(te ? e.te : e.en),
                      onTap: () => Navigator.pop(sheet, e.route),
                    ),
                ]),
              ),
            ),
          );
          if (route != null && context.mounted) context.push(route);
        },
      );
}

/// Header Screen Guide: step-by-step walkthroughs inside ASKODOX first
/// (highlights the real controls, pauses on private screens), plus the
/// existing consented cross-app guide.
class AskodoxHeaderGuideButton extends StatelessWidget {
  const AskodoxHeaderGuideButton({super.key, required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('askodoxHeaderScreenGuide'),
        tooltip: te ? 'స్క్రీన్ గైడ్' : 'Screen Guide',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.assistant_navigation, color: Color(0xFF10204A)),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(te ? 'స్క్రీన్ గైడ్ -- ఏం చేయాలో చూపిస్తాను' : 'Screen Guide -- I will show you where to tap',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                        te
                            ? 'ప్రచురించడం, తొలగించడం, చెల్లించడం లేదా సున్నితమైన వివరాలు పంపే ముందు మీ నిర్ధారణ అడుగుతాను. OTP / కార్డ్ / ఆధార్ / PAN స్క్రీన్లలో గైడ్ ఆగుతుంది.'
                            : 'I ask before publishing, deleting, paying or sending sensitive details. The guide pauses on OTP, card, Aadhaar and PAN screens.',
                        style: const TextStyle(color: Color(0xFF5B6475), fontSize: 12.5)),
                  ),
                  AskodoxGuideList(te: te, onStarted: () => Navigator.of(sheet).pop()),
                  ListTile(
                    key: const Key('askodoxHeaderGuideOtherApps'),
                    leading: const Icon(Icons.phone_android_rounded),
                    title: Text(te ? 'ఇతర యాప్‌లలో సహాయం (అనుమతితో)' : 'Help in other apps (with permission)'),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      context.push('/companion/screen-guide');
                    },
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
