import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/askodox_update_service.dart';
import '../pos/data/pos_payment_alerts.dart';
import '../pos/data/pos_repository.dart';
import 'phone_health.dart';

/// ఫోన్ ఆరోగ్యం (owner 2026-11-26): check -> fix one by one on the phone maker's own page -> (only if the person
/// presses "పంపు") a report to ASKODOX. The app looks at its OWN settings only and never taps a setting itself.
class AskodoxPhoneHealthScreen extends ConsumerStatefulWidget {
  const AskodoxPhoneHealthScreen({super.key, this.why = 'user_asked'});

  /// payment_voice_missing | setup_stuck | user_asked -- why the screen was opened (sent only with a report).
  final String why;

  @override
  ConsumerState<AskodoxPhoneHealthScreen> createState() => _AskodoxPhoneHealthScreenState();
}

class _AskodoxPhoneHealthScreenState extends ConsumerState<AskodoxPhoneHealthScreen> with WidgetsBindingObserver {
  List<AskodoxPhoneCheck>? _checks;
  String _maker = '';
  bool _onPhone = true;
  bool _sending = false;
  String? _sent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings page: look again, so a fixed line turns green by itself.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final status = await ref.read(askodoxPaymentAlertsBridgeProvider).status();
    if (!mounted) return;
    setState(() {
      _onPhone = status['unavailable'] != true;
      _maker = '${status['maker'] ?? ''}';
      _checks = askodoxPhoneChecks(status);
    });
  }

  Future<void> _fix(AskodoxPhoneCheck check) async {
    final bridge = ref.read(askodoxPaymentAlertsBridgeProvider);
    switch (check.fix) {
      case 'notifications':
        await bridge.openAppNotificationSettings();
      case 'battery':
        await bridge.openBatterySettings();
      case 'autostart':
        await bridge.openAutostartSettings();
      case 'access':
        await bridge.openListenerSettings();
      case 'voice':
        await bridge.installOfflineVoice();
    }
  }

  Future<void> _send(bool te) async {
    final checks = _checks ?? const <AskodoxPhoneCheck>[];
    if (checks.isEmpty || _sending) return;
    final agreed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              key: const Key('askodoxPhoneHealthConsent'),
              title: Text(te ? 'ASKODOX కి పంపాలా?' : 'Send to ASKODOX?'),
              content: Text(te
                  ? 'పంపేది ఇంతే: ఫోన్ కంపెనీ పేరు, app వెర్షన్, పైన కనిపించే లైన్లు సరిగా ఉన్నాయా లేదా. '
                      'మీ messages, photos, వేరే apps ఏవీ వెళ్ళవు. మీరు "పంపు" నొక్కితేనే వెళ్తుంది.'
                  : 'Only this is sent: the phone maker, the app version, and whether each line above is fine. '
                      'No messages, photos or other apps. It goes only when you press Send.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(te ? 'వద్దు' : 'No')),
                FilledButton(
                    key: const Key('askodoxPhoneHealthSendYes'),
                    onPressed: () => Navigator.of(dialog).pop(true),
                    child: Text(te ? 'పంపు' : 'Send')),
              ],
            ));
    if (agreed != true || !mounted) return;
    setState(() => _sending = true);
    String message;
    try {
      await ref.read(askodoxPosRepositoryProvider).phoneHealthReport(askodoxPhoneReport(checks,
          maker: _maker, appBuild: AskodoxUpdateService.compiledBuildNumber, why: widget.why));
      message = te ? 'పంపాం. మా team చూసి సాయం చేస్తుంది.' : 'Sent. Our team will look and help.';
    } on AskodoxPosException catch (e) {
      message = e.kind == 'sign_in'
          ? (te ? 'పంపడానికి ముందు సైన్ ఇన్ అవ్వండి.' : 'Sign in first to send.')
          : e.message(te);
    } catch (_) {
      message = te ? 'పంపలేకపోయాం. ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి.' : 'Could not send. Check the internet and try again.';
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final checks = _checks;
    final toFix = checks == null ? 0 : checks.where((c) => c.state == 'bad').length;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఫోన్ ఆరోగ్యం' : 'Phone health')),
      body: checks == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text(
                  !_onPhone
                      ? (te ? 'ఈ check Android ఫోన్ లో మాత్రమే పనిచేస్తుంది.' : 'This check works on an Android phone only.')
                      : toFix == 0
                          ? (te ? 'అన్నీ సరిగా ఉన్నాయి.' : 'Everything is fine.')
                          : (te ? '$toFix సరిచేయాలి. ఒక్కొక్కటి నొక్కండి.' : '$toFix to fix. Tap them one by one.'),
                  key: const Key('askodoxPhoneHealthSummary'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  te
                      ? 'ASKODOX తన సొంత settings మాత్రమే చూస్తుంది. వేరే apps, messages, photos చూడదు.'
                      : 'ASKODOX looks at its own settings only. Never other apps, messages or photos.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final c in checks) _row(context, c, te),
              if (checks.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    key: const Key('askodoxPhoneHealthAgain'),
                    onPressed: _check,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(te ? 'మళ్ళీ check చేయి' : 'Check again')),
                const SizedBox(height: 8),
                FilledButton.icon(
                    key: const Key('askodoxPhoneHealthSend'),
                    onPressed: _sending ? null : () => _send(te),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(te ? 'ఇంకా సమస్య ఉంది: ASKODOX కి report పంపు' : 'Still a problem: send a report to ASKODOX')),
                if (_sent != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_sent!, key: const Key('askodoxPhoneHealthSent'), textAlign: TextAlign.center),
                  ),
              ],
            ]),
    );
  }

  Widget _row(BuildContext context, AskodoxPhoneCheck check, bool te) {
    final (name, what) = askodoxPhoneCheckText(check.id, te: te);
    final steps = askodoxPhoneFixSteps(check.fix, _maker, te: te);
    final (icon, color) = switch (check.state) {
      'ok' => (Icons.check_circle_rounded, const Color(0xFF75D48B)),
      'bad' => (Icons.error_rounded, const Color(0xFFFEA293)),
      _ => (Icons.help_rounded, const Color(0xFFFB9E6A)),
    };
    return Card(
      key: ValueKey('askodoxPhoneCheck-${check.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          if (check.needsLook) ...[
            const SizedBox(height: 4),
            Text(what),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(steps, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              FilledButton.tonal(
                  key: ValueKey('askodoxPhoneFix-${check.id}'),
                  onPressed: () => _fix(check),
                  child: Text(te ? 'ఆ page తెరువు' : 'Open that page')),
            ],
          ],
        ]),
      ),
    );
  }
}
