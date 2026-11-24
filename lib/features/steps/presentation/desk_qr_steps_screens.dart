import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 12): shop / table QR `/desk/:id/qr`. Top = the shop QR, middle = one row per
/// table (tap = that table's QR), bottom = ONE big button (send the order code to customers on WhatsApp). Copy, more
/// tables and the old page are in the header menu.
class AskodoxDeskQrStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDeskQrStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskQrStepsScreen> createState() => _DeskQrState();
}

class _DeskQrState extends ConsumerState<AskodoxDeskQrStepsScreen> {
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).deskQr(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  String _shareText(AskodoxJson d) {
    final te = _te;
    final name = '${d['name'] ?? ''}'.trim();
    final shop = name.isEmpty ? (te ? 'మా షాప్' : 'our shop') : name;
    return te
        ? '$shop లో ఇప్పుడు ASKODOX తో ఆర్డర్ చేయవచ్చు. ASKODOX యాప్ తెరిచి Profile → "Order at a shop" లో ఈ కోడ్ రాయండి: ${d['shop']}'
        : 'You can now order from $shop on ASKODOX. Open the ASKODOX app, go to Profile → "Order at a shop" and enter this code: ${d['shop']}';
  }

  Future<void> _addTables() async {
    final te = _te;
    final count = TextEditingController(text: '5');
    final n = await showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(te ? 'ఎన్ని టేబుల్స్ ఉన్నాయి?' : 'How many tables?'),
              content: TextField(
                  key: const Key('askodoxDeskQrStepsCount'),
                  controller: count,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(helperText: te ? 'T1, T2 ... గా పేర్లు వస్తాయి' : 'Named T1, T2 ...')),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
                FilledButton(
                    key: const Key('askodoxDeskQrStepsMake'),
                    onPressed: () => Navigator.of(c).pop(int.tryParse(count.text.trim())),
                    child: Text(te ? 'QR లు చేయి' : 'Make QRs')),
              ],
            ));
    if (n == null || n < 1) return;
    final repo = ref.read(askodoxPosRepositoryProvider);
    final have = {for (final t in askodoxPosList(_data?['tables'])) '${t['name']}'.trim().toLowerCase()};
    try {
      for (var i = 1; i <= n.clamp(1, 60); i++) {
        if (!have.contains('t$i')) await repo.addTable(widget.businessId, 'T$i');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
    await _load();
  }

  Widget _poster(String label, String code) => AskodoxQrPoster(
        data: code,
        te: _te,
        title: '${_data?['shop'] ?? _data?['name'] ?? ''}',
        label: label,
        size: 220,
        fileName: 'askodox-qr-${label.replaceAll(RegExp(r'\s+'), '-')}',
        instructionEn: 'Scan with ASKODOX to see the menu and order',
        instructionTe: 'ASKODOX తో స్కాన్ చేసి మెనూ చూడండి, ఆర్డర్ చేయండి',
      );

  Future<void> _tableQr(AskodoxJson t) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _poster(_te ? 'టేబుల్ ${t['name']}' : 'Table ${t['name']}', '${t['code']}'),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'షాప్ / టేబుల్ QR' : 'Shop / table QR';
    final d = _data;
    if (d == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxDeskQrSteps'),
          title: title,
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final tables = askodoxPosList(d['tables']);
    return AskodoxStepScaffold(
      key: const Key('askodoxDeskQrSteps'),
      title: title,
      more: [
        AskodoxStepMore('askodoxDeskQrStepsCopy', te ? 'మెసేజ్ కాపీ' : 'Copy the message', Icons.copy, () async {
          await Clipboard.setData(ClipboardData(text: _shareText(d)));
          if (mounted) askodoxPosSnack(context, te ? 'కాపీ అయింది' : 'Copied');
        }),
        AskodoxStepMore('askodoxDeskQrStepsTables', tables.isEmpty ? (te ? 'టేబుల్ QR లు చేయి' : 'Make table QRs') : (te ? 'ఇంకా టేబుల్స్' : 'More tables'),
            Icons.table_restaurant_outlined, _addTables),
        AskodoxStepMore('askodoxDeskQrStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/desk/${widget.businessId}/qr?full=1')),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        Center(child: _poster(te ? 'షాప్ (పార్సిల్ / డెలివరీ)' : 'Shop (takeaway / delivery)', '${d['shop']}')),
        if (tables.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 16, 2, 4),
            child: Text(te ? 'టేబుల్స్ — నొక్కితే ఆ టేబుల్ QR' : 'Tables — tap for that table\'s QR', style: const TextStyle(fontWeight: FontWeight.w900, color: askodoxStepMuted)),
          ),
          for (final t in tables)
            AskodoxStepPersonRow(
              key: Key('askodoxDeskQrStepsTable-${t['name']}'),
              name: '${t['name']}',
              sub: '${t['code']}',
              amount: 'QR',
              amountColor: askodoxStepGreen,
              onTap: () => _tableQr(t),
            ),
        ],
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDeskQrStepsSend'),
        label: te ? 'కస్టమర్లకు WhatsApp' : 'Send on WhatsApp',
        icon: Icons.send,
        onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText(d))}'), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
