import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../config/theme/askodox_design_tokens.dart';
import '../../../generated/l10n/app_localizations.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('askodoxProfileScreen'),
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AskodoxDesignTokens.brandGradient,
                    boxShadow: [
                      AskodoxDesignTokens.glow(
                        AskodoxDesignTokens.violet500,
                        blur: 34,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                BrandConfig.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                BrandConfig.tagline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 24),
              _ProfileTile(
                icon: Icons.storefront_rounded,
                title: 'ASKODOX for sellers',
                subtitle: 'Create your shop and manage products, prices and stock.',
                onTap: () => context.push('/seller/login'),
                emphasized: true,
              ),
              _ProfileTile(
                icon: Icons.insights_outlined,
                title: 'Buyer insights',
                subtitle: 'Review your private, local activity summaries.',
                onTap: () => context.push('/analytics/buyer'),
              ),
              _ProfileTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Analytics privacy',
                subtitle: 'Control privacy-safe local analytics.',
                onTap: () => context.push('/analytics/privacy'),
              ),
              _ProfileTile(
                icon: Icons.shield_outlined,
                title: l.privacyCenter,
                subtitle: l.privacyIntro,
                onTap: () => context.push('/privacy'),
              ),
              _ProfileTile(
                icon: Icons.rate_review_outlined,
                title: 'Beta feedback',
                subtitle: 'Report a beta issue or share a suggestion locally.',
                onTap: () => context.push('/beta-feedback'),
              ),
              _ProfileTile(
                icon: Icons.forum_outlined,
                title: 'Communication center',
                subtitle: 'Notifications, requests, followed shops and preferences.',
                onTap: () => context.push('/communications'),
              ),
              _ProfileTile(
                icon: Icons.map_outlined,
                title: 'Location & nearby shops',
                subtitle: 'Manage saved locations, privacy and search radius.',
                onTap: () => context.push('/location'),
              ),
              const SizedBox(height: 4),
              Card(
                child: Column(
                  children: const [
                    ListTile(
                      leading: Icon(Icons.settings_outlined),
                      title: Text('Settings'),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.help_outline),
                      title: Text('Help & support'),
                    ),
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

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: emphasized ? AskodoxDesignTokens.actionGradient : null,
              color: emphasized ? null : colors.surfaceContainerHighest,
            ),
            child: Icon(
              icon,
              color: emphasized ? Colors.white : colors.primary,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
