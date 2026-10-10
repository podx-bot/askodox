import 'package:flutter/material.dart';

import '../../../shared/widgets/navigator_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../companion/askodox_companion.dart';
import '../../companion/companion_floating.dart';
import '../../companion/companion_hub.dart';
import '../../companion/companion_picker.dart';
import '../../companion/screen_guide.dart';
import '../../home/application/conversation_archive.dart';
import '../../home/application/saved_options.dart';
import '../../home/domain/active_role.dart';
import '../../location/application/location_controller.dart';
import '../../staff/askodox_staff_access.dart';
import '../data/user_profile_repository.dart';
import 'profile_header.dart';
import '../../guide/in_app_guide.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      // ASKODOX Navigator: grouped sections, every row opens its own
      // screen. Column (not a lazy list) so every section is built.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The user's own stored profile (photo, name, mobile, address,
          // language, roles, business) -- never placeholder data.
          AskodoxProfileHeader(telugu: te),
          if (ref.watch(authSessionProvider).user == null)
            AskodoxNavSection(title: t('Account', 'ఖాతా'), icon: Icons.person_outline_rounded, children: [
              AskodoxNavRow(
                  key: const Key('askodoxProfileSignIn'),
                  icon: Icons.phone_iphone_rounded,
                  title: t('Sign in with your phone', 'మీ ఫోన్‌తో సైన్ ఇన్ చేయండి'),
                  subtitle: t('Needed only to send requests and see their status.',
                      'అభ్యర్థనలు పంపడానికి, వాటి స్థితి చూడడానికి మాత్రమే అవసరం.'),
                  onTap: () => context.push('/onboarding?signin=1')),
            ]),
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-business'),
              title: t('My Business', 'నా వ్యాపారం'),
              icon: Icons.storefront_rounded,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-business-center'),
                icon: Icons.insights_rounded,
                title: t('Business dashboard', 'వ్యాపార డాష్‌బోర్డ్'),
                subtitle: t('Requests, missing details customers asked for, new demand.', 'అభ్యర్థనలు, కస్టమర్లు అడిగిన వివరాలు, కొత్త డిమాండ్.'),
                onTap: () => context.push('/business')),
            AskodoxNavRow(
                key: const ValueKey('profile-my-listings'),
                icon: Icons.inventory_2_outlined,
                title: t('My listings & catalog', 'నా లిస్టింగ్‌లు & కేటలాగ్'),
                subtitle: t('What buyers can find from you.', 'కొనుగోలుదారులకు కనిపించేవి.'),
                onTap: () => context.push('/listings/mine')),
            AskodoxNavRow(
                key: const ValueKey('profile-enquiries'),
                icon: Icons.mark_email_unread_outlined,
                title: t('Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు'),
                subtitle: t('Accept or decline; contact is shared only after you accept.', 'అంగీకరించాకే కాంటాక్ట్ షేర్ అవుతుంది.'),
                onTap: () => context.push('/orders/incoming')),
            AskodoxNavRow(
                key: const ValueKey('profile-promotions'),
                icon: Icons.local_offer_outlined,
                title: t('Offers & promotions', 'ఆఫర్లు & ప్రమోషన్లు'),
                onTap: () => context.push('/business/promotions')),
            AskodoxNavRow(
                key: const ValueKey('profile-automation'),
                icon: Icons.forum_outlined,
                title: t('Auto-replies', 'ఆటో-రిప్లైలు'),
                onTap: () => context.push('/business/automation')),
              ]),
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-studio'),
              title: t('My Studio', 'నా స్టూడియో'),
              icon: Icons.auto_awesome_outlined,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-native-video'),
                icon: Icons.video_library_outlined,
                title: t('My videos', 'నా వీడియోలు'),
                subtitle: t('Upload, preview and publish after review.', 'అప్‌లోడ్, ప్రివ్యూ, రివ్యూ తర్వాత పబ్లిష్.'),
                onTap: () => context.push('/videos/native')),
            AskodoxNavRow(
                key: const ValueKey('profile-creations'),
                icon: Icons.edit_note_rounded,
                title: t('My creations', 'నా క్రియేషన్స్'),
                subtitle: t('AI writing drafts from your own facts.', 'మీ వివరాలతో AI డ్రాఫ్ట్‌లు.'),
                onTap: () => context.push('/business/creations')),
          if (ref.watch(askodoxSavedOptionsProvider).isNotEmpty)
            KeyedSubtree(key: const Key('askodoxSavedOptionsTile'), child: ListTile(
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
              title: t('Roles & Opportunities', 'పాత్రలు & అవకాశాలు'),
              icon: Icons.badge_outlined,
              children: [
          (Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Your roles', 'మీ పాత్రలు'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(t(
                            'One person can be a buyer, seller, service provider or more at the same time.',
                            'ఒకే వ్యక్తి Buyer, Seller, Service Provider లేదా ఇతర పాత్రల్లో ఒకేసారి ఉండవచ్చు.')),
                        const SizedBox(height: 12),
                        Builder(builder: (context) {
                          // Held roles are edited here only; the conversation
                          // moves the ACTIVE role, highlighted below.
                          final roles = ref.watch(askodoxRoleProvider);
                          return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final role in {
                                  ...askodoxProfileRoles,
                                  roles.active,
                                })
                                  FilterChip(
                                      key: ValueKey('profileRole-${role.name}'),
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
                        const SizedBox(height: 12),
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
            AskodoxNavRow(
                key: const Key('askodoxMyRolesEntry'),
                icon: Icons.badge_outlined,
                title: t('My roles', 'నా పాత్రలు'),
                subtitle: t('What each role adds.', 'ప్రతి పాత్ర విభాగాలు.'),
                onTap: () => context.push('/profile/roles')),
            AskodoxNavRow(
                key: const ValueKey('profile-opportunities'),
                icon: Icons.trending_up_rounded,
                title: t('Opportunities near you', 'మీ దగ్గరి అవకాశాలు'),
                onTap: () => context.push('/opportunities')),
            if (ref.watch(askodoxRoleProvider).owned.contains(AskodoxUserRole.deliveryPartner))
            AskodoxNavRow(
                key: const Key('askodoxProfileDeliveryOpportunities'),
                icon: Icons.delivery_dining_rounded,
                title: t('Delivery & ride partner', 'డెలివరీ & రైడ్ పార్ట్‌నర్'),
                subtitle: t('Go online and accept nearby requests.', 'ఆన్‌లైన్‌కి వెళ్లి దగ్గరి రిక్వెస్ట్‌లు అంగీకరించండి.'),
                onTap: () => context.push('/mobility?tab=3')),
            AskodoxNavRow(
                key: const ValueKey('profile-mobility'),
                icon: Icons.local_taxi_outlined,
                title: t('Rides, parcels & carpool', 'రైడ్స్, పార్సెల్స్ & కార్‌పూల్'),
                subtitle: t('Book, track, or drive / deliver.', 'బుక్, ట్రాక్, లేదా డ్రైవ్ / డెలివర్.'),
                onTap: () => context.push('/mobility')),
              ]),
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-settings'),
              title: t('Settings & Privacy', 'సెట్టింగ్స్ & గోప్యత'),
              icon: Icons.settings_outlined,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-location'),
                icon: Icons.location_on_outlined,
                title: t('Location', 'లొకేషన్'),
                subtitle: locationLabel,
                onTap: () => context.push('/location')),
            AskodoxNavRow(
                icon: Icons.record_voice_over_outlined,
                title: t('Voice preference', 'వాయిస్ ప్రాధాన్యత'),
                subtitle: _voiceLabel(voicePreference, te),
                onTap: () => _pickVoicePreference(te)),
            AskodoxNavRow(
                key: const ValueKey('profile-notifications'),
                icon: Icons.notifications_none_rounded,
                title: t('Notifications', 'నోటిఫికేషన్స్'),
                onTap: () => context.push('/settings/notifications')),
            if (ref.watch(authSessionProvider).user != null)
            AskodoxNavRow(
                key: const Key('askodoxProfileMemoryEntry'),
                icon: Icons.psychology_alt_outlined,
                title: t('Memory & personalization', 'మెమరీ & వ్యక్తిగతీకరణ'),
                subtitle: t('Private; correct, delete or switch off.', 'ప్రైవేట్; సరిచేయండి, తొలగించండి లేదా ఆపండి.'),
                onTap: () => context.push('/profile/memory')),
            AskodoxNavRow(
                key: const ValueKey('profile-privacy'),
                icon: Icons.privacy_tip_outlined,
                title: t('Privacy & data', 'గోప్యత & డేటా'),
                onTap: () => context.push('/privacy')),
          // How the ASKODOX friend looks (never assumes a gender) and
          // whether it moves (off = still image, saves battery).
          KeyedSubtree(key: const Key('askodoxCompanionLook'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(
                  key: const Key('askodoxCompanionEnabled'),
                  secondary: const Icon(Icons.smart_toy_outlined, color: Color(0xFF1769FF)),
                  title: Text(t('ASKODOX friend', 'ASKODOX స్నేహితుడు'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(t('Off = plain mic button, no animation.', 'ఆఫ్ = సాధారణ మైక్ బటన్, యానిమేషన్ లేదు.')),
                  value: ref.watch(askodoxCompanionSettingsProvider).enabled,
                  onChanged: (on) => ref.read(askodoxCompanionSettingsProvider.notifier).update(enabled: on),
                ),
                if (ref.watch(askodoxCompanionSettingsProvider).enabled) ...[
                AskodoxCompanionPicker(telugu: te),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('askodoxCompanion3d'),
                  title: Text(t('3D friend', '3D స్నేహితుడు')),
                  subtitle: Text(t('Slow phones switch to the Lite robot, then the flat friend, automatically.',
                      'నెమ్మదైన ఫోన్లలో ఆటోమేటిక్‌గా లైట్ రోబోట్, తర్వాత ఫ్లాట్ స్నేహితుడు.')),
                  value: ref.watch(askodoxCompanionSettingsProvider).render3d,
                  onChanged: (on) => ref.read(askodoxCompanionSettingsProvider.notifier).update(render3d: on),
                ),
                SwitchListTile(
                  key: const Key('askodoxCompanionMotion'),
                  title: Text(t('Friend moves while it works', 'పని చేస్తున్నప్పుడు కదులుతుంది')),
                  value: ref.watch(askodoxCompanionSettingsProvider).animate,
                  onChanged: (on) => ref.read(askodoxCompanionSettingsProvider.notifier).update(animate: on),
                ),
                if (ref.watch(askodoxCompanionSettingsProvider).companion == AskodoxCompanionSettings.humanHd &&
                    AskodoxCompanionPerformance.vrmFallback != null)
                  Padding(
                    key: const Key('askodoxHumanHdFallbackNotice'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        t('Human HD could not run smoothly on this phone (${AskodoxCompanionPerformance.vrmFallback}); '
                            'the light human is shown this session.',
                            'ఈ ఫోన్‌లో హ్యూమన్ HD సాఫీగా నడవలేదు (${AskodoxCompanionPerformance.vrmFallback}); '
                            'ఈ సెషన్‌లో లైట్ హ్యూమన్ చూపిస్తున్నాం.'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A5B00))),
                  ),
                SwitchListTile(
                  key: const Key('askodoxInAppFloating'),
                  title: Text(t('Floating companion in ASKODOX', 'ASKODOXలో తేలియాడే సహచరుడు')),
                  subtitle: Text(t(
                      'Keeps your companion on Explore, Orders and Profile. Drag it anywhere; it snaps to the side '
                          'and remembers where you left it.',
                      'ఎక్స్‌ప్లోర్, ఆర్డర్లు, ప్రొఫైల్‌లో కూడా మీ సహచరుడు ఉంటారు. ఎక్కడికైనా లాగండి; పక్కకు అతుక్కుంటారు, '
                          'మీరు వదిలిన చోటు గుర్తుంచుకుంటారు.')),
                  value: ref.watch(askodoxInAppFloatProvider).enabled,
                  onChanged: (on) => ref.read(askodoxInAppFloatProvider.notifier).setEnabled(on),
                ),
                Builder(builder: (context) {
                  final bubble = ref.watch(askodoxBubbleProvider);
                  final caps = ref.watch(companionCapabilitiesProvider).valueOrNull ?? const <String, bool>{};
                  if (!companionAllows(caps, 'floating_bubble')) {
                    // Switched off by ASKODOX (e.g. a platform policy change): the bubble
                    // stops; everything else keeps working.
                    if (bubble == AskodoxBubbleState.enabled) {
                      Future.microtask(() => ref.read(askodoxBubbleProvider.notifier).disable());
                    }
                    return ListTile(
                      key: const Key('askodoxFloatingBubbleUnavailable'),
                      leading: const Icon(Icons.bubble_chart_outlined),
                      title: Text(t('Floating ASKODOX bubble', 'తేలియాడే ASKODOX బబుల్')),
                      subtitle: Text(t('Not available right now. ASKODOX works normally.',
                          'ప్రస్తుతం అందుబాటులో లేదు. ASKODOX యథావిధిగా పనిచేస్తుంది.')),
                    );
                  }
                  return SwitchListTile(
                    key: const Key('askodoxFloatingBubble'),
                    title: Text(t('Floating ASKODOX bubble', 'తేలియాడే ASKODOX బబుల్')),
                    subtitle: Text(switch (bubble) {
                      AskodoxBubbleState.needsPermission => t(
                          'Allow "Display over other apps" for ASKODOX, then come back.',
                          'ASKODOX కి "ఇతర యాప్‌లపై చూపించు" అనుమతి ఇచ్చి తిరిగి రండి.'),
                      AskodoxBubbleState.unsupported =>
                        t('Not available on this Android version.', 'ఈ Android వెర్షన్‌లో అందుబాటులో లేదు.'),
                      _ => t(
                          'A small bubble over other apps -- tap it to come back to ASKODOX. It never listens or '
                              'reads your screen. Android shows a notification while it is on.',
                          'ఇతర యాప్‌లపై చిన్న బబుల్ -- నొక్కితే ASKODOX కి తిరిగి వస్తారు. ఇది వినదు, స్క్రీన్ చదవదు. '
                              'ఆన్‌లో ఉన్నప్పుడు Android నోటిఫికేషన్ చూపిస్తుంది.'),
                    }),
                    value: bubble == AskodoxBubbleState.enabled || bubble == AskodoxBubbleState.needsPermission,
                    onChanged: (on) => on
                        ? ref.read(askodoxBubbleProvider.notifier).enable()
                        : ref.read(askodoxBubbleProvider.notifier).disable(),
                  );
                }),
                ListTile(
                  key: const Key('askodoxScreenGuideEntry'),
                  leading: const Icon(Icons.assistant_navigation),
                  title: Text(t('Screen Guide (beta)', 'స్క్రీన్ గైడ్ (బీటా)')),
                  subtitle: Text(t('Step-by-step help in other apps. You press every button; pauses on private screens.',
                      'ఇతర యాప్‌లలో దశలవారీ సహాయం. ప్రతి బటన్ మీరే నొక్కుతారు; ప్రైవేట్ స్క్రీన్‌లలో ఆగుతుంది.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/companion/screen-guide'),
                ),
                ListTile(
                  key: const Key('askodoxCompanionPerformance'),
                  leading: const Icon(Icons.speed_rounded),
                  title: Text(t('Companion performance', 'సహచరుడి పనితీరు')),
                  subtitle: Text(t('Frames, memory, battery and startup on this phone.',
                      'ఈ ఫోన్‌లో ఫ్రేమ్‌లు, మెమరీ, బ్యాటరీ, స్టార్ట్‌అప్.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/companion-performance'),
                ),
                ],
              ])),
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
              ]),
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-help'),
              title: t('Help & Support', 'సహాయం & సపోర్ట్'),
              icon: Icons.support_agent_rounded,
              children: [
          (ListTile(
                  key: const ValueKey('profile-help'),
                  leading: const Icon(Icons.support_agent_rounded),
                  title: Text(t('Help', 'సహాయం')),
                  subtitle: Text(t('Ask ASKODOX; it connects you to Customer Care if needed.',
                      'ASKODOX ని అడగండి; అవసరమైతే కస్టమర్ కేర్‌కు కలుపుతుంది.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
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
          // Early Access label + feedback (Command Center decides who sees it).
          Builder(builder: (context) {
            final early = ref.watch(askodoxEarlyAccessProvider).valueOrNull ?? EarlyAccessInfo.inactive;
            return (ListTile(
                    key: const ValueKey('profile-feedback'),
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(t('Report a problem / Send feedback', 'సమస్య చెప్పండి / ఫీడ్‌బ్యాక్ పంపండి')),
                    subtitle: early.active
                        ? Text(early.freeTrial
                            ? '${early.label} · ${t('free while in testing', 'టెస్టింగ్ సమయంలో ఉచితం')}'
                            : early.label)
                        : null,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/beta-feedback')));
          }),
          // Staff only: the server decides (the number must be linked to an
          // active staff record); nothing is shown to anyone else.
          if (ref.watch(askodoxIsStaffProvider).valueOrNull == true)
            (ListTile(
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
        ]),
      ),
    );
  }

}
