import 'package:flutter/material.dart';

import '../../../shared/widgets/navigator_section.dart';
import '../../home/application/voice_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../core/auth/sign_out.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../home/application/conversation_archive.dart';
import '../../home/application/saved_options.dart';
import '../../home/domain/active_role.dart';
import '../../location/application/location_controller.dart';
import '../../staff/askodox_staff_access.dart';
import '../data/user_profile_repository.dart';
import 'profile_editor.dart';
import 'profile_header.dart';
import '../../../shared/widgets/askodox_mascot.dart';
import '../../settings/developer_diagnostics_screen.dart';
import '../../guide/in_app_guide.dart';
import '../../home/presentation/question_mic.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _checking = false;
  bool _installing = false;
  double? _progress;
  AskodoxUpdateInfo? _update;
  String? _message;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  String _voiceLabel(VoicePreference preference, bool te) =>
      switch (preference) {
        VoicePreference.automatic => te ? 'ఆటోమేటిక్' : 'Automatic',
        VoicePreference.male => te ? 'పురుష వాయిస్' : 'Male voice',
        VoicePreference.female => te ? 'మహిళా వాయిస్' : 'Female voice',
      };

  Future<void> _pickVoicePreference(bool te) async {
    final current = ref.read(appSettingsProvider).voicePreference;
    final selected = await showModalBottomSheet<VoicePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(te ? 'వాయిస్ ప్రాధాన్యత' : 'Voice preference'),
              subtitle: Text(te
                  ? 'ASKODOX మాట్లాడే వాయిస్‌ను ఎంచుకోండి. Automatic మీ డివైస్‌కు సరిపోయే వాయిస్‌ను ఉపయోగిస్తుంది.'
                  : 'Choose the voice ASKODOX uses. Automatic picks a compatible device voice.'),
            ),
            RadioGroup<VoicePreference>(
              groupValue: current,
              onChanged: (value) => Navigator.pop(context, value),
              child: Column(
                children: [
                  for (final preference in VoicePreference.values)
                    RadioListTile<VoicePreference>(value: preference, title: Text(_voiceLabel(preference, te))),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    ref.read(appSettingsProvider.notifier).setVoicePreference(selected);
  }

  Future<void> _checkUpdate() async {
    if (_checking || _installing) return;
    if (!AskodoxUpdateService.enabled) {
      setState(() => _message = _te
          ? 'Signed live buildలో update feature పనిచేస్తుంది.'
          : 'Updates work in signed live builds.');
      return;
    }
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      const service = AskodoxUpdateService();
      final result = await service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = result.update;
        _message = result.update == null
            ? (_te
                ? 'మీ ASKODOX ఇప్పటికే తాజా వెర్షన్‌లో ఉంది.'
                : 'ASKODOX is already up to date.')
            : (_te
                ? 'కొత్త ASKODOX update సిద్ధంగా ఉంది.'
                : 'A new ASKODOX update is ready.');
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Update check failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final update = _update;
    if (update == null || _installing) return;
    setState(() {
      _installing = true;
      _progress = 0;
    });
    try {
      const service = AskodoxUpdateService();
      await service.downloadAndInstall(update, onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      });
      if (mounted) {
        setState(() => _message = _te
            ? 'Android install promptను confirm చేయండి.'
            : 'Confirm the Android install prompt.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  // ------------------------------------------------------------- redesign (2026-10-25)
  // Profile = a talk / search bar (type or SPEAK: "notifications", "my shop", "నా వీడియోలు"), then three
  // tabs -- నేను (me) / వ్యాపారం (business) / సెట్టింగ్స్ -- instead of one long list. Recently opened
  // rows come first. A running walkthrough switches to the tab that holds its next button.
  String _tab = 'me';
  final _search = TextEditingController();
  String _query = '';
  List<String> _recent = const [];
  static const _recentKey = 'askodox.profile.recent.v1';

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  void _remember(String id) {
    final next = [id, ..._recent.where((r) => r != id)].take(4).toList();
    setState(() => _recent = next);
    SharedPreferences.getInstance().then((p) => p.setStringList(_recentKey, next)).catchError((_) => true);
  }

  /// Search words: both languages + extra words people say.
  static bool _matches(_ProfileEntry e, String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    if (words.isEmpty) return false;
    final hay = '${e.en} ${e.te} ${e.words.join(' ')}'.toLowerCase();
    return words.every(hay.contains) || words.any((w) => w.length > 3 && hay.contains(w));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final voicePreference = ref.watch(appSettingsProvider).voicePreference;
    final locationState = ref.watch(locationControllerProvider);
    final selectedLocation = locationState.defaultLocation;
    final locationLabel = selectedLocation == null
        ? (te ? 'లొకేషన్ ఎంచుకోండి' : 'Choose location')
        : selectedLocation.address.trim().isNotEmpty
            ? selectedLocation.address
            : selectedLocation.name;
    String t(String en, String telugu) => te ? telugu : en;
    final early = ref.watch(askodoxEarlyAccessProvider).valueOrNull ?? EarlyAccessInfo.inactive;
    final signedIn = ref.watch(authSessionProvider).user != null;
    final owned = ref.watch(askodoxRoleProvider).owned;
    final sells = owned.contains(AskodoxUserRole.seller) || owned.contains(AskodoxUserRole.serviceProvider);

    // Every destination once: its tab, words people use for it, and where it goes.
    final entries = <_ProfileEntry>[];
    AskodoxNavRow row(String id, String tab, IconData icon, String en, String telugu, String subEn, String subTe,
        VoidCallback go, {String? guide, String? subtitle, List<String> words = const [], Key? key}) {
      final entry = _ProfileEntry(id, tab, icon, en, telugu, words, go);
      entries.add(entry);
      return AskodoxNavRow(
          key: key ?? ValueKey(id),
          guide: guide,
          icon: icon,
          title: t(en, telugu),
          subtitle: subtitle ?? t(subEn, subTe),
          onTap: () {
            _remember(id);
            go();
          });
    }

    // ---- నేను (me): buying, shop scan, advances, rides, tools, roles
    final meSections = <Widget>[
      if (!signedIn)
        AskodoxNavSection(title: t('Account', 'ఖాతా'), icon: Icons.person_outline_rounded, children: [
          AskodoxNavRow(
              key: const Key('askodoxProfileSignIn'),
              icon: Icons.phone_iphone_rounded,
              title: t('Sign in with your phone', 'మీ ఫోన్‌తో సైన్ ఇన్ చేయండి'),
              subtitle: t('Needed only to send requests and see their status.',
                  'అభ్యర్థనలు పంపడానికి, వాటి స్థితి చూడడానికి మాత్రమే అవసరం.'),
              onTap: () => context.push('/onboarding?signin=1')),
        ]),
      if (sells)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.tonalIcon(
            key: const Key('askodoxProfileGoBusiness'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => setState(() => _tab = 'business'),
            icon: const Icon(Icons.storefront_rounded),
            label: Text(t('My Business — bills, items, enquiries', 'నా వ్యాపారం — బిల్లులు, సరుకులు, ఎంక్వైరీలు'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-shopping'),
          grid: true,
          title: t('Shopping & daily use', 'కొనుగోళ్లు & రోజువారీ'),
          icon: Icons.shopping_bag_outlined,
          children: [
            row('profile-shop-scan', 'me', Icons.qr_code_scanner, 'Scan & shop in a store', 'షాప్‌లో స్కాన్ చేసి కొనండి',
                'Scan items; show the exit code at the counter.', 'సరుకులు స్కాన్ చేసి కౌంటర్‌లో కోడ్ చూపించండి.',
                () => context.push('/shop-scan'), words: ['scan', 'supermarket', 'స్కాన్']),
            row('profile-shop-advances', 'me', Icons.savings_outlined, 'Shop advances', 'షాప్ అడ్వాన్సులు',
                'Approve what a shop recorded for you.', 'షాప్ నమోదు చేసినవి ఆమోదించండి.',
                () => context.push('/me/shop-advances'), words: ['advance', 'approve', 'money', 'డబ్బు', 'ఆమోదం']),
            row('profile-mobility', 'me', Icons.local_taxi_outlined, 'Rides, parcels & carpool', 'రైడ్స్, పార్సెల్స్ & కార్‌పూల్',
                'Book, track, or drive / deliver.', 'బుక్, ట్రాక్, లేదా డ్రైవ్ / డెలివర్.', () => context.push('/mobility'),
                guide: 'screen_mobility', words: ['ride', 'parcel', 'auto', 'taxi', 'రైడ్', 'పార్సెల్']),
            row('profile-smart-tools', 'me', Icons.handyman_outlined, 'Smart Tools', 'స్మార్ట్ టూల్స్',
                'Level, compass, calculators, photo inspection.', 'లెవెల్, దిక్సూచి, లెక్కలు, ఫోటో పరిశీలన.',
                () => context.push('/tools'), words: ['tools', 'calculator', 'compass', 'టూల్స్']),
            if (ref.watch(askodoxSavedOptionsProvider).isNotEmpty) KeyedSubtree(key: const Key('askodoxSavedOptionsTile'), child: ListTile(
                    leading: const Icon(Icons.bookmark_rounded),
                    title: Text('${t('Saved options', 'సేవ్ చేసినవి')} (${ref.watch(askodoxSavedOptionsProvider).length})'),
                    subtitle: Text(t('Options you saved from conversations.', 'సంభాషణల నుండి మీరు సేవ్ చేసినవి.')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => Consumer(builder: (context, ref, _) {
                            final saved = ref.watch(askodoxSavedOptionsProvider);
                            return SafeArea(
                              child: ListView(shrinkWrap: true, children: [
                                for (final m in saved)
                                  ListTile(
                                    title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    subtitle: Text([
                                      if (m.price != null) '₹${m.price!.toStringAsFixed(0)}',
                                      if (m.locationLabel?.trim().isNotEmpty == true) m.locationLabel!,
                                      if (m.sourceName?.trim().isNotEmpty == true) m.sourceName!,
                                    ].join(' · ')),
                                    onTap: () {
                                      final uri = Uri.tryParse(m.destinationUrl ?? '') ?? askodoxDirectionsUri(m);
                                      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                                    },
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      onPressed: () => ref.read(askodoxSavedOptionsProvider.notifier).toggle(m),
                                    ),
                                  ),
                              ]),
                            );
                          }),
                        ))),
          ]),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-roles'),
          mascot: AskodoxMascotRole.entro,
          grid: true,
          title: t('Roles & Opportunities', 'పాత్రలు & అవకాశాలు'),
          icon: Icons.badge_outlined,
          children: [
            if (!signedIn)
            (Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (context) {
                          // Held roles are edited here only; the conversation
                          // moves the ACTIVE role, highlighted below.
                          final roles = ref.watch(askodoxRoleProvider);
                          return Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final role in {
                                  ...askodoxProfileRoles,
                                  roles.active,
                                })
                                  FilterChip(
                                      key: ValueKey('profileRole-${role.name}'),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      labelStyle: const TextStyle(fontSize: 12.5),
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      selected: roles.owned.contains(role),
                                      side: role == roles.active
                                          ? const BorderSide(
                                              color: Color(0xFF1769FF), width: 2)
                                          : null,
                                      avatar: role == roles.active
                                          ? const Icon(Icons.bolt_rounded,
                                              size: 18, color: Color(0xFF1769FF))
                                          : null,
                                      label: Text(role == roles.active
                                          ? '${askodoxUserRoleLabel(role, telugu: _te)} · ${t('Active now', 'ఇప్పుడు యాక్టివ్')}'
                                          : askodoxUserRoleLabel(role, telugu: _te)),
                                      onSelected: (value) {
                                        ref.read(askodoxRoleProvider.notifier).toggleOwned(role, value);
                                        // Held roles are part of the one stored profile.
                                        if (ref.read(authSessionProvider).user != null) {
                                          final held = ref.read(askodoxRoleProvider).owned.map((r) => r.name).toList()
                                            ..sort();
                                          ref.read(askodoxUserProfileProvider.notifier).save({'roles': held});
                                        }
                                      }),
                              ]);
                        }),
                        const SizedBox(height: 4),
                        // The ACTIVE role changes only when the person picks it
                        // here (or confirms a switch in chat) -- never silently.
                        Builder(builder: (context) {
                          final roles = ref.watch(askodoxRoleProvider);
                          final held = [for (final r in AskodoxUserRole.values) if (roles.owned.contains(r)) r];
                          if (held.length < 2) return const SizedBox.shrink();
                          return Row(children: [
                            Text(t('Acting as', 'ఇప్పుడు ఈ పాత్రలో'),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButton<AskodoxUserRole>(
                                key: const Key('askodoxActiveRolePicker'),
                                isExpanded: true,
                                value: held.contains(roles.active) ? roles.active : held.first,
                                items: [
                                  for (final r in held)
                                    DropdownMenuItem(value: r, child: Text(askodoxUserRoleLabel(r, telugu: _te))),
                                ],
                                onChanged: (role) {
                                  if (role == null || role == roles.active) return;
                                  ref.read(askodoxRoleProvider.notifier).setActive(role);
                                  if (ref.read(authSessionProvider).user != null) {
                                    ref.read(askodoxUserProfileProvider.notifier).save({'active_role': role.name});
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    key: const Key('askodoxActiveRoleChanged'),
                                    content: Text(askodoxRoleChangedMessage(roles.active, role, telugu: _te)),
                                  ));
                                },
                              ),
                            ),
                          ]);
                        }),
                      ]))),
            if (signedIn)
              AskodoxNavRow(
                  key: const Key('askodoxProfileEditRoles'),
                  icon: Icons.manage_accounts_outlined,
                  title: t('My roles & their details', 'నా పాత్రలు & వాటి వివరాలు'),
                  subtitle: t('Choose roles once; each adds its own box.', 'పాత్రలు ఒక్కసారే ఎంచుకోండి; ప్రతి దానికి బాక్స్ వస్తుంది.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final profile = ref.read(askodoxUserProfileProvider).valueOrNull;
                    if (profile != null) askodoxOpenProfileEditor(context, ref, profile, telugu: te, section: 'roles');
                  }),
            row('askodoxMyRolesEntry', 'me', Icons.badge_outlined, 'My roles', 'నా పాత్రలు', 'What each role adds.',
                'ప్రతి పాత్ర విభాగాలు.', () => context.push('/profile/roles'),
                guide: 'screen_roles', key: const Key('askodoxMyRolesEntry'), words: ['role', 'పాత్ర']),
            row('profile-opportunities', 'me', Icons.trending_up_rounded, 'Opportunities near you', 'మీ దగ్గరి అవకాశాలు',
                'What nearby customers ask for.', 'దగ్గరి కస్టమర్లు అడుగుతున్నవి.', () => context.push('/opportunities'),
                guide: 'screen_opportunities', words: ['demand', 'customers', 'అవకాశాలు']),
            if (owned.contains(AskodoxUserRole.deliveryPartner))
              row('askodoxProfileDeliveryOpportunities', 'me', Icons.delivery_dining_rounded, 'Delivery & ride partner',
                  'డెలివరీ & రైడ్ పార్ట్‌నర్', 'Go online and accept nearby requests.',
                  'ఆన్‌లైన్‌కి వెళ్లి దగ్గరి రిక్వెస్ట్‌లు అంగీకరించండి.', () => context.push('/mobility?tab=3'),
                  guide: 'screen_partner', key: const Key('askodoxProfileDeliveryOpportunities'), words: ['partner', 'driver']),
          ]),
    ];

    // ---- వ్యాపారం (business)
    final businessSections = <Widget>[
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-business'),
          mascot: AskodoxMascotRole.bizzo,
          grid: true,
          title: t('My Business', 'నా వ్యాపారం'),
          icon: Icons.storefront_rounded,
          children: [
            row('profile-business-center', 'business', Icons.insights_rounded, 'Business dashboard', 'వ్యాపార డాష్‌బోర్డ్',
                'Bills (POS), requests, new demand.', 'బిల్లులు (POS), అభ్యర్థనలు, కొత్త డిమాండ్.',
                () => context.push('/business'),
                guide: 'screen_business', words: ['pos', 'bill', 'shop', 'billing', 'బిల్లు', 'షాప్', 'వ్యాపారం']),
            row('profile-my-listings', 'business', Icons.inventory_2_outlined, 'My listings & catalog', 'నా లిస్టింగ్‌లు & కేటలాగ్',
                'What buyers can find from you.', 'కొనుగోలుదారులకు కనిపించేవి.', () => context.push('/listings/mine'),
                guide: 'screen_listings', words: ['listing', 'products', 'catalog', 'sell', 'అమ్మ', 'లిస్టింగ్']),
            row('profile-enquiries', 'business', Icons.mark_email_unread_outlined, 'Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు',
                'Accept or decline; contact shared only after you accept.', 'అంగీకరించాకే కాంటాక్ట్ షేర్ అవుతుంది.',
                () => context.push('/orders/incoming'), guide: 'screen_enquiries', words: ['orders', 'enquiry', 'ఆర్డర్']),
            row('profile-promotions', 'business', Icons.local_offer_outlined, 'Offers & promotions', 'ఆఫర్లు & ప్రమోషన్లు',
                'Create discounts customers see.', 'కస్టమర్లకు కనిపించే తగ్గింపులు.', () => context.push('/business/promotions'),
                guide: 'screen_promotions', words: ['offer', 'discount', 'ఆఫర్', 'తగ్గింపు']),
            row('profile-automation', 'business', Icons.bolt_rounded, 'Auto-replies', 'ఆటో-రిప్లైలు',
                'Answers sent for you when you are busy.', 'మీరు బిజీగా ఉన్నప్పుడు పంపే జవాబులు.',
                () => context.push('/business/automation'), guide: 'screen_automation', words: ['reply', 'automatic', 'జవాబు']),
          ]),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-studio'),
          mascot: AskodoxMascotRole.studio,
          grid: true,
          title: t('My Studio', 'నా స్టూడియో'),
          icon: Icons.video_library_outlined,
          children: [
            row('profile-native-video', 'business', Icons.ondemand_video_rounded, 'My videos', 'నా వీడియోలు',
                'Upload, preview and publish after review.', 'అప్‌లోడ్, ప్రివ్యూ, రివ్యూ తర్వాత పబ్లిష్.',
                () => context.push('/videos/native'), guide: 'screen_videos', words: ['video', 'upload', 'వీడియో']),
            row('profile-creations', 'business', Icons.auto_awesome_outlined, 'My creations', 'నా క్రియేషన్స్',
                'AI writing drafts from your own facts.', 'మీ వివరాలతో AI డ్రాఫ్ట్‌లు.', () => context.push('/business/creations'),
                guide: 'screen_creations', words: ['ai', 'write', 'post', 'క్రియేషన్']),
          ]),
    ];

    // ---- సెట్టింగ్స్ (settings): account, preferences, privacy, help, app, sign out
    final settingsSections = <Widget>[
      if (signedIn)
        AskodoxNavSection(
            key: const Key('askodoxProfileSection-account'),
            mascot: AskodoxMascotRole.entro,
            grid: true,
            title: t('Account & plans', 'ఖాతా & ప్లాన్లు'),
            icon: Icons.verified_user_outlined,
            children: [
              row('profile-verification', 'settings', Icons.verified_user_outlined, 'Verification (KYC)', 'ధృవీకరణ (KYC)',
                  'Verified sellers get more trust.', 'ధృవీకరించిన వారికి ఎక్కువ నమ్మకం.', () => context.push('/verification'),
                  guide: 'screen_kyc', words: ['kyc', 'verify', 'ధృవీకరణ']),
              row('profile-plans', 'settings', Icons.workspace_premium_outlined, 'Plans & subscription', 'ప్లాన్లు & సబ్‌స్క్రిప్షన్',
                  'Your plan and what each plan adds.', 'మీ ప్లాన్, ప్రతి ప్లాన్‌లో ఏముంది.', () => context.push('/plans'),
                  guide: 'screen_plans', words: ['plan', 'subscription', 'ప్లాన్']),
              row('profile-radio', 'settings', Icons.radio_outlined, 'Travel Radio (add-on)', 'ట్రావెల్ రేడియో (యాడ్-ఆన్)',
                  'Hear about places on your route.', 'మీ దారిలోని ప్రాంతాల గురించి వినండి.', () => context.push('/radio'),
                  guide: 'screen_radio', words: ['radio', 'రేడియో']),
            ]),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-settings'),
          grid: true,
          title: t('Settings & Privacy', 'సెట్టింగ్స్ & గోప్యత'),
          icon: Icons.settings_outlined,
          children: [
            row('profile-location', 'settings', Icons.location_on_outlined, 'Location', 'లొకేషన్', '', '',
                () => context.push('/location'), guide: 'screen_location', subtitle: locationLabel, words: ['place', 'city', 'ఊరు', 'ప్రాంతం']),
            SwitchListTile(
              key: const Key('askodoxVoiceModeSwitch'),
              dense: true,
              secondary: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF1769FF)),
              title: Text(t('Voice Mode', 'వాయిస్ మోడ్'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(t('On: every reply is spoken. Off: text only (replay any reply).',
                  'ఆన్: ప్రతి జవాబు వినిపిస్తుంది. ఆఫ్: టెక్స్ట్ మాత్రమే (ఏ జవాబైనా మళ్లీ వినవచ్చు).')),
              value: ref.watch(askodoxVoiceModeProvider),
              onChanged: (on) => ref.read(askodoxVoiceModeProvider.notifier).set(on),
            ),
            row('profile-voice', 'settings', Icons.record_voice_over_outlined, 'Voice preference', 'వాయిస్ ప్రాధాన్యత', '', '',
                () => _pickVoicePreference(te), subtitle: _voiceLabel(voicePreference, te), words: ['voice', 'వాయిస్', 'గొంతు']),
            row('profile-notifications', 'settings', Icons.notifications_none_rounded, 'Notifications', 'నోటిఫికేషన్స్',
                'Choose what you are told about.', 'ఏ విషయాలు తెలియజేయాలో ఎంచుకోండి.', () => context.push('/settings/notifications'),
                guide: 'screen_notifications', words: ['notification', 'alerts', 'నోటిఫికేషన్']),
            if (signedIn)
              row('askodoxProfileMemoryEntry', 'settings', Icons.psychology_alt_outlined, 'Memory & personalization',
                  'మెమరీ & వ్యక్తిగతీకరణ', 'Private; correct, delete or switch off.', 'ప్రైవేట్; సరిచేయండి, తొలగించండి లేదా ఆపండి.',
                  () => context.push('/profile/memory'),
                  guide: 'screen_memory', key: const Key('askodoxProfileMemoryEntry'), words: ['memory', 'history', 'మెమరీ', 'చరిత్ర']),
            row('profile-privacy', 'settings', Icons.privacy_tip_outlined, 'Privacy & data', 'గోప్యత & డేటా',
                'See, download or delete your data.', 'మీ డేటా చూడండి, డౌన్‌లోడ్ లేదా తొలగించండి.', () => context.push('/privacy'),
                guide: 'screen_privacy', words: ['privacy', 'delete', 'data', 'గోప్యత']),
          ]),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-help'),
          mascot: AskodoxMascotRole.suppo,
          grid: true,
          title: t('Help & Support', 'సహాయం & సపోర్ట్'),
          icon: Icons.support_agent_rounded,
          children: [
            (AskodoxNavRow(
                  key: const ValueKey('profile-help'),
                  icon: Icons.support_agent_rounded,
                  title: t('Help', 'సహాయం'),
                  subtitle: t('Ask ASKODOX; it connects you to Customer Care if needed.',
                      'ASKODOX ని అడగండి; అవసరమైతే కస్టమర్ కేర్‌కు కలుపుతుంది.'),
                  // Conversation first -> a guide on the real screen -> a
                  // human (Customer Care) when needed.
                  onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (sheet) => SafeArea(
                          child: SingleChildScrollView(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(
                                key: const ValueKey('help-ask'),
                                leading: const Icon(Icons.chat_bubble_outline_rounded),
                                title: Text(t('Ask ASKODOX', 'ASKODOX ని అడగండి')),
                                onTap: () {
                                  Navigator.pop(sheet);
                                  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(
                                      t('I need help with ASKODOX', 'నాకు ASKODOX తో సహాయం కావాలి'));
                                  context.go('/');
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(t('Show me how (on the real screen)', 'ఎలాగో చూపించు (అసలు స్క్రీన్‌పై)'),
                                        style: const TextStyle(fontWeight: FontWeight.w800))),
                              ),
                              AskodoxGuideList(te: te, onStarted: () => Navigator.pop(sheet)),
                              ListTile(
                                key: const ValueKey('help-support'),
                                leading: const Icon(Icons.support_agent_rounded),
                                title: Text(t('Talk to Customer Care', 'కస్టమర్ కేర్‌తో మాట్లాడండి')),
                                onTap: () {
                                  Navigator.pop(sheet);
                                  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(
                                      t('I want to talk to Customer Care', 'నేను కస్టమర్ కేర్‌తో మాట్లాడాలి'));
                                  context.go('/');
                                },
                              ),
                            ]),
                          ),
                        ),
                      ))),
            row('profile-feedback', 'settings', Icons.bug_report_outlined, 'Report a problem / Send feedback',
                'సమస్య చెప్పండి / ఫీడ్‌బ్యాక్ పంపండి', '', '', () => context.push('/beta-feedback'),
                guide: 'screen_feedback',
                words: ['problem', 'bug', 'feedback', 'సమస్య'],
                subtitle: early.active
                    ? (early.freeTrial
                        ? '${early.label} · ${t('free while in testing', 'టెస్టింగ్ సమయంలో ఉచితం')}'
                        : early.label)
                    : t('Tell us what went wrong.', 'ఏం తప్పు జరిగిందో చెప్పండి.')),
            if (ref.watch(askodoxIsStaffProvider).valueOrNull == true) (ListTile(
                    key: const ValueKey('profile-staff-workspace'),
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(t('Staff Workspace', 'స్టాఫ్ వర్క్‌స్పేస్')),
                    subtitle: Text(t('Add products, links, offers; tasks and support.',
                        'ప్రొడక్ట్స్, లింకులు, ఆఫర్లు; టాస్కులు, సపోర్ట్.')),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () async {
                      if (!await openStaffWorkspace(context, ref) && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(t('Could not open the Staff Workspace. Check the connection.',
                                'స్టాఫ్ వర్క్‌స్పేస్ తెరవలేకపోయాం. కనెక్షన్ చూడండి.'))));
                      }
                    })),
          ]),
      AskodoxNavSection(
          key: const Key('askodoxProfileSection-app'),
          title: t('App', 'యాప్'),
          icon: Icons.system_update_alt_rounded,
          children: [
            (Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          const Icon(Icons.system_update_alt_rounded,
                              color: Color(0xFF1769FF)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(t('App Update', 'యాప్ అప్డేట్'),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900)))
                        ]),
                        const SizedBox(height: 8),
                        Text(t(
                            'Check and install the latest signed ASKODOX build without reinstalling manually.',
                            'Manual reinstall లేకుండా తాజా signed ASKODOX buildని చెక్ చేసి install చేయండి.')),
                        if (_message != null) ...[
                          const SizedBox(height: 10),
                          Text(_message!)
                        ],
                        if (_installing) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(value: _progress)
                        ],
                        const SizedBox(height: 12),
                        if (_update == null)
                          FilledButton.icon(
                              onPressed: _checking ? null : _checkUpdate,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded),
                              label: Text(
                                  t('Check for Update', 'అప్డేట్ చెక్ చేయండి')))
                        else
                          FilledButton.icon(
                              onPressed: _installing ? null : _install,
                              icon: const Icon(Icons.download_rounded),
                              label: Text(t('Download & Install',
                                  'డౌన్‌లోడ్ & ఇన్‌స్టాల్'))),
                      ]))),
            if (askodoxDiagnosticsAllowed)
              AskodoxNavRow(
                  key: const Key('askodoxDeveloperDiagnosticsEntry'),
                  icon: Icons.developer_mode_rounded,
                  title: t('Developer Diagnostics', 'డెవలపర్ డయాగ్నస్టిక్స్'),
                  subtitle: t('FCM token and Installation ID (development builds only).',
                      'FCM టోకెన్, ఇన్‌స్టాలేషన్ ID (డెవలప్‌మెంట్ బిల్డ్‌లలో మాత్రమే).'),
                  onTap: () => context.push('/settings/diagnostics')),
            // Sign out: always the LAST item of Profile (same flow as the side menu's Logout).
            if (signedIn) Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: OutlinedButton.icon(
                key: const Key('askodoxProfileSignOut'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFB42318)),
                    minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.logout_rounded),
                label: Text(t('Sign out', 'సైన్ అవుట్'), style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () async {
                  if (await askodoxConfirmSignOut(context, te: te) && context.mounted) {
                    await askodoxSignOut(ref, restartFrom: context);
                  }
                },
              ),
            ),
          ]),
    ];

    // Help lives in Settings; saying "help" / "సహాయం" finds it too.
    entries.add(_ProfileEntry('profile-help', 'settings', Icons.support_agent_rounded, 'Help & Customer Care',
        'సహాయం & కస్టమర్ కేర్', const ['help', 'support', 'care', 'సహాయం', 'కస్టమర్'], () => setState(() => _tab = 'settings')));
    // A running walkthrough whose next button sits in another tab: open that tab.
    final guide = ref.watch(askodoxGuideProvider);
    if (guide != null && !guide.done) {
      final target = guide.step.target;
      final hit = entries.where((e) => e.id == target).firstOrNull;
      if (hit != null && hit.tab != _tab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _tab = hit.tab);
        });
      }
    }

    final query = _query.trim();
    final results = query.isEmpty ? const <_ProfileEntry>[] : entries.where((e) => _matches(e, query)).toList();
    final recent = [for (final id in _recent) ...entries.where((e) => e.id == id)];

    Widget tabButton(Key key, String id, String label, IconData icon) {
      final on = _tab == id;
      return Expanded(
        child: Material(
          color: on ? Colors.white : Colors.transparent,
          elevation: on ? 1 : 0,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _tab = id),
            child: SizedBox(
              height: 44,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: on ? const Color(0xFF1769FF) : const Color(0xFF667085)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                          color: on ? const Color(0xFF10204A) : const Color(0xFF475467))),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The user's own stored profile (photo, name, mobile, address, language, roles, business).
          AskodoxProfileHeader(telugu: te),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('askodoxProfileGuide'),
                icon: const Icon(Icons.face_retouching_natural, color: Color(0xFF6C4DFF)),
                label: Text(t('Guide: fill my profile', 'గైడ్: నా ప్రొఫైల్ నింపడం'),
                    style: const TextStyle(color: Color(0xFF6C4DFF), fontWeight: FontWeight.w800)),
                onPressed: () {
                  final flow = askodoxGuideById('screen_profile_details');
                  if (flow != null) ref.read(askodoxGuideProvider.notifier).start(flow);
                },
              ),
            ),
          ),
          // Talk or type: "what do you want?" -- finds the right row; one spoken match opens it.
          Container(
            key: const Key('askodoxProfileAsk'),
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFFD0D9EA))),
            child: Row(children: [
              const Icon(Icons.search_rounded, color: Color(0xFF667085)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('askodoxProfileSearch'),
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: t('What do you need? e.g. notifications, my shop', 'ఏది కావాలి? ఉదా: నోటిఫికేషన్లు, నా షాప్'),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: t('Clear', 'తుడిచేయి'),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              AskodoxQuestionMic(
                lang: te ? 'te' : 'en',
                onText: (text) {
                  _search.text = text;
                  final found = entries.where((e) => _matches(e, text)).toList();
                  if (found.length == 1) {
                    // Said clearly: open it at once.
                    setState(() => _query = '');
                    _search.clear();
                    _remember(found.single.id);
                    found.single.go();
                  } else {
                    setState(() => _query = text);
                  }
                },
              ),
            ]),
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (results.isEmpty)
              Card(
                key: const Key('askodoxProfileSearchNone'),
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF1769FF)),
                  title: Text(t('Not in Profile — ask ASKODOX', 'ప్రొఫైల్‌లో లేదు — ASKODOX ని అడగండి')),
                  subtitle: Text('"$query"'),
                  onTap: () {
                    ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(query);
                    context.go('/');
                  },
                ),
              )
            else
              AskodoxNavSection(
                key: const Key('askodoxProfileSearchResults'),
                title: t('Found', 'దొరికినవి'),
                icon: Icons.search_rounded,
                children: [
                  for (final e in results)
                    AskodoxNavRow(
                        key: ValueKey('askodoxProfileSearchResult-${e.id}'),
                        icon: e.icon,
                        title: t(e.en, e.te),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          _remember(e.id);
                          e.go();
                        }),
                ],
              ),
          ] else ...[
            if (recent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(t('Recent:', 'ఇటీవల:'), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475467))),
                  for (final e in recent)
                    ActionChip(
                      key: ValueKey('askodoxProfileRecent-${e.id}'),
                      avatar: Icon(e.icon, size: 16, color: const Color(0xFF1769FF)),
                      label: Text(t(e.en, e.te)),
                      onPressed: () {
                        _remember(e.id);
                        e.go();
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFE4E9F2), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                tabButton(const Key('askodoxProfileTab-me'), 'me', t('Me', 'నేను'), Icons.person_outline_rounded),
                tabButton(const Key('askodoxProfileTab-business'), 'business', t('Business', 'వ్యాపారం'), Icons.storefront_outlined),
                tabButton(const Key('askodoxProfileTab-settings'), 'settings', t('Settings', 'సెట్టింగ్స్'), Icons.settings_outlined),
              ]),
            ),
            ...switch (_tab) {
              'business' => businessSections,
              'settings' => settingsSections,
              _ => meSections,
            },
          ],
        ]),
      ),
    );
  }
}

class _ProfileEntry {
  const _ProfileEntry(this.id, this.tab, this.icon, this.en, this.te, this.words, this.go);
  final String id;
  final String tab;
  final IconData icon;
  final String en;
  final String te;
  final List<String> words;
  final VoidCallback go;
}
