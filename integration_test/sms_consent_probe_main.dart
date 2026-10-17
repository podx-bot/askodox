import 'package:flutter/material.dart';
import 'package:podx/core/auth/sms_code_listener.dart';

/// Emulator probe app for the REAL Android SMS User Consent path (CI workflow
/// sms-consent-e2e builds it with `-t`). Prints each event to logcat; after a
/// code / denial / timeout it listens again for the next SMS. Test-only: it is
/// never part of the ASKODOX app build.
void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _source = AndroidSmsUserConsent.instance;
  String _last = 'starting';

  @override
  void initState() {
    super.initState();
    _source.events.listen((event) {
      debugPrint('ASKODOX_SMS_EVENT ${event.event} ${event.code ?? ''}'.trim());
      if (mounted) setState(() => _last = event.event);
      if (event.event == 'code' || event.event == 'denied' || event.event == 'timeout') _start();
    });
    _start();
  }

  void _start() => _source.start().then((ok) => debugPrint('ASKODOX_SMS_START $ok'));

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('SMS consent probe: $_last')));
}
