import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: ListView(padding: const EdgeInsets.all(20), children: [
      const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
      const SizedBox(height: 24),
      Card(child: ListTile(contentPadding: const EdgeInsets.all(18), leading: Icon(Icons.storefront, size: 34, color: Theme.of(context).colorScheme.primary), title: const Text('PODX for sellers', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Create your shop and manage products, prices and stock.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/seller/login'))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.insights_outlined), title: const Text('Buyer insights'), subtitle: const Text('Review your private, local activity summaries.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/analytics/buyer'))),
      Card(child: ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Analytics privacy'), subtitle: const Text('Control privacy-safe local analytics.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/analytics/privacy'))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.forum_outlined), title: const Text('Communication center'), subtitle: const Text('Notifications, product requests, followed shops and preferences.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/communications'))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.map_outlined), title: const Text('Location & nearby shops'), subtitle: const Text('Manage saved locations, privacy and search radius.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/location'))),
      const SizedBox(height: 12),
      const Card(child: Column(children: [ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings')), Divider(height: 1), ListTile(leading: Icon(Icons.help_outline), title: Text('Help & support'))])),
    ]))),
  );
}
