import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../services/media_picker.dart';
import '../data/pos_hardware.dart';
import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Reads the text inside a QR from a photo (camera or gallery). Injectable for tests.
abstract interface class AskodoxQrReader {
  /// The QR text; null when cancelled. Throws [AskodoxScanException] when no QR was found.
  Future<String?> read(String source);
}

class PhotoQrReader implements AskodoxQrReader {
  const PhotoQrReader(this._picker);
  final AskodoxMediaPicker _picker;

  @override
  Future<String?> read(String source) async {
    final picked = await _picker.pick(source);
    final photo = picked.where((p) => p.isImage).firstOrNull;
    if (photo == null) return null;
    final image = await askodoxDecodeForScan(photo.bytes);
    final code = await compute(askodoxDecodeBarcodePixels, image);
    if (code == null) throw const AskodoxScanException('not_found');
    return code;
  }
}

final askodoxQrReaderProvider = Provider<AskodoxQrReader>((ref) => PhotoQrReader(ref.watch(askodoxMediaPickerProvider)));

Widget _dialogField(TextEditingController c, String label, {String? hint, bool digits = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
      ),
    );

/// Profile -> Payment methods: the person's OWN UPI IDs (from ANY app's / bank's QR) and bank accounts.
class AskodoxMyPaymentMethodsScreen extends ConsumerStatefulWidget {
  const AskodoxMyPaymentMethodsScreen({super.key});

  @override
  ConsumerState<AskodoxMyPaymentMethodsScreen> createState() => _AskodoxMyPaymentMethodsScreenState();
}

