import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Owner 2026-11-24: ONE rule for every way of working -- the customer pays to the OWNER's own UPI QR; the owner and
/// the person who showed it both hear when the money's notice arrives; the owner's "I saw it" records the money on the
/// job card / monthly due. ASKODOX never holds the money. `kind` = job | booking | member.
Future<void> askodoxShowCollectQr(BuildContext context, WidgetRef ref,
    {required String businessId, required String kind, required String refId, String month = ''}) async {
  final repo = ref.read(askodoxPosRepositoryProvider);
  final te = askodoxPosTe(context);
  AskodoxJson request;
  try {
    request = await repo.collectFor(businessId, kind, refId, month: month);
  } on AskodoxPosException catch (e) {
    if (context.mounted) askodoxPosSnack(context, e.message(te));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CollectQrSheet(repo: repo, businessId: businessId, first: request),
  );
}

class _CollectQrSheet extends StatefulWidget {
  const _CollectQrSheet({required this.repo, required this.businessId, required this.first});
  final AskodoxPosRepository repo;
  final String businessId;
  final AskodoxJson first;

  @override
  State<_CollectQrSheet> createState() => _CollectQrSheetState();
}

class _CollectQrSheetState extends State<_CollectQrSheet> {
  late AskodoxJson _req = widget.first;
  bool _busy = false;

  Future<void> _refresh() async {
    final list = await widget.repo.collectRequests(widget.businessId);
    for (final r in list) {
      if (r['id'] == _req['id'] && mounted) setState(() => _req = r);
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final r = await widget.repo.decideCollectRequest(widget.businessId, '${_req['id']}', 'confirm',
          checkedBank: true);
      if (mounted) setState(() => _req = r);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final status = '${_req['status']}';
    final done = status == 'confirmed';
    final got = status == 'matched' || done;
    final rupees = askodoxPosInt(_req['amount_paise']) / 100;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${_req['label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('₹${rupees == rupees.roundToDouble() ? rupees.round() : rupees.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (!done)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(key: const Key('askodoxCollectQr'), data: '${_req['upi_link']}', size: 210),
            ),
          const SizedBox(height: 8),
          Text(
              done
                  ? (te ? '✓ ఓనర్ నిర్ధారించారు, రికార్డ్ అయింది' : '✓ Owner confirmed, recorded')
                  : got
                      ? (te ? '✓ డబ్బు వచ్చిన నోటీసు వచ్చింది. బ్యాంక్ లో చూసి నిర్ధారించండి.' : '✓ Payment notice arrived. Check your bank, then confirm.')
                      : (te ? 'కస్టమర్ ఈ QR స్కాన్ చేసి కట్టాలి. డబ్బు ఓనర్ UPI కే వెళ్తుంది.' : 'Customer scans and pays. Money goes to the owner\'s UPI.'),
              textAlign: TextAlign.center,
              key: const Key('askodoxCollectQrState')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _refresh, child: Text(te ? 'రిఫ్రెష్' : 'Refresh'))),
            if (!done) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('askodoxCollectQrConfirm'),
                  onPressed: _busy ? null : _confirm,
                  child: Text(te ? 'డబ్బు వచ్చింది' : 'Money received'),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
