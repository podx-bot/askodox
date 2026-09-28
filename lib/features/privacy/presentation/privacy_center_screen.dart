import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../location/application/location_controller.dart';

/// "Your privacy" in plain words, with only actions that really work:
/// download my data, forget saved places, delete my account. Details sit
/// behind "Learn more".
class PrivacyCenterScreen extends ConsumerStatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  ConsumerState<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends ConsumerState<PrivacyCenterScreen> {
  bool _busy = false;
  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  ApiRequestOptions get _auth =>
      ApiRequestOptions(timeout: const Duration(seconds: 30), authToken: ref.read(authSessionProvider).tokenPlaceholder);

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _download() async {
    setState(() => _busy = true);
    final result = await ref.read(apiClientProvider).get<Map<String, Object?>>('/api/me/export', options: _auth);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is! ApiSuccess<Map<String, Object?>>) {
      _say(_t('Could not download your data right now.', 'ఇప్పుడు మీ డేటా డౌన్‌లోడ్ కాలేదు.'));
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(result.data);
    final sections = (result.data['data'] as Map?)?.length ?? 0;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Your data', 'మీ డేటా')),
        content: Text(_t('ASKODOX has $sections kinds of records for your account. Copy them to keep or share.',
            'మీ ఖాతాకు ASKODOX వద్ద $sections రకాల రికార్డులు ఉన్నాయి. కాపీ చేసుకోండి.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('Close', 'మూసివేయండి'))),
          FilledButton(
            key: const Key('askodoxCopyMyData'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) Navigator.pop(context);
              _say(_t('Copied.', 'కాపీ అయింది.'));
            },
            child: Text(_t('Copy all', 'అన్నీ కాపీ చేయండి')),
          ),
        ],
      ),
    );
  }

  Future<void> _forgetPlaces() async {
    await ref.read(locationControllerProvider.notifier).clearSaved();
    if (mounted) _say(_t('Saved places removed from this phone.', 'సేవ్ చేసిన ప్రాంతాలు ఈ ఫోన్ నుండి తీసేశాం.'));
  }

  Future<void> _deleteAccount() async {
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('Delete your account?', 'మీ ఖాతా తొలగించాలా?')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t(
              'Your listings are removed, open requests closed and you are signed out everywhere. '
                  'Orders you already made with another person stay on record for them. This cannot be undone.',
              'మీ లిస్టింగ్‌లు తీసివేయబడతాయి, తెరిచిన అభ్యర్థనలు మూసివేయబడతాయి, అన్ని చోట్లా సైన్ అవుట్ అవుతారు. '
                  'ఇతరులతో చేసిన ఆర్డర్లు వారి కోసం రికార్డులో ఉంటాయి. దీన్ని తిరిగి పొందలేరు.',
            )),
            const SizedBox(height: 12),
            TextField(
              key: const Key('askodoxDeleteConfirmField'),
              controller: typed,
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(labelText: _t('Type DELETE to confirm', 'నిర్ధారించడానికి DELETE టైప్ చేయండి')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('Cancel', 'రద్దు'))),
            FilledButton(
              key: const Key('askodoxConfirmDelete'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
              onPressed: typed.text.trim().toUpperCase() == 'DELETE' ? () => Navigator.pop(context, true) : null,
              child: Text(_t('Delete account', 'ఖాతా తొలగించండి')),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(apiClientProvider)
        .delete<Map<String, Object?>>('/api/me?confirm=DELETE', options: _auth);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is! ApiSuccess<Map<String, Object?>>) {
      _say(_t('Could not delete the account right now. Please try again.', 'ఇప్పుడు ఖాతా తొలగించలేకపోయాం. మళ్లీ ప్రయత్నించండి.'));
      return;
    }
    // Forget the session on this phone too.
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['askodox.auth.token', 'askodox.onboarding.complete', 'askodox.profile.mobile', 'askodox.profile.name']) {
      await prefs.remove(key);
    }
    await ref.read(locationControllerProvider.notifier).clearSaved();
    await ref.read(authSessionProvider.notifier).logout();
    if (!mounted) return;
    _say(_t('Your account was deleted.', 'మీ ఖాతా తొలగించబడింది.'));
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authSessionProvider).user != null;
    Widget promise(String text) => ListTile(
          dense: true,
          leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF1B8A3B)),
          title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(_t('Your privacy', 'మీ ప్రైవసీ'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          promise(_t('Exact location stays private', 'మీ ఖచ్చితమైన లొకేషన్ ప్రైవేట్‌గా ఉంటుంది')),
          promise(_t('Contact information is protected', 'మీ కాంటాక్ట్ వివరాలు సురక్షితం')),
          promise(_t('ASKODOX shares only what is needed for the request',
              'అభ్యర్థనకు అవసరమైనంత మాత్రమే ASKODOX పంచుకుంటుంది')),
          ExpansionTile(
            key: const Key('askodoxPrivacyLearnMore'),
            title: Text(_t('Learn more', 'మరింత తెలుసుకోండి')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t(
                '• Sellers see your area, never your exact location.\n'
                    '• Your phone number is shared only after you and the other person accept a request.\n'
                    '• ASKODOX keeps your requests, listings and orders to run them, and orders stay on record for the other person.\n'
                    '• Your chosen location is saved only on this phone.',
                '• విక్రేతలకు మీ ప్రాంతం మాత్రమే కనిపిస్తుంది, ఖచ్చితమైన లొకేషన్ కాదు.\n'
                    '• మీరు, అవతలి వ్యక్తి అభ్యర్థనను అంగీకరించిన తర్వాతే మీ ఫోన్ నంబర్ పంచుకోబడుతుంది.\n'
                    '• అభ్యర్థనలు, లిస్టింగ్‌లు, ఆర్డర్లు నడపడానికి ASKODOX వాటిని ఉంచుతుంది; ఆర్డర్లు అవతలి వ్యక్తి కోసం రికార్డులో ఉంటాయి.\n'
                    '• మీరు ఎంచుకున్న లొకేషన్ ఈ ఫోన్‌లో మాత్రమే సేవ్ అవుతుంది.',
              )),
            ],
          ),
          const Divider(),
          ListTile(
            key: const Key('askodoxForgetPlaces'),
            leading: const Icon(Icons.location_off_outlined),
            title: Text(_t('Forget saved places on this phone', 'ఈ ఫోన్‌లో సేవ్ చేసిన ప్రాంతాలు మర్చిపోండి')),
            onTap: _busy ? null : _forgetPlaces,
          ),
          if (signedIn) ...[
            ListTile(
              key: const Key('askodoxDownloadMyData'),
              leading: const Icon(Icons.download_outlined),
              title: Text(_t('Download my data', 'నా డేటా డౌన్‌లోడ్')),
              onTap: _busy ? null : _download,
            ),
            ListTile(
              key: const Key('askodoxDeleteAccount'),
              leading: const Icon(Icons.delete_forever_outlined, color: Color(0xFFB3261E)),
              title: Text(_t('Delete my account', 'నా ఖాతా తొలగించండి'), style: const TextStyle(color: Color(0xFFB3261E))),
              onTap: _busy ? null : _deleteAccount,
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
