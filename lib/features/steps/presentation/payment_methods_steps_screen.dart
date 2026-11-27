import '../../../config/theme/askodox_look.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/share/askodox_image_share.dart';
import '../../../shared/widgets/qr_poster.dart';
import '../../native_video/video_commerce.dart' show askodoxShareTextProvider;
import '../../pos/data/pos_hardware.dart' show AskodoxScanException;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_collect_screens.dart' show askodoxQrReaderProvider;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 28): my own ways to be paid `/me/payment-methods`.
/// Top = THE QR customers scan (default UPI), middle = ONE list of my UPI IDs / bank accounts (tap = make default /
/// remove, asks once), bottom = ONE big button "Add QR / UPI" (QR photo, photograph QR, type UPI ID, bank account).
/// Share / copy the QR, payment sound alerts and the old page live in ⋮. Money goes straight to the person's bank;
/// ASKODOX never holds it. Old page stays at `?full=1`.
class AskodoxPaymentMethodsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxPaymentMethodsStepsScreen({super.key});

  @override
  ConsumerState<AskodoxPaymentMethodsStepsScreen> createState() => _PaymentMethodsStepsState();
}

class _PaymentMethodsStepsState extends ConsumerState<AskodoxPaymentMethodsStepsScreen> {
  final _qrKey = GlobalKey();
  List<AskodoxJson>? _methods;
  Object? _error;
  bool _busy = false;
  // Dialog boxes live here: a dialog still draws them while it closes.
  final _upiTyped = TextEditingController();
  final _payee = TextEditingController();
  final _app = TextEditingController();
  final _holder = TextEditingController();
  final _number = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_upiTyped, _payee, _app, _holder, _number, _ifsc, _bank]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.myPaymentMethods();
      if (mounted) {
        setState(() {
          _methods = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _methods == null) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<List<AskodoxJson>> Function() call, {String? done}) async {
    setState(() => _busy = true);
    try {
      final list = await call();
      if (!mounted) return;
      setState(() => _methods = list);
      if (done != null) askodoxPosSnack(context, done);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AskodoxJson? _main(List<AskodoxJson> methods) {
    final upis = methods.where((m) => m['kind'] != 'bank' && '${m['upi_id'] ?? ''}'.isNotEmpty).toList();
    if (upis.isEmpty) return null;
    return upis.firstWhere((u) => u['is_default'] == true, orElse: () => upis.first);
  }

  String _link(AskodoxJson m) {
    final upi = '${m['upi_id']}';
    final name = '${m['payee_name'] ?? ''}';
    return 'upi://pay?pa=${Uri.encodeComponent(upi)}${name.isEmpty ? '' : '&pn=${Uri.encodeComponent(name)}'}&cu=INR';
  }

  // ------------------------------------------------------------------ adding
  Future<void> _addSheet() async {
    final te = _te;
    final way = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'ఎలా చేర్చాలి?' : 'How to add?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (final (value, icon, en, tel) in const [
              ('photos', Icons.image_outlined, 'Pick the QR photo (from PhonePe / GPay / bank app)', 'QR ఫోటో ఎంచుకోండి (PhonePe / GPay / బ్యాంక్ యాప్ నుండి)'),
              ('camera', Icons.qr_code_scanner_rounded, 'Photograph the QR', 'QR ఫోటో తీయండి'),
              ('typed', Icons.keyboard_rounded, 'Type the UPI ID', 'UPI ID టైప్ చేయండి'),
              ('bank', Icons.account_balance_outlined, 'Bank account', 'బ్యాంక్ ఖాతా'),
            ]) ...[
              OutlinedButton.icon(
                key: ValueKey('askodoxPayMethodsStepsWay-$value'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), alignment: Alignment.centerLeft),
                onPressed: () => Navigator.pop(ctx, value),
                icon: Icon(icon),
                label: Text(te ? tel : en, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
    if (way == null || !mounted) return;
    switch (way) {
      case 'typed':
        await _addTyped();
      case 'bank':
        await _addBank();
      default:
        await _addFromQr(way);
    }
  }

  Future<void> _addFromQr(String source) async {
    final te = _te;
    String? text;
    try {
      text = await ref.read(askodoxQrReaderProvider).read(source);
    } on AskodoxScanException catch (e) {
      if (mounted) {
        askodoxPosSnack(
            context,
            e.code == 'not_found'
                ? (te
                    ? 'ఫోటోలో QR చదవలేకపోయాను. UPI app లో "Share QR" / "Download QR" image వాడండి, లేదా UPI ID టైప్ చేయండి.'
                    : 'Could not read a QR in this photo. Use the QR image from your UPI app ("Share QR" / "Download QR"), or type the UPI ID.')
                : e.message(te));
      }
      return;
    } catch (_) {
      if (mounted) askodoxPosSnack(context, te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
      return;
    }
    if (text == null || !mounted) return;
    AskodoxJson preview;
    try {
      preview = await _repo.readUpiQr(text);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final saved = await _confirm('${preview['upi_id']}', '${preview['payee_name'] ?? ''}');
    if (saved == null || !mounted) return;
    final qr = text;
    await _run(() => _repo.addPaymentMethod({'kind': 'upi', 'qr_text': qr, ...saved}), done: te ? '✓ సేవ్ అయింది' : '✓ Saved');
  }

  Future<void> _addTyped() async {
    final te = _te;
    _upiTyped.clear();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'UPI ID టైప్ చేయండి' : 'Type your UPI ID'),
        content: TextField(
          key: const Key('askodoxPayMethodsStepsUpi'),
          controller: _upiTyped,
          decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'name@okhdfcbank', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxPayMethodsStepsUpiNext'),
              onPressed: () => Navigator.pop(ctx, _upiTyped.text.trim()),
              child: Text(te ? 'తర్వాత' : 'Next')),
        ],
      ),
    );
    if (typed == null || typed.isEmpty || !mounted) return;
    final saved = await _confirm(typed, '');
    if (saved == null || !mounted) return;
    await _run(() => _repo.addPaymentMethod({'kind': 'upi', 'upi_id': typed, ...saved}), done: te ? '✓ సేవ్ అయింది' : '✓ Saved');
  }

  /// Shows what was read; the person names the app / bank (a label only) before saving.
  Future<AskodoxJson?> _confirm(String upiId, String payee) {
    final te = _te;
    _payee.text = payee;
    _app.clear();
    return showDialog<AskodoxJson>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('askodoxPayMethodsStepsConfirm'),
        title: Text(te ? 'ఈ UPI ID సేవ్ చేయాలా?' : 'Save this UPI ID?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(upiId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
                controller: _payee,
                decoration: InputDecoration(labelText: te ? 'పేరు (కస్టమర్‌కి కనిపించేది)' : 'Name customers see', border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: _app,
                decoration: InputDecoration(
                    labelText: te ? 'ఏ యాప్ / బ్యాంక్ (ఉదా. PhonePe, HDFC)' : 'Which app / bank (e.g. PhonePe, HDFC)',
                    border: const OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxPayMethodsStepsSave'),
              onPressed: () => Navigator.pop(ctx, {'payee_name': _payee.text.trim(), 'app': _app.text.trim()}),
              child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
  }

  Future<void> _addBank() async {
    final te = _te;
    for (final c in [_holder, _number, _ifsc, _bank]) {
      c.clear();
    }
    Widget field(TextEditingController c, String label, String key, {String? hint, bool digits = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: Key(key),
            controller: c,
            keyboardType: digits ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'బ్యాంక్ ఖాతా' : 'Bank account'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(_holder, te ? 'ఖాతాదారు పేరు' : 'Account holder name', 'askodoxPayMethodsStepsHolder'),
            field(_number, te ? 'ఖాతా నంబర్' : 'Account number', 'askodoxPayMethodsStepsNumber', digits: true),
            field(_ifsc, 'IFSC', 'askodoxPayMethodsStepsIfsc', hint: 'HDFC0001234'),
            field(_bank, te ? 'బ్యాంక్ పేరు' : 'Bank name', 'askodoxPayMethodsStepsBankName'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxPayMethodsStepsBankSave'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'kind': 'bank',
      'account_holder': _holder.text.trim(),
      'account_number': _number.text.trim(),
      'ifsc': _ifsc.text.trim().toUpperCase(),
      'bank_name': _bank.text.trim(),
    };
    await _run(() => _repo.addPaymentMethod(body), done: te ? '✓ సేవ్ అయింది' : '✓ Saved');
  }

  // ------------------------------------------------------------------ one saved way
  Future<void> _method(AskodoxJson m) async {
    final te = _te;
    final id = '${m['id']}';
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_title(m), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            Text(_sub(m, te), style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 12),
            if (m['is_default'] != true) ...[
              FilledButton(
                key: ValueKey('askodoxPayMethodsStepsDefault-$id'),
                style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.pop(ctx, 'default'),
                child: Text(te ? 'ముఖ్యమైనదిగా చేయి (ఈ QR చూపించు)' : 'Make default (show this QR)'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              key: ValueKey('askodoxPayMethodsStepsRemove-$id'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: askodoxStepBad),
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: Text(te ? 'తీసివేయి' : 'Remove'),
            ),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'default') {
      await _run(() => _repo.defaultPaymentMethod(id), done: te ? '✓ ఇప్పుడు ఇదే మీ QR' : '✓ This is your QR now');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? '${_title(m)} తీసివేయాలా?' : 'Remove ${_title(m)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxPayMethodsStepsRemoveYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'తీసివేయి' : 'Remove')),
        ],
      ),
    );
    if (sure == true && mounted) await _run(() => _repo.removePaymentMethod(id));
  }

  String _title(AskodoxJson m) =>
      m['kind'] == 'bank' ? '${m['bank_name'] ?? ''} ••${m['account_last4'] ?? ''}'.trim() : '${m['upi_id'] ?? ''}';

  String _sub(AskodoxJson m, bool te) => [
        if ('${m['payee_name'] ?? m['account_holder'] ?? ''}'.isNotEmpty) '${m['payee_name'] ?? m['account_holder']}',
        if ('${m['app'] ?? ''}'.isNotEmpty) '${m['app']}',
        if (m['kind'] == 'bank' && '${m['ifsc'] ?? ''}'.isNotEmpty) '${m['ifsc']}',
      ].join(' · ');

  // ------------------------------------------------------------------ share / copy
  Future<void> _share(AskodoxJson m) async {
    final te = _te;
    final upi = '${m['upi_id']}';
    final name = '${m['payee_name'] ?? ''}';
    var shared = false;
    try {
      final boundary = _qrKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) {
          shared = await askodoxShareImage(data.buffer.asUint8List(),
              name: 'askodox-upi-qr', text: '${name.isEmpty ? '' : '$name — '}UPI: $upi');
        }
      }
    } catch (_) {}
    if (!shared) shared = await ref.read(askodoxShareTextProvider)('$name — UPI: $upi\n${_link(m)}', subject: 'UPI');
    if (!shared) await _copy(upi, te);
  }

  Future<void> _copy(String upi, bool te) async {
    await Clipboard.setData(ClipboardData(text: upi));
    if (mounted) askodoxPosSnack(context, te ? 'UPI ID కాపీ అయింది.' : 'UPI ID copied.');
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా ఖాతాలు' : 'My accounts';
    final methods = _methods;
    final main = methods == null ? null : _main(methods);
    final more = [
      if (main != null) ...[
        AskodoxStepMore('askodoxPayMethodsStepsShare', te ? 'QR షేర్' : 'Share the QR', Icons.share_outlined, () => _share(main)),
        AskodoxStepMore('askodoxPayMethodsStepsCopy', te ? 'UPI ID కాపీ' : 'Copy the UPI ID', Icons.copy_rounded,
            () => _copy('${main['upi_id']}', te)),
      ],
      AskodoxStepMore('askodoxPayMethodsStepsAlerts', te ? 'పేమెంట్ సౌండ్ అలర్ట్' : 'Payment sound alerts', Icons.volume_up_rounded,
          () => context.push('/me/payment-alerts')),
      AskodoxStepMore('askodoxPayMethodsStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/me/payment-methods?full=1').then((_) => _load())),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    if (methods == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    return AskodoxStepScaffold(
      key: const Key('askodoxPayMethodsSteps'),
      title: title,
      question: main == null ? (te ? 'మీ UPI QR చేర్చండి' : 'Add your UPI QR') : null,
      hint: main == null ? (te ? 'కస్టమర్ స్కాన్ చేసే QR ఇక్కడ కనిపిస్తుంది' : 'The QR customers scan shows here') : null,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          if (main != null)
            Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: AskodoxPaper(child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AskodoxQrPoster(
                      qrKey: const Key('askodoxPayMethodsStepsQr'),
                      data: _link(main),
                      te: te,
                      title: '${main['payee_name'] ?? ''}',
                      size: 190,
                      actions: false,
                      fileName: 'askodox-upi-qr',
                      instructionEn: 'Scan & pay with any UPI app',
                      instructionTe: 'ఏ UPI యాప్‌తో అయినా స్కాన్ చేసి చెల్లించండి',
                      footnoteEn: "Shop's own UPI · ASKODOX never holds your money",
                      footnoteTe: 'షాప్ సొంత UPI · ASKODOX మీ డబ్బు ఉంచుకోదు',
                    ),
                    SelectableText('${main['upi_id']}', style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
                  ]),
                ),
              )),
            ),
          const SizedBox(height: 10),
          for (final m in methods)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxPayMethodsStepsRow-${m['id']}'),
              name: _title(m),
              sub: _sub(m, te),
              amount: m['is_default'] == true ? '★' : (m['kind'] == 'bank' ? '🏦' : 'UPI'),
              amountColor: m['is_default'] == true ? askodoxStepGreen : askodoxStepMuted,
              onTap: () => _method(m),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                te
                    ? 'డబ్బు నేరుగా మీ బ్యాంక్‌కే. ASKODOX మధ్యలో పట్టుకోదు. బ్యాంక్ నంబర్ దాచి (encrypted) ఉంచుతాం.'
                    : 'Money goes straight to your bank. ASKODOX never holds it. Bank numbers are kept encrypted.',
                style: const TextStyle(fontSize: 12, color: askodoxStepMuted, height: 1.4)),
          ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxPayMethodsStepsAdd'),
        label: te ? 'QR / UPI చేర్చు' : 'Add QR / UPI',
        icon: Icons.qr_code_2_rounded,
        busy: _busy,
        onPressed: _busy ? null : _addSheet,
      ),
    );
  }
}
