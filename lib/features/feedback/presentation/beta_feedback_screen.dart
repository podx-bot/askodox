import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/flags/askodox_remote_flags.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../staff/askodox_staff_access.dart';
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
  bool _shareDiagnostics = false;
  bool _sending = false;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  String _categoryLabel(FeedbackCategory value) => switch (value) {
        FeedbackCategory.bug => _t('Bug', 'బగ్'),
        FeedbackCategory.feature => _t('Feature', 'ఫీచర్'),
        FeedbackCategory.ui => _t('UI', 'యూజర్ ఇంటర్‌ఫేస్'),
        FeedbackCategory.search => _t('Search', 'సెర్చ్'),
        FeedbackCategory.price => _t('Price', 'ధర'),
        FeedbackCategory.seller => _t('Seller', 'సెల్లర్'),
        FeedbackCategory.performance => _t('Performance', 'పనితీరు'),
        FeedbackCategory.other => _t('Other', 'ఇతర'),
      };

  String _severityLabel(FeedbackSeverity value) => switch (value) {
        FeedbackSeverity.low => _t('Low', 'తక్కువ'),
        FeedbackSeverity.medium => _t('Medium', 'మధ్యస్థ'),
        FeedbackSeverity.high => _t('High', 'ఎక్కువ'),
        FeedbackSeverity.blocking => _t('Blocking', 'పూర్తిగా అడ్డుకుంటోంది'),
      };

  @override
  void dispose() {
    _description.dispose();
    _screen.dispose();
    _screenshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_t('Report a problem / Send feedback', 'సమస్య చెప్పండి / ఫీడ్‌బ్యాక్'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(_t(
                    'Sent to the ASKODOX team. Do not include passwords, OTPs, card or Aadhaar numbers -- they are hidden automatically.',
                    'ASKODOX టీమ్‌కి పంపబడుతుంది. పాస్‌వర్డ్‌లు, OTPలు, కార్డ్ లేదా ఆధార్ నంబర్లు వద్దు -- అవి ఆటోమేటిక్‌గా దాచబడతాయి.',
                  )),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<FeedbackCategory>(
                    initialValue: _category,
                    decoration: InputDecoration(labelText: _t('Category', 'కేటగిరీ')),
                    items: FeedbackCategory.values
                        .map((value) => DropdownMenuItem(value: value, child: Text(_categoryLabel(value))))
                        .toList(),
                    onChanged: (value) => setState(() => _category = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration: InputDecoration(labelText: _t('Description', 'వివరణ')),
                    maxLength: 2000,
                    minLines: 4,
                    maxLines: 8,
                    validator: (value) => value == null || value.trim().length < 10
                        ? _t('Enter at least 10 characters.', 'కనీసం 10 అక్షరాలు నమోదు చేయండి.')
                        : null,
                  ),
                  TextFormField(
                    controller: _screen,
                    decoration: InputDecoration(labelText: _t('Screen name', 'స్క్రీన్ పేరు')),
                    maxLength: 100,
                  ),
                  DropdownButtonFormField<FeedbackSeverity>(
                    initialValue: _severity,
                    decoration: InputDecoration(labelText: _t('Severity', 'తీవ్రత')),
                    items: FeedbackSeverity.values
                        .map((value) => DropdownMenuItem(value: value, child: Text(_severityLabel(value))))
                        .toList(),
                    onChanged: (value) => setState(() => _severity = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _screenshot,
                    decoration: InputDecoration(
                      labelText: _t('Screenshot reference (optional)', 'స్క్రీన్‌షాట్ రిఫరెన్స్ (ఐచ్చికం)'),
                    ),
                    maxLength: 200,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Allow the beta team to contact me', 'బీటా టీమ్ నన్ను సంప్రదించడానికి అనుమతించండి')),
                    value: _contactAllowed,
                    onChanged: (value) => setState(() => _contactAllowed = value),
                  ),
                  SwitchListTile(
                    key: const ValueKey('feedback-diagnostics'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Include app version and screen name', 'యాప్ వెర్షన్, స్క్రీన్ పేరు జత చేయండి')),
                    subtitle: Text(_t('No messages, contacts, location or payment details.',
                        'మెసేజ్‌లు, కాంటాక్ట్స్, లొకేషన్, పేమెంట్ వివరాలు ఉండవు.')),
                    value: _shareDiagnostics,
                    onChanged: (value) => setState(() => _shareDiagnostics = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: const Icon(Icons.send),
                    label: Text(_t('Submit feedback', 'ఫీడ్‌బ్యాక్ పంపండి')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  static String _kind(FeedbackCategory category) => switch (category) {
        FeedbackCategory.bug || FeedbackCategory.performance || FeedbackCategory.ui => 'bug',
        FeedbackCategory.search || FeedbackCategory.price || FeedbackCategory.seller => 'wrong_result',
        FeedbackCategory.feature => 'idea',
        FeedbackCategory.other => 'other',
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    setState(() => _sending = true);
    String? reference;
    try {
      final version = '${await const AskodoxUpdateService().installedBuildNumber()}';
      reference = await ref.read(askodoxStaffRepositoryProvider).sendFeedback(
            kind: _kind(_category),
            message: '[${_severity.name}] ${_description.text.trim()}',
            feature: _screen.text.trim().isEmpty ? _category.name : _screen.text.trim(),
            appVersion: version,
            installId: await ref.read(askodoxFlagsRepositoryProvider).installId(),
            consentDiagnostics: _shareDiagnostics,
            diagnostics: {'screen': _screen.text.trim(), 'build': version},
            token: ref.read(authSessionProvider).tokenPlaceholder,
          );
    } catch (_) {
      reference = null;
    }
    if (!mounted) return;
    setState(() => _sending = false);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(reference != null
              ? _t('Sent to the ASKODOX team. Thank you!', 'ASKODOX టీమ్‌కి పంపాం. ధన్యవాదాలు!')
              : _t('Could not send right now -- please try again when you are online.',
                  'ఇప్పుడు పంపలేకపోయాం -- ఆన్‌లైన్‌లో ఉన్నప్పుడు మళ్లీ ప్రయత్నించండి.'))),
    );
  }
}

class SubmittedFeedbackScreen extends ConsumerWidget {
  const SubmittedFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    final feedback = ref.watch(betaFeedbackProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Submitted beta feedback • DEV ONLY', 'పంపిన బీటా ఫీడ్‌బ్యాక్ • DEV ONLY'))),
      body: feedback.isEmpty
          ? Center(child: Text(t('No feedback has been submitted on this run.', 'ఈ రన్‌లో ఇంకా ఫీడ్‌బ్యాక్ పంపలేదు.')))
          : ListView.builder(
              itemCount: feedback.length,
              itemBuilder: (context, index) {
                final item = feedback[index];
                return ListTile(
                  title: Text(item.category.name),
                  subtitle: Text(item.description),
                  trailing: Text(item.severity.name),
                );
              },
            ),
    );
  }
}
