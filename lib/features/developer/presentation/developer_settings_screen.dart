import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeveloperSettingsScreen extends StatelessWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Developer settings are unavailable.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Developer settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('ASKODOX debug tools'),
              subtitle: Text('Debug-only diagnostics and test utilities.'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync status'),
            onTap: () => context.push('/sync-status'),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Storage usage'),
            onTap: () => context.push('/storage-usage'),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Performance monitor'),
            onTap: () => context.push('/performance-monitor'),
          ),
        ],
      ),
    );
  }
}