class _AskodoxMyPaymentMethodsScreenState extends ConsumerState<AskodoxMyPaymentMethodsScreen> {
  List<AskodoxJson>? _methods;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<List<AskodoxJson>> Function(AskodoxPosRepository repo) call) async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await call(repo);
      if (mounted) setState(() => _methods = list);
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run((repo) => repo.myPaymentMethods());

  Future<void> _addUpiFromQr(String source) async {
    final te = askodoxPosTe(context);
    String? text;
    try {
      text = await ref.read(askodoxQrReaderProvider).read(source);
    } on AskodoxScanException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    } catch (_) {
      if (mounted) askodoxPosSnack(context, te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
      return;
    }
    if (text == null || !mounted) return;
    AskodoxJson preview;
    try {
      preview = await ref.read(askodoxPosRepositoryProvider).readUpiQr(text);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final saved = await _confirmUpi('${preview['upi_id']}', '${preview['payee_name'] ?? ''}');
    if (saved == null) return;
    await _run((repo) => repo.addPaymentMethod({'kind': 'upi', 'qr_text': text, ...saved}));
  }

  /// Shows what was read; the person names the app / bank (label only) before saving.
  Future<AskodoxJson?> _confirmUpi(String upiId, String payee) async {
    final te = askodoxPosTe(context);
    final app = TextEditingController();
    final name = TextEditingController(text: payee);
    final out = await showDialog<AskodoxJson>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('askodoxPayMethodConfirm'),
        title: Text(te ? 'ఈ UPI ID సేవ్ చేయాలా?' : 'Save this UPI ID?'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(upiId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          _dialogField(name, te ? 'పేరు (కస్టమర్‌కి కనిపించేది)' : 'Name customers see'),
          _dialogField(app, te ? 'ఏ యాప్ / బ్యాంక్ (ఉదా. PhonePe, HDFC)' : 'Which app / bank (e.g. PhonePe, HDFC)'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxPayMethodSave'),
              onPressed: () => Navigator.pop(ctx, {'payee_name': name.text.trim(), 'app': app.text.trim()}),
              child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    return out; // dialog fields are not disposed: the closing animation still draws them
  }

  Future<void> _addUpiTyped() async {
    final te = askodoxPosTe(context);
    final id = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'UPI ID టైప్ చేయండి' : 'Type your UPI ID'),
        content: _dialogField(id, 'UPI ID', hint: 'name@okhdfcbank'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxPayMethodTypedNext'),
              onPressed: () => Navigator.pop(ctx, id.text.trim()),
              child: Text(te ? 'తర్వాత' : 'Next')),
        ],
      ),
    );
    if (typed == null || typed.isEmpty || !mounted) return;
    final saved = await _confirmUpi(typed, '');
    if (saved == null) return;
    await _run((repo) => repo.addPaymentMethod({'kind': 'upi', 'upi_id': typed, ...saved}));
  }

  Future<void> _addBank() async {
    final te = askodoxPosTe(context);
    final holder = TextEditingController();
    final number = TextEditingController();
    final ifsc = TextEditingController();
    final bank = TextEditingController();
    final body = await showDialog<AskodoxJson>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'బ్యాంక్ ఖాతా' : 'Bank account'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogField(holder, te ? 'ఖాతాదారు పేరు' : 'Account holder name'),
            _dialogField(number, te ? 'ఖాతా నంబర్' : 'Account number', digits: true),
            _dialogField(ifsc, 'IFSC', hint: 'HDFC0001234'),
            _dialogField(bank, te ? 'బ్యాంక్ పేరు' : 'Bank name'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                    'kind': 'bank',
                    'account_holder': holder.text.trim(),
                    'account_number': number.text.trim(),
                    'ifsc': ifsc.text.trim().toUpperCase(),
                    'bank_name': bank.text.trim(),
                  }),
              child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (body == null) return;
    await _run((repo) => repo.addPaymentMethod(body));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final methods = _methods;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా పేమెంట్ పద్ధతులు' : 'My payment methods')),
      body: methods == null
          ? (_error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(key: const Key('askodoxPayMethods'), padding: const EdgeInsets.all(12), children: [
              Text(
                  te
                      ? 'కొనేవారు / కస్టమర్లు మీకు నేరుగా ఇక్కడే కడతారు — PhonePe, Google Pay, Paytm, BHIM లేదా ఏ బ్యాంక్ QR అయినా. ASKODOX డబ్బు పట్టుకోదు.'
                      : 'Buyers and customers pay you directly here — PhonePe, Google Pay, Paytm, BHIM or any bank QR. ASKODOX never holds money.',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                FilledButton.tonalIcon(
                    key: const Key('askodoxPayMethodQrPhoto'),
                    onPressed: _busy ? null : () => _addUpiFromQr('photos'),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(te ? 'QR ఫోటో ఎంచుకోండి' : 'Pick QR photo')),
                OutlinedButton.icon(
                    key: const Key('askodoxPayMethodQrCamera'),
                    onPressed: _busy ? null : () => _addUpiFromQr('camera'),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(te ? 'QR ఫోటో తీయండి' : 'Photograph QR')),
                OutlinedButton.icon(
                    key: const Key('askodoxPayMethodTyped'),
                    onPressed: _busy ? null : _addUpiTyped,
                    icon: const Icon(Icons.keyboard),
                    label: Text(te ? 'UPI ID టైప్' : 'Type UPI ID')),
                OutlinedButton.icon(
                    key: const Key('askodoxPayMethodBank'),
                    onPressed: _busy ? null : _addBank,
                    icon: const Icon(Icons.account_balance_outlined),
                    label: Text(te ? 'బ్యాంక్ ఖాతా' : 'Bank account')),
              ]),
              if (_error != null)
                Text(_error!, key: const Key('askodoxPayMethodError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              if (methods.isEmpty)
                Text(te ? 'ఇంకా ఏదీ లేదు.' : 'Nothing saved yet.', key: const Key('askodoxPayMethodsEmpty')),
              for (final m in methods)
                Card(
                  key: ValueKey('askodoxPayMethod-${m['id']}'),
                  child: ListTile(
                    leading: Icon(m['kind'] == 'bank' ? Icons.account_balance : Icons.qr_code_2),
                    title: Text(m['kind'] == 'bank'
                        ? '${m['bank_name'] ?? ''} ••${m['account_last4']} · ${m['ifsc']}'
                        : '${m['upi_id']}'),
                    subtitle: Text([
                      if ('${m['payee_name'] ?? m['account_holder'] ?? ''}'.isNotEmpty) '${m['payee_name'] ?? m['account_holder']}',
                      if ('${m['app'] ?? ''}'.isNotEmpty) '${m['app']}',
                      if (m['is_default'] == true) te ? 'డిఫాల్ట్' : 'Default',
                    ].join(' · ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'default'
                          ? _run((repo) => repo.defaultPaymentMethod('${m['id']}'))
                          : _run((repo) => repo.removePaymentMethod('${m['id']}')),
                      itemBuilder: (_) => [
                        if (m['is_default'] != true)
                          PopupMenuItem(value: 'default', child: Text(te ? 'డిఫాల్ట్ చేయి' : 'Make default')),
                        PopupMenuItem(value: 'remove', child: Text(te ? 'తీసివేయి' : 'Remove')),
                      ],
                    ),
                  ),
                ),
            ]),
    );
  }
}

