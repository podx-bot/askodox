import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/sign_out.dart';
import '../../core/flags/askodox_release_phase.dart';
import '../../core/providers/backend_providers.dart';
import '../../features/guide/in_app_guide.dart';
import '../../features/home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../../features/profile/data/user_profile_repository.dart' show askodoxUserProfileProvider;
import '../../features/profile/presentation/profile_editor.dart' show askodoxOpenProfileEditor;
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
  AskodoxMenuEntry('more', askodoxProfileDetailsMenuValue, Icons.person_outline_rounded, 'My details (personal & business)',
      'నా వివరాలు (వ్యక్తిగత & బిజినెస్)'),
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

/// Owner 2026-11-18: personal + business details open from the Menu (the bottom tab became "Tools").
const askodoxProfileDetailsMenuValue = '__profile_details__';

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
                // Owner 2026-11-18: the menu as coloured buttons in 3 groups (same look as the business pages).
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), children: [
                  FilledButton.icon(
                    key: const ValueKey('askodoxMenu-newchat'),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5B2A9E),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => Navigator.pop(sheet, askodoxNewChatMenuValue),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(te ? 'కొత్త చాట్ — ఏదైనా అడగండి' : 'New chat — ask anything'),
                  ),
                  for (final (title, entries) in [
                    (te ? 'నా బిజినెస్' : 'My business', [
                      for (final e in askodoxHeaderMenuEntries
                          .where((e) => askodoxRouteShownNow(e.route) && const {'business', 'listings', 'enquiries'}.contains(e.key)))
                        (ValueKey('askodoxMenu-${e.key}'), e.icon, te ? e.te : e.en, e.route, const Color(0xFFFFF1E3), const Color(0xFFB45309)),
                      (const ValueKey('askodoxMenu-mybusiness'), Icons.storefront_outlined, te ? 'నా షాప్ / బిజినెస్' : 'My shop / business',
                          '/me/business', const Color(0xFFFFF1E3), const Color(0xFFB45309)),
                    ]),
                    (te ? 'నేను కొనేవి' : 'What I buy', [
                      for (final e in askodoxHeaderMenuEntries
                          .where((e) => askodoxRouteShownNow(e.route) && const {'orders', 'saved', 'mobility'}.contains(e.key)))
                        (ValueKey('askodoxMenu-${e.key}'), e.icon, te ? e.te : e.en, e.route, const Color(0xFFE8EEFB), const Color(0xFF1E3FA0)),
                    ]),
                    (te ? 'నా ఖాతా' : 'My account', [
                      for (final e in askodoxHeaderMenuEntries.where((e) => e.key == 'more'))
                        (ValueKey('askodoxMenu-${e.key}'), e.icon, te ? e.te : e.en, e.route, const Color(0xFFF1F2F4), const Color(0xFF374151)),
                      (const ValueKey('askodoxMenu-settings'), Icons.settings_outlined, te ? 'సెట్టింగ్స్' : 'Settings',
                          askodoxSettingsMenuValue, const Color(0xFFF1F2F4), const Color(0xFF374151)),
                      (const ValueKey('askodoxMenu-ideas'), Icons.lightbulb_outline, te ? 'మీ ఐడియా చెప్పండి' : 'Tell us your idea',
                          '/me/ideas', const Color(0xFFFFF7E0), const Color(0xFF8A6100)),
                      if (askodoxGuidesOn)
                        (const ValueKey('askodoxMenu-guide'), Icons.assistant_navigation, te ? 'స్క్రీన్ గైడ్' : 'Screen Guide',
                            askodoxGuideMenuValue, const Color(0xFFE3F4F6), const Color(0xFF0E6A84)),
                      if (signedIn)
                        (const ValueKey('askodoxMenu-signout'), Icons.logout_rounded, te ? 'లాగ్ అవుట్' : 'Logout',
                            askodoxSignOutMenuValue, const Color(0xFFFDECEC), const Color(0xFFB42318)),
                    ]),
                  ])
                    if (entries.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
                        child: Text(title,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563))),
                      ),
                      LayoutBuilder(builder: (context, box) {
                        final w = (box.maxWidth - 8) / 2;
                        return Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final (key, icon, label, value, bg, fg) in entries)
                            SizedBox(
                              width: w,
                              child: Material(
                                color: bg,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: key,
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.pop(sheet, value),
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: 56),
                                    padding: const EdgeInsets.all(10),
                                    child: Row(children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                                        child: Icon(icon, color: fg, size: 18),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(label,
                                            maxLines: 2,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF16203F))),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                        ]);
                      }),
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
          if (route == askodoxProfileDetailsMenuValue) {
            final profile = ref.read(askodoxUserProfileProvider).valueOrNull;
            if (profile == null) {
              context.push('/onboarding?signin=1');
            } else {
              await askodoxOpenProfileEditor(context, ref, profile, telugu: te);
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
