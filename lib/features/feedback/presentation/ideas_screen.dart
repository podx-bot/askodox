import '../../../config/theme/askodox_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/flags/askodox_remote_flags.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/update/askodox_update_service.dart';
import '../../home/presentation/question_mic.dart';
import '../../pos/presentation/pos_common.dart' show askodoxPosTe;
import '../../staff/askodox_staff_access.dart';

/// "మీ ఐడియా చెప్పండి" (owner 2026-11-18): anyone says or types an idea; it goes to the backend as data
/// (`POST /api/feedback`, kind `idea`, contact details masked on the server) for the team to read.
class AskodoxIdeasScreen extends ConsumerStatefulWidget {
  const AskodoxIdeasScreen({super.key, this.about = ''});

  /// Where it was opened from (e.g. `business`), kept with the idea.
  final String about;

  @override
  ConsumerState<AskodoxIdeasScreen> createState() => _AskodoxIdeasScreenState();
}

class _AskodoxIdeasScreenState extends ConsumerState<AskodoxIdeasScreen> {
  final _text = TextEditingController();
  late String _topic = widget.about.isEmpty ? 'other' : widget.about;
  bool _sending = false;
  String? _sent;

  static const _topics = <(String, String, String)>[
    ('business', 'నా బిజినెస్', 'My business'),
    ('billing', 'బిల్లులు & డబ్బు', 'Bills & money'),
    ('orders', 'ఆర్డర్లు', 'Orders'),
    ('staff', 'సిబ్బంది', 'Staff'),
    ('reports', 'రిపోర్ట్స్', 'Reports'),
    ('shopping', 'కొనడం / వెతకడం', 'Shopping / search'),
    ('other', 'ఇంకేదైనా', 'Anything else'),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _te => askodoxPosTe(context);

  Future<void> _send() async {
    final words = _text.text.trim();
    if (words.length < 3 || _sending) return;
    setState(() => _sending = true);
    String? reference;
    try {
      reference = await ref.read(askodoxStaffRepositoryProvider).sendFeedback(
            kind: 'idea',
            message: words,
            feature: 'idea:$_topic',
            appVersion: '${await const AskodoxUpdateService().installedBuildNumber()}',
            installId: await ref.read(askodoxFlagsRepositoryProvider).installId(),
            token: ref.read(authSessionProvider).tokenPlaceholder,
          );
    } catch (_) {
      reference = null;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (reference != null) {
        _sent = reference;
        _text.clear();
      }
    });
    if (reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_te ? 'పంపలేకపోయాం — ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి.' : 'Could not send — check the internet and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    return Scaffold(
      key: const Key('askodoxIdeas'),
      backgroundColor: const Color(0xFF1F2432),
      appBar: AppBar(title: Text(te ? 'సలహాలు & సూచనలు' : 'Ideas & suggestions')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF392C01), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('💡', style: TextStyle(fontSize: 40)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    te
                        ? 'ఏది ఇంకా సులువుగా ఉండాలి? ఏం కొత్తగా కావాలి? మాట్లాడి చెప్పండి లేదా రాయండి — మా టీమ్ ప్రతి ఐడియా చదువుతుంది.'
                        : 'What should be easier? What new thing do you need? Say it or type it — our team reads every idea.',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Text(te ? 'దేని గురించి?' : 'About what?', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, tl, en) in _topics)
              ChoiceChip(
                key: Key('askodoxIdeaTopic-$k'),
                label: Text(te ? tl : en),
                selected: _topic == k,
                onSelected: (_) => setState(() => _topic = k),
              ),
          ]),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: AskodoxLook.sheet, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF4A526B))),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const Key('askodoxIdeaText'),
                  controller: _text,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: te ? 'ఉదా: రాత్రి రిపోర్ట్ వాట్సాప్‌లో కూడా రావాలి' : 'e.g. send the night report on WhatsApp too',
                  ),
                ),
              ),
              AskodoxQuestionMic(
                key: const Key('askodoxIdeaMic'),
                lang: te ? 'te' : 'en',
                followCentre: false,
                maxDuration: const Duration(seconds: 90),
                onText: (words) => setState(() => _text.text = [_text.text.trim(), words.trim()].where((x) => x.isNotEmpty).join(' ')),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(te ? 'ఫోన్ నంబర్, OTP, కార్డ్ నంబర్లు రాయకండి.' : 'Do not write phone numbers, OTPs or card numbers.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB1B9C8))),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('askodoxIdeaSend'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AskodoxLook.sheet))
                : const Icon(Icons.send_rounded),
            label: Text(te ? 'పంపు' : 'Send', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          if (_sent != null) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('askodoxIdeaThanks'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1A3429), borderRadius: BorderRadius.circular(14)),
              child: Text(
                  te ? '🙏 ధన్యవాదాలు! మీ ఐడియా మా టీమ్‌కి చేరింది. ఇంకోటి ఉంటే రాయండి.' : '🙏 Thank you! Your idea reached our team. Send another any time.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7CD3A2))),
            ),
          ],
        ]),
      ),
    );
  }
}
