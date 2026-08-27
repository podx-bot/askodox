import 'package:flutter/material.dart';

import '../../../core/demo/demo_accounts.dart';
import '../../../core/demo/demo_state.dart';

class DemoCenterScreen extends StatefulWidget {
  const DemoCenterScreen({super.key});

  @override
  State<DemoCenterScreen> createState() => _DemoCenterScreenState();
}

class _DemoCenterScreenState extends State<DemoCenterScreen> {
  DemoModule _module = DemoModule.commerce;

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

  @override
  Widget build(BuildContext context) {
    final accounts = DemoAccounts.forModule(_module);
    final records = DemoRuntime.state.forModule(_module);

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
                  child: ListTile(
                    leading: CircleAvatar(child: Text(account.party == DemoParty.a ? 'A' : 'B')),
                    title: Text('${account.party == DemoParty.a ? 'Party A' : 'Party B'} · ${account.displayName}'),
                    subtitle: SelectableText('${account.loginId}\n${account.location}\n${account.sampleIntent}'),
                    isThreeLine: true,
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
