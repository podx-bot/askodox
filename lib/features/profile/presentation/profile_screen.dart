import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/update/askodox_update_service.dart';
import '../../../generated/l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AskodoxUpdateService _updateService = const AskodoxUpdateService();

  AskodoxUpdateInfo? _updateInfo;
  bool _checkingUpdate = false;
  bool _installingUpdate = false;
  double? _updateProgress;
  String? _updateMessage;

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate || _installingUpdate) return;

    if (!AskodoxUpdateService.enabled) {
      setState(() {
        _updateInfo = null;
        _updateMessage = 'In-app updates are enabled in signed release builds.';
      });
      return;
    }

    setState(() {
      _checkingUpdate = true;
      _updateMessage = null;
    });

    final info = await _updateService.checkForUpdate();
    if (!mounted) return;

    setState(() {
      _checkingUpdate = false;
      _updateInfo = info;
      _updateMessage = info == null
          ? 'ASKODOX is up to date.'
          : 'ASKODOX ${info.version} is ready to install.';
    });
  }

  Future<void> _installUpdate() async {
    final info = _updateInfo;
    if (info == null || _installingUpdate) return;

    setState(() {
      _installingUpdate = true;
      _updateProgress = 0;
      _updateMessage = 'Downloading update…';
    });

    try {
      await _updateService.downloadAndInstall(
        info,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _updateProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _installingUpdate = false;
        _updateMessage = 'Update downloaded. Confirm the Android install prompt to finish.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installingUpdate = false;
        _updateProgress = null;
        _updateMessage = 'Update could not be installed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isTe = Localizations.localeOf(context).languageCode == 'te';

    String t(String en, String te) => isTe ? te : en;

    return Scaffold(
      appBar: AppBar(title: Text(t('Profile', 'ప్రొఫైల్'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: Icon(Icons.storefront, size: 34, color: Theme.of(context).colorScheme.primary),
                  title: Text(t('ASKODOX for sellers', 'విక్రేతల కోసం ASKODOX'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(t(
                    'Create your shop and manage products, prices and stock.',
                    'మీ షాప్‌ను సృష్టించి ఉత్పత్తులు, ధరలు, స్టాక్‌ను నిర్వహించండి.',
                  )),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/seller/login'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.system_update_alt_rounded),
                        title: Text(t('App update', 'యాప్ అప్‌డేట్')),
                        subtitle: Text(t(
                          'Check and install the latest signed ASKODOX build from inside the app.',
                          'యాప్ నుంచే తాజా signed ASKODOX build‌ను చెక్ చేసి ఇన్‌స్టాల్ చేయండి.',
                        )),
                        trailing: _checkingUpdate
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : IconButton(
                                tooltip: t('Check for updates', 'అప్‌డేట్ చెక్ చేయండి'),
                                onPressed: _checkForUpdate,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                      ),
                      if (_updateMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(_updateMessage!, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      if (_installingUpdate) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: _updateProgress),
                        const SizedBox(height: 6),
                        Text(
                          _updateProgress == null
                              ? t('Downloading…', 'డౌన్‌లోడ్ అవుతోంది…')
                              : '${(_updateProgress! * 100).round()}%',
                          textAlign: TextAlign.right,
                        ),
                      ],
                      if (_updateInfo != null && !_installingUpdate) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _installUpdate,
                          icon: const Icon(Icons.download_done_rounded),
                          label: Text(t('Download & install update', 'అప్‌డేట్ డౌన్‌లోడ్ చేసి ఇన్‌స్టాల్ చేయండి')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: Text(t('Buyer insights', 'కొనుగోలుదారుల విశ్లేషణలు')),
                  subtitle: Text(t('Review your private, local activity summaries.', 'మీ వ్యక్తిగత లోకల్ యాక్టివిటీ సమరీలను చూడండి.')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/analytics/buyer'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(t('Analytics privacy', 'అనలిటిక్స్ గోప్యత')),
                  subtitle: Text(t('Control privacy-safe local analytics.', 'గోప్యతను కాపాడే లోకల్ అనలిటిక్స్‌ను నియంత్రించండి.')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/analytics/privacy'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l.privacyCenter),
                  subtitle: Text(l.privacyIntro),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: Text(t('Beta feedback', 'బీటా ఫీడ్‌బ్యాక్')),
                  subtitle: Text(t('Report a beta issue or share a suggestion locally.', 'బీటా సమస్యను రిపోర్ట్ చేయండి లేదా సూచనను షేర్ చేయండి.')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/beta-feedback'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(t('Communication center', 'కమ్యూనికేషన్ కేంద్రం')),
                  subtitle: Text(t(
                    'Notifications, product requests, followed shops and preferences.',
                    'నోటిఫికేషన్లు, ఉత్పత్తి అభ్యర్థనలు, ఫాలో అవుతున్న షాపులు మరియు ప్రాధాన్యతలు.',
                  )),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/communications'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(t('Location & nearby shops', 'లొకేషన్ & దగ్గరలోని షాపులు')),
                  subtitle: Text(t(
                    'Manage saved locations, privacy and search radius.',
                    'సేవ్ చేసిన లొకేషన్లు, గోప్యత మరియు సెర్చ్ పరిధిని నిర్వహించండి.',
                  )),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/location'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(leading: const Icon(Icons.settings_outlined), title: Text(t('Settings', 'సెట్టింగ్స్'))),
                    const Divider(height: 1),
                    ListTile(leading: const Icon(Icons.help_outline), title: Text(t('Help & support', 'సహాయం & సపోర్ట్'))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
