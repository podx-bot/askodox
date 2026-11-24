import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 8): collect by the shop's OWN UPI `/pos/:id/collect`.
/// 1 how much -> 2 the QR (the shop confirms only after the money is seen) -> 3 done. Money is only recorded;
/// the old page stays at `?full=1`.
class AskodoxCollectStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCollectStepsScreen({super.key, required this.businessId, this.pollEvery = const Duration(seconds: 4)});
  final String businessId;
  final Duration pollEvery;

  @override
  ConsumerState<AskodoxCollectStepsScreen> createState() => _CollectState();
}

class _CollectState extends ConsumerState<AskodoxCollectStepsScreen> {
  AskodoxJson? _settings;
  List<AskodoxJson> _requests = const [];
  AskodoxJson? _current;
  Object? _error;
  String _typed = '';
  bool _busy = false;
  Timer? _timer;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (widget.pollEvery != Duration.zero) _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.collectSettings(widget.businessId);
      final r = await _repo.collectRequests(widget.businessId);
      if (mounted) {
        setState(() {
          _settings = s;
          _requests = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _settings == null) setState(() => _error = e);
    }
  }

  Future<void> _poll() async {
    final cur = _current;
    if (_busy || cur == null || cur['status'] != 'pending') return;
    try {
      final r = await _repo.collectRequests(widget.businessId);
      if (!mounted) return;
      setState(() {
        _requests = r;
        _current = r.where((x) => x['id'] == cur['id']).firstOrNull ?? cur;
      });
    } catch (_) {
      // offline: next tick
    }
  }

