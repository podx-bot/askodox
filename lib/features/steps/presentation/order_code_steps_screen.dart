import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_hardware.dart' show AskodoxScanException;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_collect_screens.dart' show askodoxQrReaderProvider;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 32): order at a shop / table `/order-desk/enter`.
/// Top = ONE question (which shop?) with the search box, middle = ONE list (shops found, else my orders: running ones
/// open their tracking, finished ones "order again"), bottom = ONE big button (photograph the shop / table QR).
/// QR from the gallery, typing the code and the old page live in ⋮. Old page stays at `?full=1`.
class AskodoxOrderCodeStepsScreen extends ConsumerStatefulWidget {
  const AskodoxOrderCodeStepsScreen({super.key});

  @override
  ConsumerState<AskodoxOrderCodeStepsScreen> createState() => _OrderCodeStepsState();
}

class _OrderCodeStepsState extends ConsumerState<AskodoxOrderCodeStepsScreen> {
  final _shop = TextEditingController();
  final _code = TextEditingController();
  List<AskodoxJson> _mine = const [];
  List<AskodoxJson> _shops = const [];
  bool _searched = false;
  Timer? _debounce;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadMine());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _shop.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    try {
      final rows = await _repo.deskMine();
      if (mounted) setState(() => _mine = rows);
    } catch (_) {}
  }

  void _searchSoon(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = text.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() {
            _shops = const [];
            _searched = false;
          });
        }
        return;
      }
      try {
        final rows = await _repo.deskShops(q);
        if (mounted && _shop.text.trim() == q) {
          setState(() {
            _shops = rows;
            _searched = true;
          });
        }
      } on AskodoxPosException {
        // the QR and the code still work
      }
    });
  }

  void _open(String code) {
    final text = code.trim();
    if (text.isEmpty) return;
    context.push('/order-desk?code=${Uri.encodeQueryComponent(text)}');
  }

  /// A customer cannot type a long code: photograph the shop / table QR (read on this phone).
  Future<void> _scan(String source) async {
    final te = _te;
    try {
      final text = await ref.read(askodoxQrReaderProvider).read(source);
      if (text == null || !mounted) return;
      if (!text.toUpperCase().startsWith('ASKODOX-ORDER:')) {
        askodoxPosSnack(context,
            te ? 'ఇది ASKODOX ఆర్డర్ QR కాదు. షాప్ / టేబుల్ మీది QR తీయండి.' : 'That is not an ASKODOX order QR. Photograph the one on the shop / table.');
        return;
      }
      _open(text);
    } on AskodoxScanException {
      if (mounted) {
        askodoxPosSnack(context,
            te ? 'QR కనబడలేదు. దగ్గరగా, వెలుతురులో మళ్ళీ తీయండి — లేదా షాప్ పేరు వెతకండి.' : 'No QR found. Try closer, in good light — or search the shop by name.');
      }
    } catch (_) {
      if (mounted) askodoxPosSnack(context, te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
    }
  }

  Future<void> _typeCode() async {
    final te = _te;
    _code.clear();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'ఆర్డర్ కోడ్' : 'Order code'),
        content: TextField(
          key: const Key('askodoxOrderCodeStepsCode'),
          controller: _code,
          decoration: InputDecoration(
              border: const OutlineInputBorder(), helperText: te ? 'QR కింద ఉంటుంది (ASKODOX-ORDER:…)' : 'Printed under the QR (ASKODOX-ORDER:…)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxOrderCodeStepsCodeGo'),
              onPressed: () => Navigator.pop(d, _code.text.trim()),
              child: Text(te ? 'తెరువు' : 'Open')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) _open(code);
  }

  String _kind(String kind, bool te) => switch (kind) {
        'dine_in' => te ? 'ఇక్కడ తింటాను' : 'Dine in',
        'delivery' => te ? 'డెలివరీ' : 'Delivery',
        _ => te ? 'పార్సిల్' : 'Takeaway',
      };

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final searching = _shop.text.trim().length >= 2;
    return AskodoxStepScaffold(
      key: const Key('askodoxOrderCodeSteps'),
      title: te ? 'షాప్ / టేబుల్ ఆర్డర్' : 'Order at a shop / table',
      question: te ? 'ఏ షాప్?' : 'Which shop?',
      hint: te ? 'పేరు వెతకండి లేదా షాప్ / టేబుల్ మీది QR ఫోటో తీయండి' : 'Search the name or photograph the QR on the shop / table',
      more: [
        AskodoxStepMore('askodoxOrderCodeStepsGallery', te ? 'గ్యాలరీ నుంచి QR' : 'QR from the gallery', Icons.photo_library_outlined,
            () => _scan('photos')),
        AskodoxStepMore('askodoxOrderCodeStepsType', te ? 'కోడ్ టైప్ చేయి' : 'Type the code', Icons.keyboard_rounded, _typeCode),
        AskodoxStepMore('askodoxOrderCodeStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/order-desk/enter?full=1')),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        AskodoxStepSearch(
          fieldKey: const Key('askodoxOrderCodeStepsSearch'),
          controller: _shop,
          hint: te ? 'షాప్ పేరు' : 'Shop name',
          onChanged: (t) {
            setState(() {});
            _searchSoon(t);
          },
        ),
        const SizedBox(height: 8),
        if (searching) ...[
          for (final s in _shops)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxOrderCodeStepsShop-${s['id']}'),
              name: '${s['name'] ?? ''}',
              sub: s['open'] == true ? (te ? 'తెరిచి ఉంది' : 'Open') : (te ? 'ఇప్పుడు మూసి ఉంది' : 'Closed now'),
              amount: '›',
              amountColor: s['open'] == true ? askodoxStepGreen : askodoxStepMuted,
              onTap: () => _open('${s['code']}'),
            ),
          if (_searched && _shops.isEmpty)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(te ? 'ఈ పేరుతో ASKODOX లో షాప్ కనబడలేదు.' : 'No shop with this name on ASKODOX.')),
        ] else ...[
          if (_mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(te ? 'నా ఆర్డర్లు' : 'My orders', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          for (final o in _mine)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxOrderCodeStepsMine-${o['id']}'),
              name: '${o['business_name'] ?? ''}',
              sub: '${_kind('${o['kind']}', te)} · ${(o['stage_text'] as Map?)?[te ? 'te' : 'en'] ?? ''}',
              amount: const ['done', 'rejected', 'cancelled'].contains(o['stage']) ? (te ? 'మళ్ళీ' : 'Again') : '›',
              amountColor: askodoxStepGreen,
              onTap: () {
                if (const ['done', 'rejected', 'cancelled'].contains(o['stage'])) {
                  _open('ASKODOX-ORDER:${o['business_id']}');
                } else {
                  context.push('/order-desk/track/${o['id']}');
                }
              },
            ),
        ],
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxOrderCodeStepsScan'),
        label: te ? 'QR ఫోటో తీయి' : 'Photograph the QR',
        icon: Icons.qr_code_scanner_rounded,
        onPressed: () => _scan('camera'),
      ),
    );
  }
}
