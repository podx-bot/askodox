import 'package:flutter/material.dart';

class AuthMessageScreen extends StatelessWidget {
  const AuthMessageScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(_localizedTitle(te, title))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(_localizedMessage(te, message), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(te ? 'వెనక్కి వెళ్లండి' : 'Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localizedTitle(bool te, String value) {
    if (!te) return value;
    return switch (value) {
      'Page not found' => 'పేజీ కనబడలేదు',
      'Sign in required' => 'సైన్ ఇన్ అవసరం',
      'Session expired' => 'సెషన్ ముగిసింది',
      'Account suspended' => 'అకౌంట్ నిలిపివేయబడింది',
      'Access denied' => 'యాక్సెస్ నిరాకరించబడింది',
      _ => value,
    };
  }

  String _localizedMessage(bool te, String value) {
    if (!te) return value;
    if (value.startsWith('This link is unavailable or no longer exists.')) {
      final pathStart = value.indexOf('(');
      final path = pathStart >= 0 ? value.substring(pathStart) : '';
      return 'ఈ లింక్ అందుబాటులో లేదు లేదా ఇక లేదు. $path';
    }
    return switch (value) {
      'Choose a demo role in Developer settings to continue.' =>
        'కొనసాగడానికి Developer settingsలో ఒక demo role ఎంచుకోండి.',
      'Your session expired. Sign in again to continue.' =>
        'మీ సెషన్ ముగిసింది. కొనసాగడానికి మళ్లీ సైన్ ఇన్ చేయండి.',
      'This account is suspended. Contact support for help.' =>
        'ఈ అకౌంట్ నిలిపివేయబడింది. సహాయం కోసం సపోర్ట్‌ను సంప్రదించండి.',
      'Your current role cannot access this area.' =>
        'మీ ప్రస్తుత రోల్‌కు ఈ విభాగాన్ని యాక్సెస్ చేసే అనుమతి లేదు.',
      _ => value,
    };
  }
}
