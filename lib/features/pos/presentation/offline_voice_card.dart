import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart' show AskodoxJson;
import 'pos_common.dart';

/// Owner 2026-11-17: the payment voice must work with NO internet (bank SMS still arrives) in the language the person
/// chose. Shows whether this phone's own speech engine has that language offline; if not, one tap opens the phone's
/// "download voice data" page. Re-checks when the person comes back to the app.
class AskodoxOfflineVoiceCard extends ConsumerStatefulWidget {
  const AskodoxOfflineVoiceCard({super.key, required this.language});
  final String language;

  @override
  ConsumerState<AskodoxOfflineVoiceCard> createState() => _AskodoxOfflineVoiceCardState();
}

class _AskodoxOfflineVoiceCardState extends ConsumerState<AskodoxOfflineVoiceCard> with WidgetsBindingObserver {
  AskodoxJson? _state;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void didUpdateWidget(AskodoxOfflineVoiceCard old) {
    super.didUpdateWidget(old);
    if (old.language != widget.language) unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check()); // back from the download page
  }

  @override
  void dispose() {
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final s = await ref.read(askodoxPaymentAlertsBridgeProvider).offlineVoice(widget.language);
    if (!mounted) return;
    setState(() => _state = s);
    _retry?.cancel();
    if (s['ready'] == null) _retry = Timer(const Duration(seconds: 2), () => unawaited(_check())); // engine starting
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _state;
    if (s == null || s['unavailable'] == true || s['ready'] == null) return const SizedBox.shrink();
    final label = askodoxOfflineVoiceLabel(s);
    final ok = s['offline'] == true;
    return Container(
      key: const Key('askodoxOfflineVoice'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF1C3428) : const Color(0xFF3C2A0D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(ok ? Icons.offline_bolt : Icons.wifi_off, color: ok ? const Color(0xFF7CD3A2) : const Color(0xFFFB9E6A)),
        const SizedBox(width: 10),
        Expanded(child: Text(te ? label.$2 : label.$1, style: const TextStyle(fontSize: 13))),
        if (!ok && s['supported'] != false)
          TextButton(
            key: const Key('askodoxOfflineVoiceInstall'),
            onPressed: () => ref.read(askodoxPaymentAlertsBridgeProvider).installOfflineVoice(),
            child: Text(te ? 'డౌన్‌లోడ్' : 'Download'),
          ),
      ]),
    );
  }
}

/// (en, te) line for the offline voice state of the chosen language.
(String, String) askodoxOfflineVoiceLabel(AskodoxJson s) {
  if (s['offline'] == true) {
    return ('Works without internet: the phone voice for this language is on the phone.',
        'నెట్ లేకపోయినా వాయిస్ వస్తుంది: ఈ భాష ఫోన్ వాయిస్ ఫోన్‌లో ఉంది.');
  }
  if (s['supported'] == false) {
    return ("This phone's voice engine has no voice for this language: without internet the amount is said in English. "
            'Install "Speech Services by Google" from Play Store for more languages.',
        'ఈ ఫోన్ వాయిస్‌లో ఈ భాష లేదు: నెట్ లేనప్పుడు మొత్తం ఇంగ్లీష్‌లో చెప్తుంది. Play Store నుంచి "Speech Services by Google" వేస్తే ఎక్కువ భాషలు వస్తాయి.');
  }
  // Owner 2026-11-20: nothing to set up -- with internet ASKODOX's own voice speaks; without it the amount is said in
  // English (and if no voice can play, two loud beeps). Downloading the language voice is only an extra.
  return ('Nothing to set up. Without internet the amount is said in English. (Optional: Download to hear this language offline too.)',
      'ఏమీ సెట్ చేయక్కర్లేదు. నెట్ లేనప్పుడు మొత్తం ఇంగ్లీష్‌లో చెప్తుంది. (కావాలంటే "డౌన్‌లోడ్" తో ఈ భాష కూడా నెట్ లేకుండా వస్తుంది.)');
}
