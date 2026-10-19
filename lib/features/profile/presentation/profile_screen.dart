import 'package:flutter/material.dart';

import '../../../shared/widgets/navigator_section.dart';
import '../../home/application/voice_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'profile_header.dart';
import 'role_switcher.dart';
import '../../../shared/widgets/askodox_mascot.dart';
import '../../settings/developer_diagnostics_screen.dart';
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
    final early = ref.watch(askodoxEarlyAccessProvider).valueOrNull ?? EarlyAccessInfo.inactive;
    final signedIn = ref.watch(authSessionProvider).user != null;
    // Only the ACTIVE role's sections; every held role stays one tap away.
    final active = ref.watch(askodoxRoleProvider).active;
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
          AskodoxRoleSwitcher(telugu: te),
          // Guide for the details above: what to write where.
          Padding(
            padding: const EdgeInsets.only(top: 8),
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
          if (askodoxRoleShowsBusiness(active))
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-business'),
              mascot: AskodoxMascotRole.bizzo,
              grid: true,
              title: t('My Business', 'నా వ్యాపారం'),
              icon: Icons.storefront_rounded,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-business-center'), guide: 'screen_business',
                icon: Icons.insights_rounded,
                title: t('Business dashboard', 'వ్యాపార డాష్‌బోర్డ్'),
                subtitle: t('Requests, missing details customers asked for, new demand.', 'అభ్యర్థనలు, కస్టమర్లు అడిగిన వివరాలు, కొత్త డిమాండ్.'),
                onTap: () => context.push('/business')),
            AskodoxNavRow(
                key: const ValueKey('profile-my-listings'), guide: 'screen_listings',
                icon: Icons.inventory_2_outlined,
                title: t('My listings & catalog', 'నా లిస్టింగ్‌లు & కేటలాగ్'),
                subtitle: t('What buyers can find from you.', 'కొనుగోలుదారులకు కనిపించేవి.'),
                onTap: () => context.push('/listings/mine')),
            AskodoxNavRow(
                key: const ValueKey('profile-enquiries'), guide: 'screen_enquiries',
                icon: Icons.mark_email_unread_outlined,
                title: t('Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు'),
                subtitle: t('Accept or decline; contact is shared only after you accept.', 'అంగీకరించాకే కాంటాక్ట్ షేర్ అవుతుంది.'),
                onTap: () => context.push('/orders/incoming')),
            AskodoxNavRow(
                key: const ValueKey('profile-promotions'), guide: 'screen_promotions',
                icon: Icons.local_offer_outlined,
                title: t('Offers & promotions', 'ఆఫర్లు & ప్రమోషన్లు'),
                subtitle: t('Create discounts customers see.', 'కస్టమర్లకు కనిపించే తగ్గింపులు.'),
                onTap: () => context.push('/business/promotions')),
            AskodoxNavRow(
                key: const ValueKey('profile-automation'), guide: 'screen_automation',
                icon: Icons.forum_outlined,
                title: t('Auto-replies', 'ఆటో-రిప్లైలు'),
                subtitle: t('Answers sent for you when you are busy.', 'మీరు బిజీగా ఉన్నప్పుడు పంపే జవాబులు.'),
                onTap: () => context.push('/business/automation')),
              ]),
          if (askodoxRoleShowsStudio(active))
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-studio'),
              mascot: AskodoxMascotRole.studio,
              grid: true,
              title: t('My Studio', 'నా స్టూడియో'),
              icon: Icons.auto_awesome_outlined,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-native-video'), guide: 'screen_videos',
                icon: Icons.video_library_outlined,
                title: t('My videos', 'నా వీడియోలు'),
                subtitle: t('Upload, preview and publish after review.', 'అప్‌లోడ్, ప్రివ్యూ, రివ్యూ తర్వాత పబ్లిష్.'),
                onTap: () => context.push('/videos/native')),
            AskodoxNavRow(
                key: const ValueKey('profile-creations'), guide: 'screen_creations',
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
              mascot: AskodoxMascotRole.entro,
              grid: true,
              title: t('Roles, opportunities & rides', 'పాత్రలు, అవకాశాలు & రైడ్స్'),
              icon: Icons.badge_outlined,
              children: [
            AskodoxNavRow(
                key: const Key('askodoxMyRolesEntry'), guide: 'screen_roles',
                icon: Icons.badge_outlined,
                title: t('My roles', 'నా పాత్రలు'),
                subtitle: t('What each role adds.', 'ప్రతి పాత్ర విభాగాలు.'),
                onTap: () => context.push('/profile/roles')),
            if (askodoxRoleShowsOpportunities(active))
            AskodoxNavRow(
                key: const ValueKey('profile-opportunities'), guide: 'screen_opportunities',
                icon: Icons.trending_up_rounded,
                title: t('Opportunities near you', 'మీ దగ్గరి అవకాశాలు'),
                subtitle: t('What nearby customers ask for.', 'దగ్గరి కస్టమర్లు అడుగుతున్నవి.'),
                onTap: () => context.push('/opportunities')),
            if (askodoxRoleShowsPartner(active))
            AskodoxNavRow(
                key: const Key('askodoxProfileDeliveryOpportunities'), guide: 'screen_partner',
                icon: Icons.delivery_dining_rounded,
                title: t('Delivery & ride partner', 'డెలివరీ & రైడ్ పార్ట్‌నర్'),
                subtitle: t('Go online and accept nearby requests.', 'ఆన్‌లైన్‌కి వెళ్లి దగ్గరి రిక్వెస్ట్‌లు అంగీకరించండి.'),
                onTap: () => context.push('/mobility?tab=3')),
            AskodoxNavRow(
                key: const ValueKey('profile-mobility'), guide: 'screen_mobility',
                icon: Icons.local_taxi_outlined,
                title: t('Rides, parcels & carpool', 'రైడ్స్, పార్సెల్స్ & కార్‌పూల్'),
                subtitle: t('Book, track, or drive / deliver.', 'బుక్, ట్రాక్, లేదా డ్రైవ్ / డెలివర్.'),
                onTap: () => context.push('/mobility')),
              ]),
          if (signedIn)
            AskodoxNavSection(
                key: const Key('askodoxProfileSection-account'),
              mascot: AskodoxMascotRole.entro,
                grid: true,
                title: t('Account & plans', 'ఖాతా & ప్లాన్లు'),
                icon: Icons.verified_user_outlined,
                children: [
                  AskodoxNavRow(
                      key: const ValueKey('profile-verification'), guide: 'screen_kyc',
                      icon: Icons.verified_user_outlined,
                      title: t('Verification (KYC)', 'ధృవీకరణ (KYC)'),
                      subtitle: t('Verified sellers get more trust.', 'ధృవీకరించిన వారికి ఎక్కువ నమ్మకం.'),
                      onTap: () => context.push('/verification')),
                  AskodoxNavRow(
                      key: const ValueKey('profile-plans'), guide: 'screen_plans',
                      icon: Icons.workspace_premium_outlined,
                      title: t('Plans & subscription', 'ప్లాన్లు & సబ్‌స్క్రిప్షన్'),
                      subtitle: t('Your plan and what each plan adds.', 'మీ ప్లాన్, ప్రతి ప్లాన్‌లో ఏముంది.'),
                      onTap: () => context.push('/plans')),
                  AskodoxNavRow(
                      key: const ValueKey('profile-radio'), guide: 'screen_radio',
                      icon: Icons.radio_outlined,
                      title: t('Travel Radio (add-on)', 'ట్రావెల్ రేడియో (యాడ్-ఆన్)'),
                      subtitle: t('Hear about places on your route.', 'మీ దారిలోని ప్రాంతాల గురించి వినండి.'),
                      onTap: () => context.push('/radio')),
                ]),
          AskodoxNavSection(
              key: const Key('askodoxProfileSection-settings'),
              grid: true,
              title: t('Settings & Privacy', 'సెట్టింగ్స్ & గోప్యత'),
              icon: Icons.settings_outlined,
              children: [
            AskodoxNavRow(
                key: const ValueKey('profile-location'), guide: 'screen_location',
                icon: Icons.location_on_outlined,
                title: t('Location', 'లొకేషన్'),
                subtitle: locationLabel,
                onTap: () => context.push('/location')),
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
            AskodoxNavRow(
                icon: Icons.record_voice_over_outlined,
                title: t('Voice preference', 'వాయిస్ ప్రాధాన్యత'),
                subtitle: _voiceLabel(voicePreference, te),
                onTap: () => _pickVoicePreference(te)),
            AskodoxNavRow(
                key: const ValueKey('profile-notifications'), guide: 'screen_notifications',
                icon: Icons.notifications_none_rounded,
                title: t('Notifications', 'నోటిఫికేషన్స్'),
                subtitle: t('Choose what you are told about.', 'ఏ విషయాలు తెలియజేయాలో ఎంచుకోండి.'),
                onTap: () => context.push('/settings/notifications')),
            if (ref.watch(authSessionProvider).user != null)
            AskodoxNavRow(
                key: const Key('askodoxProfileMemoryEntry'), guide: 'screen_memory',
                icon: Icons.psychology_alt_outlined,
                title: t('Memory & personalization', 'మెమరీ & వ్యక్తిగతీకరణ'),
                subtitle: t('Private; correct, delete or switch off.', 'ప్రైవేట్; సరిచేయండి, తొలగించండి లేదా ఆపండి.'),
                onTap: () => context.push('/profile/memory')),
            AskodoxNavRow(
                key: const ValueKey('profile-privacy'), guide: 'screen_privacy',
                icon: Icons.privacy_tip_outlined,
                title: t('Privacy & data', 'గోప్యత & డేటా'),
                subtitle: t('See, download or delete your data.', 'మీ డేటా చూడండి, డౌన్‌లోడ్ లేదా తొలగించండి.'),
                onTap: () => context.push('/privacy')),
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
          // Early Access label + feedback (Command Center decides who sees it).
          AskodoxNavRow(
              key: const ValueKey('profile-feedback'), guide: 'screen_feedback',
              icon: Icons.bug_report_outlined,
              title: t('Report a problem / Send feedback', 'సమస్య చెప్పండి / ఫీడ్‌బ్యాక్ పంపండి'),
              subtitle: early.active
                  ? (early.freeTrial
                      ? '${early.label} · ${t('free while in testing', 'టెస్టింగ్ సమయంలో ఉచితం')}'
                      : early.label)
                  : t('Tell us what went wrong.', 'ఏం తప్పు జరిగిందో చెప్పండి.'),
              onTap: () => context.push('/beta-feedback')),
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
          // Sign out: always the LAST item of Profile (same flow as the side
          // menu's Logout).
          if (ref.watch(authSessionProvider).user != null)
            Padding(
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
        ]),
      ),
    );
  }
}
