import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../generated/l10n/app_localizations.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