/// POS -> Collect payment: an amount QR to the shop's OWN UPI; a matching payment notification flags it,
/// the cashier confirms (never automatic).
class AskodoxPosCollectScreen extends ConsumerStatefulWidget {
  const AskodoxPosCollectScreen({super.key, required this.businessId, this.pollEvery = const Duration(seconds: 4)});
  final String businessId;
  final Duration pollEvery;

  @override
  ConsumerState<AskodoxPosCollectScreen> createState() => _AskodoxPosCollectScreenState();
}

class _AskodoxPosCollectScreenState extends ConsumerState<AskodoxPosCollectScreen> {
  AskodoxJson? _settings;
  AskodoxJson? _current;
  List<AskodoxJson> _requests = const [];
  String? _error;
  bool _busy = false;
  Timer? _timer;
  final _amount = TextEditingController();
  final _label = TextEditingController();
  late final AskodoxPosRepository _repo = ref.read(askodoxPosRepositoryProvider);

  String get _id => widget.businessId;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.pollEvery != Duration.zero) _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.collectSettings(_id);
      final r = await _repo.collectRequests(_id);
      if (mounted) {
        setState(() {
          _settings = s;
          _requests = r;
          _error = null;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxPosTe(context)));
    }
  }

  Future<void> _poll() async {
    if (_busy || _current == null || _current!['status'] != 'pending') return;
    try {
      final r = await _repo.collectRequests(_id);
      if (!mounted) return;
      setState(() {
        _requests = r;
        _current = r.where((x) => x['id'] == _current!['id']).firstOrNull ?? _current;
      });
    } on AskodoxPosException {
      // offline: next tick
    }
  }

  Future<void> _create() async {
    final te = askodoxPosTe(context);
    final rupees = double.tryParse(_amount.text.trim());
    if (rupees == null || rupees <= 0) {
      askodoxPosSnack(context, te ? 'మొత్తం టైప్ చేయండి.' : 'Type the amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      final req = await _repo.createCollectRequest(_id, (rupees * 100).round(), _label.text.trim());
      if (mounted) setState(() => _current = req);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String requestId, String action) async {
    try {
      final out = await _repo.decideCollectRequest(_id, requestId, action);
      if (!mounted) return;
      setState(() => _current = _current?['id'] == requestId ? out : _current);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  (String, String) _statusText(String status) => switch (status) {
        'matched' => ('Payment notification with this amount arrived — check your bank app, then confirm',
            'ఈ మొత్తం పేమెంట్ నోటిఫికేషన్ వచ్చింది — బ్యాంక్ యాప్‌లో చూసి నిర్ధారించండి'),
        'confirmed' => ('Confirmed by the shop', 'షాపు నిర్ధారించింది'),
        'cancelled' => ('Cancelled', 'రద్దు'),
        _ => ('Waiting for the customer to pay…', 'కస్టమర్ కట్టే వరకు వేచి ఉంది…'),
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _settings;
    final method = s == null ? null : askodoxPosMap(s['method']);
    final current = _current;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'UPI తో కట్టించుకోండి' : 'Collect by UPI')),
      body: s == null
          ? (_error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(key: const Key('askodoxPosCollect'), padding: const EdgeInsets.all(12), children: [
              Card(
                child: ListTile(
                  key: const Key('askodoxPosCollectTo'),
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(method == null || method.isEmpty
                      ? (te ? 'UPI ID ఇంకా లేదు' : 'No UPI ID yet')
                      : '${method['upi_id']}'),
                  subtitle: Text(method == null || method.isEmpty
                      ? (te ? 'యజమాని Profile → నా పేమెంట్ పద్ధతులు లో తన QR / UPI ID జోడించాలి.'
                          : 'The owner adds their QR / UPI ID in Profile → My payment methods.')
                      : (te ? 'డబ్బు నేరుగా ఈ UPI కి వెళ్తుంది. ASKODOX పట్టుకోదు.' : 'Money goes straight to this UPI. ASKODOX never holds it.')),
                  trailing: s['can_edit'] == true
                      ? PopupMenuButton<String>(
                          key: const Key('askodoxPosCollectChange'),
                          icon: const Icon(Icons.swap_horiz),
                          onSelected: (v) async {
                            if (v == '_add') {
                              await context.push('/me/payment-methods');
                              await _load();
                              return;
                            }
                            try {
                              final out = await _repo.setCollectMethod(_id, v);
                              if (mounted) setState(() => _settings = out);
                            } on AskodoxPosException catch (e) {
                              if (context.mounted) askodoxPosSnack(context, e.message(te));
                            }
                          },
                          itemBuilder: (_) => [
                            for (final o in askodoxPosList(s['options']))
                              PopupMenuItem(value: '${o['id']}', child: Text('${o['upi_id']}${'${o['app'] ?? ''}'.isEmpty ? '' : ' · ${o['app']}'}')),
                            PopupMenuItem(value: '_add', child: Text(te ? '+ కొత్తది జోడించు' : '+ Add another')),
                          ],
                        )
                      : null,
                ),
              ),
              if (method != null && method.isNotEmpty) ...[
                const SizedBox(height: 8),
                AskodoxPosField(controller: _amount, label: te ? 'మొత్తం ₹' : 'Amount ₹', number: true),
                AskodoxPosField(controller: _label, label: te ? 'నోట్ (ఐచ్ఛికం, ఉదా. బిల్లు నంబర్)' : 'Note (optional, e.g. bill number)', maxLength: 60),
                FilledButton.icon(
                    key: const Key('askodoxPosCollectShow'),
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(te ? 'QR చూపించు' : 'Show QR')),
              ],
              if (current != null) ...[
                const SizedBox(height: 12),
                Card(
                  key: const Key('askodoxPosCollectCurrent'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Text(askodoxRupees(current['amount_paise']), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      Text('${current['payee']} · ${current['upi_id']}', style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 8),
                      if ('${current['upi_link'] ?? ''}'.isNotEmpty)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(key: const Key('askodoxPosCollectQr'), data: '${current['upi_link']}', size: 230),
                        ),
                      Text(te ? 'ఏ UPI యాప్‌తో అయినా స్కాన్ చేయండి' : 'Scan with any UPI app', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(te ? _statusText('${current['status']}').$2 : _statusText('${current['status']}').$1,
                          key: const Key('askodoxPosCollectStatus'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: switch ('${current['status']}') {
                                'matched' => const Color(0xFFB45309),
                                'confirmed' => const Color(0xFF15803D),
                                _ => const Color(0xFF1D4ED8),
                              })),
                      if (current['status'] == 'pending' || current['status'] == 'matched')
                        Wrap(spacing: 8, children: [
                          FilledButton(
                              key: const Key('askodoxPosCollectConfirm'),
                              onPressed: () => _decide('${current['id']}', 'confirm'),
                              child: Text(te ? 'డబ్బు అందింది' : 'Money received')),
                          TextButton(
                              onPressed: () => _decide('${current['id']}', 'cancel'), child: Text(te ? 'రద్దు' : 'Cancel')),
                        ]),
                      TextButton.icon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: '${current['upi_link']}')),
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(te ? 'పేమెంట్ లింక్ కాపీ' : 'Copy payment link')),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_requests.isNotEmpty) Text(te ? 'ఇటీవలివి' : 'Recent', style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final r in _requests.take(15))
                ListTile(
                  key: ValueKey('askodoxPosCollectReq-${r['id']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${askodoxRupees(r['amount_paise'])}${'${r['label'] ?? ''}'.isEmpty ? '' : ' · ${r['label']}'}'),
                  subtitle: Text(te ? _statusText('${r['status']}').$2 : _statusText('${r['status']}').$1),
                  onTap: () => setState(() => _current = r),
                ),
            ]),
    );
  }
}
