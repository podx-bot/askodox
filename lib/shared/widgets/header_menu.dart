import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/sign_out.dart';
import '../../core/flags/askodox_release_phase.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/backend_providers.dart';
import '../../features/business/presentation/biz_hub.dart' show askodoxBizHubProvider;
import '../../features/home/domain/conversation_language.dart';
import '../../features/home/domain/shopping_mode.dart';
import '../../features/money_home/money_home_store.dart';
import '../../features/guide/in_app_guide.dart';
import '../../features/home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../../features/profile/data/user_profile_repository.dart' show askodoxUserProfileProvider;
import '../../features/profile/presentation/profile_editor.dart' show askodoxOpenProfileEditor;
import '../../features/profile/presentation/profile_screen.dart' show askodoxProfileViewProvider;
import 'chat_pins.dart';

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

/// Menu value that opens the language choice (also on the header chip).
const askodoxLanguageMenuValue = '__language__';

/// Every reply language the header chip offers ('auto' = follow the conversation).
const askodoxLanguageChoices = <(String, String)>[
  ('auto', 'Automatic'),
  ('en', 'English'), ('te', 'తెలుగు'), ('hi', 'हिन्दी'),
  ('ta', 'தமிழ்'), ('kn', 'ಕನ್ನಡ'), ('ml', 'മലയാളം'),
  ('mr', 'मराठी'), ('bn', 'বাংলা'), ('gu', 'ગુજરાતી'),
  ('pa', 'ਪੰਜਾਬੀ'), ('or', 'ଓଡ଼ିଆ'), ('ur', 'اردو'), ('as', 'অসমীয়া'),
];

/// "Automatic" releases the explicit lock (conversation detection drives replies); a concrete choice locks the screens
/// and the conversation to the same language.
void askodoxApplyLanguage(WidgetRef ref, String code) {
  if (code == 'auto') {
    ref.read(appSettingsProvider.notifier).useSystemLocale();
  } else {
    ref.read(appSettingsProvider.notifier).setLocale(Locale(code));
  }
  ref.read(askodoxConversationLanguageProvider.notifier).lockTo(code);
}

/// The company's own pages (askodox.com), the same in both sides.
const askodoxCompanyLinks = <(String, IconData, String, String, String)>[
  ('support', Icons.support_agent_rounded, 'Customer care', 'కస్టమర్ కేర్', 'https://askodox.com/support/'),
  ('contact', Icons.mail_outline_rounded, 'Contact us', 'మమ్మల్ని సంప్రదించండి', 'https://askodox.com/contact/'),
  ('about', Icons.info_outline_rounded, 'About us', 'మా గురించి', 'https://askodox.com/about/'),
  ('terms', Icons.gavel_rounded, 'Terms & conditions', 'నిబంధనలు', 'https://askodox.com/terms/'),
  ('privacy', Icons.privacy_tip_outlined, 'Privacy', 'ప్రైవసీ', 'https://askodox.com/privacy/'),
  ('report', Icons.flag_outlined, 'Report a problem', 'సమస్య చెప్పండి', 'https://askodox.com/report-a-problem/'),
];

const _buyerColor = Color(0xFF6C4DFF);
const _sellerColor = Color(0xFF0B7A4B);

/// ☰ (owner 2026-11-22): a box that drops from the TOP, in the side's colour (purple = Buyer, green = Seller).
/// - Buyer: the person's name, phone and address (✏ edits them);
/// - Seller: the shop's name and address (✏ edits the shop), plus "My shops";
/// - then the person's own things (history, language, location, notifications, AI Credits, settings, feedback, idea),
///   the company's pages (customer care, contact, about, terms, privacy) and Sign in / Logout.
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
          final route = await showGeneralDialog<String>(
            context: context,
            barrierDismissible: true,
            barrierLabel: te ? 'మెనూ మూసేయండి' : 'Close menu',
            barrierColor: const Color(0x66000000),
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (dialog, _, __) => AskodoxMenuBox(te: te),
            transitionBuilder: (dialog, animation, _, child) => SlideTransition(
              position: Tween(begin: const Offset(0, -1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
          if (route == null || !context.mounted) return;
          await askodoxRunMenuChoice(context, ref, route, te: te);
        },
      );
}

/// What a menu choice does (shared by the box and its tests).
Future<void> askodoxRunMenuChoice(BuildContext context, WidgetRef ref, String route, {required bool te}) async {
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
  if (route == askodoxLanguageMenuValue) {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .7),
          child: ListView(key: const Key('askodoxMenuLanguageSheet'), shrinkWrap: true, children: [
            for (final (code, name) in askodoxLanguageChoices)
              ListTile(
                key: ValueKey('askodoxMenuLanguage-$code'),
                title: Text(code == 'auto' && te ? 'ఆటోమేటిక్' : name),
                trailing: ref.read(askodoxReplyLanguageProvider) == code ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheet, code),
              ),
          ]),
        ),
      ),
    );
    if (code != null) askodoxApplyLanguage(ref, code);
    return;
  }
  if (route.startsWith('https://')) {
    await launchUrl(Uri.parse(route), mode: LaunchMode.externalApplication);
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
}

