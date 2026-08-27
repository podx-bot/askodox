import 'package:flutter/material.dart';

import '../../../core/demo/demo_accounts.dart';
import '../../../core/help/module_faqs.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
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

  void _escalate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support request prepared. In production this will be sent to ASKODOX Support with the selected module and unresolved question.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final faqs = ModuleFaqs.forModule(_module);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Choose the area you need help with. Open a question to see a short answer.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DemoModule>(
                value: _module,
                decoration: const InputDecoration(
                  labelText: 'Help topic',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final module in DemoModule.values)
                    DropdownMenuItem(
                      value: module,
                      child: Text(_moduleName(module)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _module = value);
                },
              ),
              const SizedBox(height: 16),
              for (final faq in faqs)
                Card(
                  child: ExpansionTile(
                    title: Text(faq.question),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(faq.answer),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Still need help?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(ModuleFaqs.unresolvedMessage),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _escalate,
                        icon: const Icon(Icons.support_agent_rounded),
                        label: const Text('Ask ASKODOX Support'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
