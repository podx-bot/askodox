import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_payment_alerts.dart' show askodoxRupees;
import '../data/pos_repository.dart';
import 'my_payment_alerts_screen.dart' show askodoxStaffRoleLabel;

/// Owner 2026-11-18: does every phone that should hear the shop's payments really hear them?
/// ✅ working / ⚠ permission off / ⚠ phone did not answer. Android lets no app change another phone's settings,
/// so the fix is always done ON that phone: ASKODOX there shows only the one step it needs.
(String, Color) askodoxPhoneSoundState(AskodoxJson p, bool te) {
  final reason = '${p['reason'] ?? ''}';
  return switch ('${p['state']}') {
    'working' => (te ? '✅ పనిచేస్తోంది' : '✅ Working', const Color(0xFF75D48B)),
    'permission_off' => ('⚠ ${te ? 'అనుమతి ఆఫ్' : 'Permission off'}: ${askodoxPhoneSoundReason(reason, te)}', const Color(0xFFFEA195)),
    'not_answering' => (
        '⚠ ${te ? 'సౌండ్ రాలేదు' : 'Sound missed'}'
            '${p['missed_amount_paise'] is num ? ' (${askodoxRupees(p['missed_amount_paise'])})' : ''}: '
            '${askodoxPhoneSoundReason(reason, te)}',
        const Color(0xFFFEA195)
      ),
    'off' => (te ? '🔕 ఆ ఫోన్‌లో సౌండ్ ఆఫ్ చేశారు' : '🔕 Sound switched off on that phone', const Color(0xFFB1B9C8)),
    _ => (te ? '⏳ ఇంకా తెలియదు — ఒక టెస్ట్ సౌండ్ పంపండి' : '⏳ Not known yet — send a test sound', const Color(0xFFB1B9C8)),
  };
}

String askodoxPhoneSoundReason(String reason, bool te) => switch (reason) {
      'needs_access' => te ? 'నోటిఫికేషన్ అనుమతి ఇవ్వలేదు' : 'notification access not given',
      'no_listener' => te ? 'యాప్ పాత వెర్షన్ — Play Store లో అప్‌డేట్' : 'old app version — update from Play Store',
      'no_apps' => te ? 'పేమెంట్ యాప్ ఎంచుకోలేదు' : 'no payment app chosen',
      'off' => te ? 'పేమెంట్ సౌండ్ ఆఫ్' : 'payment sound off',
      'no_voice' => te ? 'ఫోన్ వాయిస్ పనిచేయలేదు' : 'the phone voice failed',
      'no_answer' => te ? 'ఫోన్ ఆఫ్ / నెట్ లేదు / ఫోన్ యాప్‌ను ఆపేసింది' : 'phone off / no internet / the phone stopped the app',
      _ => te ? 'తెలియదు' : 'unknown',
    };

String askodoxPhoneName(AskodoxJson p, bool te) {
  final name = '${p['name'] ?? ''}'.trim();
  final who = name.isNotEmpty ? name : askodoxStaffRoleLabel('${p['role'] ?? ''}', te);
  return p['mine'] == true ? '$who (${te ? 'ఈ ఫోన్' : 'this phone'})' : who;
}

/// [warningOnly]: the alert page's top -- shown only when a phone has a problem, opens "who hears it".
class AskodoxPayAlertPhonesCard extends ConsumerStatefulWidget {
  const AskodoxPayAlertPhonesCard({super.key, required this.businessId, this.warningOnly = false});

  final String businessId;
  final bool warningOnly;

  @override
  ConsumerState<AskodoxPayAlertPhonesCard> createState() => _AskodoxPayAlertPhonesCardState();
}

class _AskodoxPayAlertPhonesCardState extends ConsumerState<AskodoxPayAlertPhonesCard> {
  AskodoxJson? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).paymentAlertPhones(widget.businessId);
      if (mounted) setState(() => _data = out);
    } catch (_) {
      // an older server has no /phones: show nothing
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final phones = askodoxPosList(_data?['phones']);
    if (_data == null || phones.isEmpty) return const SizedBox.shrink();
    final bad = phones.where((p) => p['state'] == 'permission_off' || p['state'] == 'not_answering').toList();
    if (widget.warningOnly) {
      if (bad.isEmpty) return const SizedBox.shrink();
      return Card(
        key: const Key('askodoxPayAlertPhonesWarning'),
        color: const Color(0xFF603D3E),
        child: ListTile(
          leading: const Icon(Icons.volume_off_rounded, color: Color(0xFFFEA195)),
          title: Text(te ? '${bad.length} ఫోన్‌లో పేమెంట్ సౌండ్ రావట్లేదు' : 'Payment sound not working on ${bad.length} phone(s)',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text([for (final p in bad) '${askodoxPhoneName(p, te)}: ${askodoxPhoneSoundState(p, te).$1}'].join('\n')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/me/payment-alerts/${widget.businessId}/who'),
        ),
      );
    }
    return Card(
      key: const Key('askodoxPayAlertPhones'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'ఫోన్ల స్థితి — సౌండ్ వస్తోందా?' : 'Phones — is the sound playing?',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final p in phones)
            Padding(
              key: ValueKey('askodoxPayAlertPhone-${p['id']}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.phone_android, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(askodoxPhoneName(p, te), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(askodoxPhoneSoundState(p, te).$1,
                        style: TextStyle(fontSize: 12.5, color: askodoxPhoneSoundState(p, te).$2)),
                  ]),
                ),
              ]),
            ),
          if (bad.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  te
                      ? 'అనుమతులు దూరం నుంచి మార్చలేం. ఆ ఫోన్‌లో ASKODOX తెరిస్తే చేయాల్సిన ఒక్క స్టెప్ మాత్రమే చూపిస్తుంది.'
                      : 'Settings cannot be changed from another phone. Opening ASKODOX on that phone shows the one step it needs.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB4BED1))),
            ),
        ]),
      ),
    );
  }
}