/// The menu box itself.
class AskodoxMenuBox extends ConsumerWidget {
  const AskodoxMenuBox({super.key, required this.te});
  final bool te;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(askodoxSellerModeProvider);
    final signedIn = ref.watch(authSessionProvider).user != null;
    final color = seller ? _sellerColor : _buyerColor;
    void pick(String value) => Navigator.of(context).pop(value);

    final mine = <(String, IconData, String, String)>[
      ('askodoxMenu-saved', Icons.history_rounded, te ? 'చరిత్ర' : 'History', '/watchlist'),
      ('askodoxMenu-newchat', Icons.add_comment_outlined, te ? 'కొత్త చాట్' : 'New chat', askodoxNewChatMenuValue),
      ('askodoxMenu-language', Icons.language_rounded, te ? 'భాష' : 'Language', askodoxLanguageMenuValue),
      ('askodoxMenu-location', Icons.location_on_outlined, te ? 'లొకేషన్' : 'Location', '/location'),
      ('askodoxMenu-notifications', Icons.notifications_none_rounded, te ? 'నోటిఫికేషన్లు' : 'Notifications',
          '/settings/notifications'),
      ('askodoxMenu-credits', Icons.bolt_rounded, te ? 'AI క్రెడిట్స్' : 'AI Credits', '/me/ai-credits'),
      ('askodoxMenu-settings', Icons.settings_outlined, te ? 'సెట్టింగ్స్' : 'Settings', askodoxSettingsMenuValue),
      ('askodoxMenu-feedback', Icons.rate_review_outlined, te ? 'ఫీడ్‌బ్యాక్' : 'Feedback', '/beta-feedback'),
      ('askodoxMenu-ideas', Icons.lightbulb_outline, te ? 'మీ ఐడియా' : 'Your idea', '/me/ideas'),
      if (askodoxGuidesOn)
        ('askodoxMenu-guide', Icons.assistant_navigation, te ? 'స్క్రీన్ గైడ్' : 'Screen Guide', askodoxGuideMenuValue),
      // Phase 2 places, each on its own side.
      for (final e in askodoxHeaderMenuEntries)
        if (e.key != 'saved' && e.key != 'more' && askodoxRouteShownNow(e.route) &&
            (seller ? const {'business', 'listings', 'enquiries'} : const {'orders', 'mobility'}).contains(e.key))
          ('askodoxMenu-${e.key}', e.icon, te ? e.te : e.en, e.route),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        key: const Key('askodoxMenuBox'),
        color: Colors.white,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          bottom: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(14, 8, 14, 14), children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Text(seller ? (te ? 'అమ్ము' : 'Sell') : (te ? 'కొను' : 'Buy'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('askodoxMenuClose'),
                  tooltip: te ? 'మూసేయండి' : 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              if (seller) _ShopHeader(te: te, color: color, pick: pick) else _PersonHeader(te: te, color: color, pick: pick),
              const SizedBox(height: 12),
              _grid(mine, color, pick),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
                child: Text('ASKODOX', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
              ),
              _grid([
                for (final (id, icon, en, tel, url) in askodoxCompanyLinks) ('askodoxMenu-$id', icon, te ? tel : en, url),
              ], const Color(0xFF374151), pick),
              const SizedBox(height: 12),
              if (signedIn)
                OutlinedButton.icon(
                  key: const ValueKey('askodoxMenu-signout'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318), minimumSize: const Size.fromHeight(46)),
                  onPressed: () => pick(askodoxSignOutMenuValue),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(te ? 'లాగ్ అవుట్' : 'Logout'),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('askodoxMenu-signin'),
                  style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(46)),
                  onPressed: () => pick('/onboarding?signin=1'),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(te ? 'సైన్ ఇన్' : 'Sign in'),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<(String, IconData, String, String)> items, Color color, void Function(String) pick) =>
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (key, icon, label, value) in items)
            SizedBox(
              width: w,
              child: Material(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: ValueKey(key),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => pick(value),
                  // Owner 2026-11-19: any menu page can be pinned above the chat (press and hold).
                  onLongPress: value.startsWith('/')
                      ? () => askodoxOfferChatPin(context, AskodoxChatPin(id: 'menu:$value', route: value, en: label, te: label))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF16203F))),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      });
}

