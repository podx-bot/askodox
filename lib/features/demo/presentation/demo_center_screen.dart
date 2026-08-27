import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/demo_accounts.dart';
import '../../../core/demo/demo_state.dart';
import '../../../core/providers/backend_providers.dart';

class DemoCenterScreen extends ConsumerStatefulWidget {
  const DemoCenterScreen({super.key});

  @override
  ConsumerState<DemoCenterScreen> createState() => _DemoCenterScreenState();
}

class _DemoCenterScreenState extends ConsumerState<DemoCenterScreen> {
  DemoModule _module = DemoModule.commerce;
  bool _switching = false;

  String _moduleName(DemoModule module) => switch (module) {
        DemoModule.commerce => 'Buy & Sell',
        DemoModule.jobs => 'Jobs',
        DemoModule.services => 'Services',
        DemoModule.rides => 'Rides',
        DemoModule.parcel => 'Parcel Delivery',
        DemoModule.appointments => 'Appointments',
        DemoModule.catering => 'Catering',
        DemoModule.localDiscovery => 'Local Discovery',
      };

  void _reset() {
    DemoRuntime.state.reset();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Demo data reset to the default seed state.')),
    );
  }

  Future<void> _enterAs(DemoAccount account) async {
    if (_switching) return;
    setState(() => _switching = true);
    await ref.read(authSessionProvider.notifier).setDemoAccount(account);
    if (!mounted) return;
    setState(() => _switching = false);
    if (account.role.name == 'seller') {
      context.go('/seller/dashboard');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = DemoAccounts.forModule(_module);
    final records = DemoRuntime.state.forModule(_module);
    final session = ref.watch(authSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ASKODOX Demo Center')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DEMO ONLY', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Use these fixed accounts for testing, tutorials, How to Use videos and FAQ demos. They must never be used for real payments or real customer leads.'),
                      const SizedBox(height: 12),
                      SelectableText('Common demo password: ${DemoAccounts.demoPassword}'),
                      if (session.tokenPlaceholder == 'DEMO_ONLY' && session.user != null) ...[
                        const SizedBox(height: 10),
                        Text('Current demo session: ${session.user!.displayName ?? session.user!.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DemoModule>(
                value: _module,
                decoration: const InputDecoration(labelText: 'Demo module', border: OutlineInputBorder()),
                items: [
                  for (final module in DemoModule.values)
                    DropdownMenuItem(value: module, child: Text(_moduleName(module))),
                ],
                onChanged: (value) => value == null ? null : setState(() => _module = value),
              ),
              const SizedBox(height: 16),
              for (final account in accounts) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(child: Text(account.party == DemoParty.a ? 'A' : 'B')),
                          title: Text('${account.party == DemoParty.a ? 'Party A' : 'Party B'} · ${account.displayName}'),
                          subtitle: SelectableText('${account.loginId}\n${account.location}\n${account.sampleIntent}'),
                          isThreeLine: true,
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _switching ? null : () => _enterAs(account),
                            icon: const Icon(Icons.login_rounded),
                            label: Text('Enter as ${account.party == DemoParty.a ? 'Party A' : 'Party B'}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Seed activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final record in records)
                Card(
                  child: ListTile(
                    leading: Icon(record.party == DemoParty.a ? Icons.storefront_outlined : Icons.person_search_outlined),
                    title: Text(record.title),
                    subtitle: Text('${record.type.name} · ${record.status}'),
                    trailing: Text(record.party == DemoParty.a ? 'A' : 'B'),
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset all demo data'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
