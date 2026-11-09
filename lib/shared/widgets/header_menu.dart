import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/sign_out.dart';
import '../../core/flags/askodox_release_phase.dart';
import '../../core/providers/backend_providers.dart';
import '../../features/guide/in_app_guide.dart';
import '../../features/home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../../features/profile/presentation/profile_screen.dart' show askodoxProfileViewProvider;

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

/// Only the places people open most often; everything else (roles, KYC,
/// plans, Travel Radio, studio, memory, privacy, settings) lives in the
/// Profile grid -- the last entry opens it.
const askodoxHeaderMenuEntries = <AskodoxMenuEntry>[
  AskodoxMenuEntry('business', '/business', Icons.storefront_outlined, 'My Business', 'నా వ్యాపారం'),
  AskodoxMenuEntry('listings', '/listings/mine', Icons.inventory_2_outlined, 'Listings & catalog', 'లిస్టింగ్‌లు & కేటలాగ్'),
  AskodoxMenuEntry('enquiries', '/orders/incoming', Icons.mark_email_unread_outlined, 'Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు'),
  AskodoxMenuEntry('orders', '/orders/mine', Icons.receipt_long_outlined, 'My requests & orders', 'నా అభ్యర్థనలు & ఆర్డర్లు'),
  AskodoxMenuEntry('saved', '/watchlist', Icons.bookmark_border_rounded, 'Saved & history', 'సేవ్ చేసినవి & చరిత్ర'),
  AskodoxMenuEntry('mobility', '/mobility', Icons.local_shipping_outlined, 'Rides, parcels & delivery', 'రైడ్స్, పార్సెల్స్ & డెలివరీ'),
  AskodoxMenuEntry('more', '/profile', Icons.person_outline_rounded, 'My profile', 'నా ప్రొఫైల్'),
];

/// Menu value that is not a route: the ONE secure sign-out flow.
const askodoxSignOutMenuValue = '__sign_out__';

/// Menu value that opens the Screen Guide (moved here from its own header
/// icon -- owner, 2026-11-04: a cleaner header).
const askodoxGuideMenuValue = '__screen_guide__';

/// Menu value that opens Settings (location, voice, notifications, memory,
/// privacy, AI Credits). Owner 2026-11-09: settings live in the Menu so the
/// Profile page stays clean.
const askodoxSettingsMenuValue = '__settings__';

/// Menu value that starts a clean conversation (the old one stays in History).
const askodoxNewChatMenuValue = '__new_chat__';

class AskodoxHeaderMenuButton extends ConsumerWidget {
  const AskodoxHeaderMenuButton({super.key, required this.te});
  final bool te;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        key: const Key('askodoxHeaderMenu'),
        tooltip: te ? 'మెనూ' : 'Menu',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.menu_rounded, color: Color(0xFF10204A)),
        onPressed: () async {
          final signedIn = ref.read(authSessionProvider).user != null;
          final route = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheet) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
                child: ListView(shrinkWrap: true, children: [
                  ListTile(
                    key: const ValueKey('askodoxMenu-guide'),
                    dense: true,
                    leading: const Icon(Icons.assistant_navigation),
                    title: Text(te ? 'స్క్రీన్ గైడ్ -- ఎక్కడ నొక్కాలో చూపిస్తాను' : 'Screen Guide -- where to tap'),
                    onTap: () => Navigator.pop(sheet, askodoxGuideMenuValue),
                  ),
                  ListTile(
                    key: const ValueKey('askodoxMenu-newchat'),
                    dense: true,
                    leading: const Icon(Icons.add_comment_outlined),
                    title: Text(te ? 'కొత్త చాట్' : 'New chat'),
                    onTap: () => Navigator.pop(sheet, askodoxNewChatMenuValue),
                  ),
                  ListTile(
                    key: const ValueKey('askodoxMenu-settings'),
                    dense: true,
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(te ? 'సెట్టింగ్స్ — లొకేషన్, వాయిస్, నోటిఫికేషన్స్, గోప్యత' : 'Settings — location, voice, notifications, privacy'),
                    onTap: () => Navigator.pop(sheet, askodoxSettingsMenuValue),
                  ),
                  // Phase 1 build: Phase 2 places (business, listings, rides...) are not offered.
                  for (final e in askodoxHeaderMenuEntries.where((e) => askodoxRouteShownNow(e.route)))
                    ListTile(
                      key: ValueKey('askodoxMenu-${e.key}'),
                      dense: true,
                      leading: Icon(e.icon),
                      title: Text(te ? e.te : e.en),
                      onTap: () => Navigator.pop(sheet, e.route),
                    ),
                  if (signedIn) ...[
                    const Divider(height: 8),
                    ListTile(
                      key: const ValueKey('askodoxMenu-signout'),
                      dense: true,
                      leading: const Icon(Icons.logout_rounded, color: Color(0xFFB42318)),
                      title: Text(te ? 'లాగ్ అవుట్' : 'Logout',
                          style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
                      onTap: () => Navigator.pop(sheet, askodoxSignOutMenuValue),
                    ),
                  ],
                ]),
              ),
            ),
          );
          if (route == null || !context.mounted) return;
          if (route == askodoxGuideMenuValue) {
            askodoxShowScreenGuide(context, te: te);
            return;
          }
          if (route == askodoxSignOutMenuValue) {
            if (await askodoxConfirmSignOut(context, te: te) && context.mounted) {
              await askodoxSignOut(ref, restartFrom: context);
            }
            return;
          }
          if (route == askodoxNewChatMenuValue) {
            askodoxStartNewChat(ref, context);
            return;
          }
          if (route == askodoxSettingsMenuValue || route == '/profile') {
            ref.read(askodoxProfileViewProvider.notifier).state = route == askodoxSettingsMenuValue ? 'settings' : 'me';
            context.go('/profile'); // a bottom-bar tab, not a page on top
          } else {
            context.push(route);
          }
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
        onPressed: () => askodoxShowScreenGuide(context, te: te),
      );
}

/// The Screen Guide sheet: walkthroughs inside ASKODOX + the consented
/// cross-app guide. Opened from the header Menu.
void askodoxShowScreenGuide(BuildContext context, {required bool te}) {
  showModalBottomSheet<void>(
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
  );
}

/// Starts a clean conversation in Main Chat right away (no app restart).
void askodoxStartNewChat(WidgetRef ref, BuildContext context) {
  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.newConversation();
  context.go('/');
}