/// Buyer side: the person's own details (✏ = the profile editor; signed out = Sign in).
class _PersonHeader extends ConsumerWidget {
  const _PersonHeader({required this.te, required this.color, required this.pick});
  final bool te;
  final Color color;
  final void Function(String) pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(askodoxUserProfileProvider).valueOrNull;
    final user = ref.watch(authSessionProvider).user;
    final name = [profile?.name, profile?.lastName].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    final shownName = name.isNotEmpty ? name : (user?.displayName ?? (te ? 'అతిథి' : 'Guest'));
    final phone = (profile?.mobile ?? '').trim();
    final address = (profile?.address ?? '').trim();
    return _HeaderCard(
      key: const ValueKey('askodoxMenu-more'),
      color: color,
      icon: Icons.person_rounded,
      title: shownName,
      lines: [
        if (phone.isNotEmpty) phone,
        if (address.isNotEmpty) address,
        if (user == null) te ? 'సైన్ ఇన్ చేస్తే మీ వివరాలు ఇక్కడ' : 'Sign in to see your details here',
      ],
      onTap: () => pick(user == null ? '/onboarding?signin=1' : askodoxProfileDetailsMenuValue),
      editLabel: te ? 'మార్చు' : 'Edit',
    );
  }
}

/// Seller side: the shop in view (✏ = its details) + "My shops".
class _ShopHeader extends ConsumerWidget {
  const _ShopHeader({required this.te, required this.color, required this.pick});
  final bool te;
  final Color color;
  final void Function(String) pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(askodoxMyShopsProvider).valueOrNull ?? const [];
    final shop = askodoxPickShop(shops, ref.watch(askodoxMoneyShopProvider));
    final id = shop == null ? null : '${shop['id']}';
    final business = id == null ? null : ref.watch(askodoxBizHubProvider(id)).valueOrNull?.$1;
    final address = '${business?['address'] ?? ''}'.trim();
    final owner = shop != null && '${shop['role']}' == 'owner';
    return Column(children: [
      _HeaderCard(
        key: const ValueKey('askodoxMenu-shop'),
        color: color,
        icon: Icons.storefront_rounded,
        title: shop == null ? (te ? 'ఇంకా షాప్ లేదు' : 'No shop yet') : '${shop['name'] ?? ''}',
        lines: [
          if (address.isNotEmpty) address,
          if (shop != null && !owner) te ? 'మీరు ఇక్కడ సిబ్బంది' : 'You are staff here',
          if (shop == null) te ? 'Money లో షాప్ మొదలుపెట్టండి' : 'Start your shop in Money',
        ],
        onTap: () => pick(shop == null ? '/money-home' : (owner ? '/me/business/$id/profile' : '/money-home')),
        editLabel: shop == null ? (te ? 'మొదలు' : 'Start') : (owner ? (te ? 'మార్చు' : 'Edit') : (te ? 'తెరువు' : 'Open')),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('askodoxMenu-mybusiness'),
          onPressed: () => pick('/me/business'),
          icon: Icon(Icons.store_mall_directory_outlined, color: color),
          label: Text(te ? 'నా షాప్‌లు / కొత్త షాప్' : 'My shops / add a shop', style: TextStyle(color: color)),
        ),
      ),
    ]);
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
    required this.editLabel,
  });
  final Color color;
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onTap;
  final String editLabel;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleAvatar(radius: 24, backgroundColor: color, child: Icon(icon, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF16203F))),
                  for (final l in lines)
                    Text(l,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF4B5563))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_rounded, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(editLabel, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
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
