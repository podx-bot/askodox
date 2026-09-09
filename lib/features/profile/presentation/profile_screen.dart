import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../core/update/askodox_update_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _roles = <String>{'Buyer'};
  bool _checking = false;
  bool _installing = false;
  double? _progress;
  AskodoxUpdateInfo? _update;
  String? _message;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  String _voiceLabel(VoicePreference preference, bool te) => switch (preference) {
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
              subtitle: Text(
                te
                    ? 'ASKODOX మాట్లాడే వాయిస్‌ను ఎంచుకోండి. Automatic మీ డివైస్‌కు సరిపోయే వాయిస్‌ను ఉపయోగిస్తుంది.'
                    : 'Choose the voice ASKODOX uses. Automatic picks a compatible device voice.',
              ),
            ),
            for (final preference in VoicePreference.values)
              RadioListTile<VoicePreference>(
                value: preference,
                groupValue: current,
                title: Text(_voiceLabel(preference, te)),
                onChanged: (value) => Navigator.pop(context, value),
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
      setState(() => _message = _te ? 'Signed live buildలో update feature పనిచేస్తుంది.' : 'Updates work in signed live builds.');
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
            ? (_te ? 'మీ ASKODOX ఇప్పటికే తాజా వెర్షన్‌లో ఉంది.' : 'ASKODOX is already up to date.')
            : (_te ? 'కొత్త ASKODOX update సిద్ధంగా ఉంది.' : 'A new ASKODOX update is ready.');
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
      if (mounted) setState(() => _message = _te ? 'Android install promptను confirm చేయండి.' : 'Confirm the Android install prompt.');
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
    String t(String en, String telugu) => te ? telugu : en;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          const CircleAvatar(radius: 42, child: Icon(Icons.person_rounded, size: 42)),
          const SizedBox(height: 10),
          Text(t('Your ASKODOX profile', 'మీ ASKODOX ప్రొఫైల్'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Your roles', 'మీ పాత్రలు'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(t('One person can be a buyer, seller, service provider or more at the same time.', 'ఒకే వ్యక్తి Buyer, Seller, Service Provider లేదా ఇతర పాత్రల్లో ఒకేసారి ఉండవచ్చు.')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Buyer', 'Seller', 'Service Provider', 'Job Seeker', 'Delivery Partner'].map((role) {
                      final selected = _roles.contains(role);
                      return FilterChip(
                        selected: selected,
                        label: Text(role),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _roles.add(role);
                            } else if (_roles.length > 1) {
                              _roles.remove(role);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_roles.contains('Seller'))
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.storefront_rounded),
                title: Text(t('Seller dashboard', 'Seller dashboard')),
                subtitle: Text(t('Manage your shop, products, prices and requests.', 'మీ షాప్, ప్రోడక్ట్స్, ధరలు, requests నిర్వహించండి.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/seller/login'),
              ),
            ),
          if (_roles.contains('Delivery Partner'))
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.delivery_dining_rounded),
                title: Text(t('Delivery opportunities', 'డెలివరీ అవకాశాలు')),
                subtitle: Text(t('See nearby delivery requests you can choose to accept.', 'మీ దగ్గరలో ఉన్న delivery requests చూసి accept చేయవచ్చు.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/alerts'),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.record_voice_over_outlined, color: Color(0xFF1769FF)),
              title: Text(t('Voice preference', 'వాయిస్ ప్రాధాన్యత'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_voiceLabel(voicePreference, te)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickVoicePreference(te),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.system_update_alt_rounded, color: Color(0xFF1769FF)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('App Update', 'యాప్ అప్డేట్'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(t('Check and install the latest signed ASKODOX build without reinstalling manually.', 'Manual reinstall లేకుండా తాజా signed ASKODOX buildని చెక్ చేసి install చేయండి.')),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(_message!),
                  ],
                  if (_installing) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _progress),
                  ],
                  const SizedBox(height: 12),
                  if (_update == null)
                    FilledButton.icon(
                      onPressed: _checking ? null : _checkUpdate,
                      icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
                      label: Text(t('Check for Update', 'అప్డేట్ చెక్ చేయండి')),
                    )
                  else
                    FilledButton.icon(onPressed: _installing ? null : _install, icon: const Icon(Icons.download_rounded), label: Text(t('Download & Install', 'డౌన్‌లోడ్ & ఇన్‌స్టాల్'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(t('Location', 'లొకేషన్')), subtitle: const Text('Vuyyuru, AP'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push('/location'))),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.settings_outlined), title: Text(t('Settings', 'సెట్టింగ్స్')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push('/notification-preferences'))),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(t('Support', 'సపోర్ట్')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push('/communications'))),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t('Privacy', 'ప్రైవసీ')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push('/privacy'))),
        ],
      ),
    );
  }
}
