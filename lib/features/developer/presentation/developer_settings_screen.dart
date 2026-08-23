import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/providers/backend_providers.dart';

class DeveloperSimulation {
  const DeveloperSimulation({
    this.offline = false,
    this.networkError = false,
    this.delay = Duration.zero,
  });

  final bool offline;
  final bool networkError;
  final Duration delay;

  DeveloperSimulation copyWith({
    bool? offline,
    bool? networkError,
    Duration? delay,
  }) =>
      DeveloperSimulation(
        offline: offline ?? this.offline,
        networkError: networkError ?? this.networkError,
        delay: delay ?? this.delay,
      );
}

class DeveloperSimulationNotifier extends Notifier<DeveloperSimulation> {
  @override
  DeveloperSimulation build() => const DeveloperSimulation();

  void offline(bool value) => state = state.copyWith(offline: value);
  void networkError(bool value) => state = state.copyWith(networkError: value);
  void delay(bool value) => state = state.copyWith(
        delay: value ? const Duration(seconds: 2) : Duration.zero,
      );
  void reset() => state = const DeveloperSimulation();
}

final developerSimulationProvider =
    NotifierProvider<DeveloperSimulationNotifier, DeveloperSimulation>(
  DeveloperSimulationNotifier.new,
);

class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kReleaseMode) {
      return const Scaffold(
        body: Center(child: Text('Developer settings are disabled in production.')),
      );
    }

    final sim = ref.watch(developerSimulationProvider);
    final session = ref.watch(authSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Developer settings • DEV ONLY')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<UserRole>(
            initialValue:
                session.role == UserRole.guest ? UserRole.buyer : session.role,
            decoration: const InputDecoration(labelText: 'Mock user role'),
            items: [
              UserRole.buyer,
              UserRole.seller,
              UserRole.admin,
              UserRole.superAdmin,
            ]
                .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.name),
                    ))
                .toList(),
            onChanged: (role) {
              if (role != null) {
                ref.read(authSessionProvider.notifier).setDemoRole(role);
              }
            },
          ),
          SwitchListTile(
            title: const Text('Simulate logged out'),
            value: session.status == AuthStatus.loggedOut,
            onChanged: (value) => ref.read(authSessionProvider.notifier).simulate(
                  value ? AuthStatus.loggedOut : AuthStatus.loggedIn,
                ),
          ),
          SwitchListTile(
            title: const Text('Simulate expired session'),
            value: session.status == AuthStatus.sessionExpired,
            onChanged: (value) => ref.read(authSessionProvider.notifier).simulate(
                  value ? AuthStatus.sessionExpired : AuthStatus.loggedIn,
                ),
          ),
          SwitchListTile(
            title: const Text('Simulate network error'),
            value: sim.networkError,
            onChanged:
                ref.read(developerSimulationProvider.notifier).networkError,
          ),
          SwitchListTile(
            title: const Text('Simulate offline mode'),
            value: sim.offline,
            onChanged: ref.read(developerSimulationProvider.notifier).offline,
          ),
          SwitchListTile(
            title: const Text('Simulate 2 second backend delay'),
            value: sim.delay != Duration.zero,
            onChanged: ref.read(developerSimulationProvider.notifier).delay,
          ),
          ListTile(
            title: const Text('Trigger mock sync'),
            trailing: const Icon(Icons.sync),
            onTap: () async {
              await ref.read(syncServiceProvider).sync();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock sync complete')),
                );
              }
            },
          ),
          ListTile(
            title: const Text('View submitted beta feedback'),
            trailing: const Icon(Icons.feedback_outlined),
            onTap: () => context.push('/developer/feedback'),
          ),
          ListTile(
            title: const Text('Clear local mock data'),
            trailing: const Icon(Icons.delete_outline),
            onTap: () => ref.read(localStoreProvider).clear(),
          ),
          ListTile(
            title: const Text('Reset demo data'),
            trailing: const Icon(Icons.restart_alt),
            onTap: () {
              ref.read(developerSimulationProvider.notifier).reset();
              ref.read(authSessionProvider.notifier).setDemoRole(UserRole.buyer);
            },
          ),
        ],
      ),
    );
  }
}
