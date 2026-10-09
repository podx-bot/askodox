import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/domain/active_role.dart';

/// Profile -> My Roles: ONE personal identity (edited once, in Profile) and
/// the sections each role adds. Buyer, Seller, Service provider and Service
/// taker (someone seeking services or jobs). Nothing is duplicated per role:
/// every tile opens the one real screen for it.
class MyRolesScreen extends ConsumerWidget {
  const MyRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final owned = ref.watch(askodoxRoleProvider).owned;
    final roles = <({String id, String title, bool holds, List<({String key, String label, IconData icon, String route})> tiles})>[
      (
        id: 'buyer',
        title: t('Buyer', 'కొనుగోలుదారు'),
        holds: owned.contains(AskodoxUserRole.buyer),
        tiles: [
          (key: 'orders', label: t('My orders', 'నా ఆర్డర్లు'), icon: Icons.receipt_long_outlined, route: '/orders/mine'),
          (key: 'memory', label: t('My needs (remembered)', 'నా అవసరాలు'), icon: Icons.psychology_alt_outlined,
              route: '/profile/memory'),
        ],
      ),
      (
        id: 'service_taker',
        title: t('Service taker (services / jobs)', 'సేవ / ఉద్యోగం కోరేవారు'),
        holds: owned.contains(AskodoxUserRole.buyer) || owned.contains(AskodoxUserRole.jobSeeker),
        tiles: [
          (key: 'requests', label: t('My requests & replies', 'నా అభ్యర్థనలు'), icon: Icons.forum_outlined,
              route: '/deals'),
          (key: 'memory', label: t('Services / jobs I need', 'నాకు కావలసిన సేవలు / ఉద్యోగాలు'),
              icon: Icons.psychology_alt_outlined, route: '/profile/memory'),
        ],
      ),
      (
        id: 'seller',
        title: t('Seller', 'విక్రేత'),
        holds: owned.contains(AskodoxUserRole.seller),
        tiles: [
          (key: 'business', label: t('My Business', 'నా వ్యాపారం'), icon: Icons.storefront_rounded, route: '/business'),
          (key: 'listings', label: t('My listings', 'నా లిస్టింగ్‌లు'), icon: Icons.inventory_2_outlined,
              route: '/listings/mine'),
        ],
      ),
      (
        id: 'service_provider',
        title: t('Service provider', 'సేవ అందించేవారు'),
        holds: owned.contains(AskodoxUserRole.serviceProvider),
        tiles: [
          (key: 'business', label: t('My Business', 'నా వ్యాపారం'), icon: Icons.storefront_rounded, route: '/business'),
          (key: 'opportunities', label: t('New demand near me', 'దగ్గరలో కొత్త డిమాండ్'), icon: Icons.campaign_outlined,
              route: '/opportunities'),
        ],
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('My roles', 'నా పాత్రలు'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Card(
            elevation: 0,
            child: ListTile(
              key: const Key('askodoxRolesPersonal'),
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(t('Personal profile', 'వ్యక్తిగత ప్రొఫైల్')),
              subtitle: Text(t('Your name, photo, language and address -- one identity for every role.',
                  'పేరు, ఫోటో, భాష, చిరునామా -- అన్ని పాత్రలకు ఒకే గుర్తింపు.')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go('/profile'),
            ),
          ),
          for (final role in roles) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Row(children: [
                Expanded(
                  child: Text(role.title,
                      key: ValueKey('askodoxRole-${role.id}'), style: Theme.of(context).textTheme.titleSmall),
                ),
                if (!role.holds)
                  TextButton(
                    key: ValueKey('askodoxRoleAdd-${role.id}'),
                    onPressed: () => context.go('/profile'),
                    child: Text(t('Add this role in Profile', 'ప్రొఫైల్‌లో ఈ పాత్ర జోడించండి')),
                  ),
              ]),
            ),
            if (role.holds)
              for (final tile in role.tiles)
                Card(
                  elevation: 0,
                  child: ListTile(
                    key: ValueKey('askodoxRoleTile-${role.id}-${tile.key}'),
                    leading: Icon(tile.icon),
                    title: Text(tile.label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(tile.route),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