  Future<void> _show() async {
    final paise = askodoxKeypadPaise(_typed);
    if (paise <= 0) return;
    setState(() => _busy = true);
    try {
      final req = await _repo.createCollectRequest(widget.businessId, paise, '');
      if (mounted) setState(() => _current = req);
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String action) async {
    final cur = _current;
    if (cur == null) return;
    final te = _te;
    var checkedBank = false;
    if (action == 'confirm' && cur['status'] != 'matched') {
      // No payment notification matched this amount: a tap alone must never confirm.
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                key: const Key('askodoxCollectStepsCheckBank'),
                title: Text(te ? 'డబ్బు నిజంగా వచ్చిందా?' : 'Did the money really arrive?'),
                content: Text(te
                    ? 'ఈ మొత్తానికి ఇంకా పేమెంట్ నోటిఫికేషన్ రాలేదు. మీ UPI / బ్యాంక్ యాప్‌లో ఈ మొత్తం కనిపించాకే "అందింది" నొక్కండి.'
                    : 'No payment notification for this amount yet. Mark it received only after you SEE it in your bank / UPI app.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(te ? 'ఇంకా లేదు' : 'Not yet')),
                  FilledButton(
                      key: const Key('askodoxCollectStepsCheckBankYes'),
                      onPressed: () => Navigator.of(c).pop(true),
                      child: Text(te ? 'అవును, చూశాను' : 'Yes, I saw it')),
                ],
              ));
      if (ok != true) return;
      checkedBank = true;
    }
    try {
      final out = await _repo.decideCollectRequest(widget.businessId, '${cur['id']}', action, checkedBank: checkedBank);
      if (!mounted) return;
      setState(() => _current = action == 'cancel' ? null : out);
      if (action == 'cancel') setState(() => _typed = '');
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _sendLink() async {
    final cur = _current;
    final url = '${cur?['share_url'] ?? ''}';
    if (cur == null || url.isEmpty) return;
    final te = _te;
    final amount = askodoxStepRupees(askodoxPosInt(cur['amount_paise']));
    final text = te ? '$amount కట్టడానికి ఈ లింక్ నొక్కండి: $url' : 'Tap to pay $amount by UPI: $url';
    final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) askodoxPosSnack(context, te ? 'యాప్ తెరవలేదు — లింక్ కాపీ చేశాను.' : 'Could not open the app — link copied.');
    }
  }

  bool _received(AskodoxJson r) => r['status'] == 'confirmed';

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      AskodoxStepMore('askodoxCollectStepsRecent', te ? 'ఇటీవలివి' : 'Recent', Icons.history, _recent),
      AskodoxStepMore('askodoxCollectStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/pos/${widget.businessId}/collect?full=1')),
    ];
  }

  Future<void> _recent() async {
    final te = _te;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          if (_requests.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(te ? 'ఇంకా ఏమీ లేవు' : 'Nothing yet')),
          for (final r in _requests.take(15))
            AskodoxStepPersonRow(
              key: Key('askodoxCollectStepsReq-${r['id']}'),
              name: askodoxStepRupees(askodoxPosInt(r['amount_paise'])),
              sub: '${r['label'] ?? ''}',
              amount: _received(r) ? (te ? 'అందింది' : 'Received') : (r['status'] == 'cancelled' ? (te ? 'రద్దు' : 'Cancelled') : (te ? 'వేచి' : 'Waiting')),
              amountColor: _received(r) ? askodoxStepDone : askodoxStepMuted,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _current = r);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'UPI తో కట్టించుకోండి' : 'Collect by UPI';
    final s = _settings;
    if (s == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxCollectSteps'),
          title: title,
          more: _more(),
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final method = askodoxPosMap(s['method']);
    final cur = _current;
    if (cur != null) {
      final done = _received(cur);
      final matched = cur['status'] == 'matched';
      if (done) {
        return AskodoxStepScaffold(
          key: const Key('askodoxCollectSteps3'),
          title: title,
          step: 3,
          total: 3,
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
            const Center(child: AskodoxStepDoneMark()),
            const SizedBox(height: 26),
            AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(cur['amount_paise'])), label: te ? 'అందింది' : 'Received', size: 44),
            if (cur['can_reopen'] == true)
              TextButton.icon(
                  key: const Key('askodoxCollectStepsUndo'),
                  onPressed: () => _decide('reopen'),
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text(te ? 'పొరపాటున నొక్కాను — వెనక్కి' : 'Pressed by mistake — undo')),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxCollectStepsAgain'),
            label: te ? 'ఇంకొకటి' : 'Collect another',
            icon: Icons.add_rounded,
            onPressed: () => setState(() {
              _current = null;
              _typed = '';
            }),
          ),
        );
      }
      return AskodoxStepScaffold(
        key: const Key('askodoxCollectSteps2'),
        title: title,
        step: 2,
        total: 3,
        question: askodoxStepRupees(askodoxPosInt(cur['amount_paise'])),
        hint: matched
            ? (te ? 'నోటిఫికేషన్ వచ్చింది — బ్యాంక్ యాప్‌లో చూసి "అందింది" నొక్కండి' : 'A notification came — check your bank app, then tap received')
            : (te ? 'కస్టమర్ ఏ UPI యాప్‌తో అయినా స్కాన్ చేయవచ్చు' : 'The customer scans with any UPI app'),
        onBack: () => _decide('cancel'),
        more: [
          if ('${cur['share_url'] ?? ''}'.isNotEmpty)
            AskodoxStepMore('askodoxCollectStepsSend', te ? 'కస్టమర్‌కి లింక్ పంపండి' : 'Send link to customer', Icons.send_to_mobile_outlined, _sendLink),
          ..._more(),
        ],
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          if ('${cur['upi_link'] ?? ''}'.isNotEmpty)
            Center(
              child: AskodoxQrPoster(
                qrKey: const Key('askodoxCollectStepsQr'),
                data: '${cur['upi_link']}',
                te: te,
                title: '${cur['payee'] ?? ''}',
                size: 240,
                actions: false,
                fileName: 'askodox-collect-qr',
                footnoteEn: "Shop's own UPI · ASKODOX never holds your money",
                footnoteTe: 'షాప్ సొంత UPI · ASKODOX మీ డబ్బు ఉంచుకోదు',
              ),
            ),
          const SizedBox(height: 10),
          Center(
              child: AskodoxStepPill(matched ? (te ? 'నోటిఫికేషన్ వచ్చింది' : 'Notification matched') : (te ? 'కస్టమర్ కట్టే వరకు వేచి ఉంది…' : 'Waiting for the customer…'),
                  kind: matched ? 'good' : 'warn')),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxCollectStepsConfirm'),
          label: te ? 'డబ్బు అందింది ✓' : 'Money received ✓',
          icon: Icons.check_rounded,
          onPressed: () => _decide('confirm'),
        ),
      );
    }
    if (method.isEmpty) {
      return AskodoxStepScaffold(
        key: const Key('askodoxCollectSteps'),
        title: title,
        question: te ? 'UPI ID ఇంకా లేదు' : 'No UPI ID yet',
        hint: te ? 'ఓనర్ తన QR / UPI ID ని "నా పేమెంట్ పద్ధతులు" లో జోడించాలి.' : 'The owner adds a QR / UPI ID in "My payment methods".',
        more: _more(),
        body: const SizedBox.shrink(),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxCollectStepsAdd'),
          label: te ? 'UPI జోడించు' : 'Add UPI',
          icon: Icons.add_rounded,
          onPressed: () async {
            await context.push('/me/payment-methods');
            await _load();
          },
        ),
      );
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxCollectSteps'),
      title: title,
      step: 1,
      total: 3,
      question: te ? 'ఎంత కట్టించుకోవాలి?' : 'How much to collect?',
      hint: '${method['upi_id']}',
      more: _more(),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepAmountPad(value: _typed, onChanged: (v) => setState(() => _typed = v)),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCollectStepsShow'),
        label: te ? 'QR చూపించు' : 'Show QR',
        icon: Icons.qr_code_2,
        busy: _busy,
        onPressed: _busy || askodoxKeypadPaise(_typed) <= 0 ? null : _show,
      ),
    );
  }
}
