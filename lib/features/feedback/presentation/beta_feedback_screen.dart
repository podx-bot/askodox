import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/beta_feedback_provider.dart';
import '../domain/beta_feedback.dart';

class BetaFeedbackScreen extends ConsumerStatefulWidget {
  const BetaFeedbackScreen({super.key});

  @override
  ConsumerState<BetaFeedbackScreen> createState() => _BetaFeedbackScreenState();
}

class _BetaFeedbackScreenState extends ConsumerState<BetaFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _screen = TextEditingController();
  final _screenshot = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.bug;
  FeedbackSeverity _severity = FeedbackSeverity.medium;
  bool _contactAllowed = false;

  @override
  void dispose() {
    _description.dispose();
    _screen.dispose();
    _screenshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Beta feedback')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('Stored on this device only. Do not include passwords, OTPs, or personal information.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField(
                    value: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: FeedbackCategory.values.map((value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                    onChanged: (value) => setState(() => _category = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLength: 2000,
                    minLines: 4,
                    maxLines: 8,
                    validator: (value) => value == null || value.trim().length < 10 ? 'Enter at least 10 characters.' : null,
                  ),
                  TextFormField(controller: _screen, decoration: const InputDecoration(labelText: 'Screen name'), maxLength: 100),
                  DropdownButtonFormField(
                    value: _severity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: FeedbackSeverity.values.map((value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                    onChanged: (value) => setState(() => _severity = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _screenshot, decoration: const InputDecoration(labelText: 'Screenshot reference (optional)'), maxLength: 200),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow the beta team to contact me'),
                    value: _contactAllowed,
                    onChanged: (value) => setState(() => _contactAllowed = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Submit feedback')),
                ],
              ),
            ),
          ),
        ),
      );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    ref.read(betaFeedbackProvider.notifier).submit(BetaFeedback(
          id: now.microsecondsSinceEpoch.toString(),
          category: _category,
          description: _description.text.trim(),
          screenName: _screen.text.trim(),
          severity: _severity,
          screenshotReference: _screenshot.text.trim().isEmpty ? null : _screenshot.text.trim(),
          contactAllowed: _contactAllowed,
          submittedAt: now,
        ));
    _description.clear();
    _screen.clear();
    _screenshot.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback saved locally. Thank you.')));
  }
}

class SubmittedFeedbackScreen extends ConsumerWidget {
  const SubmittedFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final feedback = ref.watch(betaFeedbackProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Submitted beta feedback • DEV ONLY')),
      body: feedback.isEmpty
          ? const Center(child: Text('No feedback has been submitted on this run.'))
          : ListView.builder(
              itemCount: feedback.length,
              itemBuilder: (context, index) {
                final item = feedback[index];
                return ListTile(title: Text(item.category.name), subtitle: Text(item.description), trailing: Text(item.severity.name));
              },
            ),
    );
  }
}
