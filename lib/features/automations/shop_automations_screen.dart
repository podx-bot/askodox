import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pos/data/pos_repository.dart';

/// "ASKODOX గమనించింది" for one shop (owner 2026-11-25, automations 3 + 4): items running low grouped by the supplier
/// they were last bought from, and regular customers who have not come for a while. DRAFTS ONLY: a purchase order is
/// made as a draft the owner checks and sends; a customer message opens in WhatsApp for the owner to send himself.
/// Every card has "వద్దు" (not now) and "ఇక చూపించకు" (never again).
final askodoxShopAutomationsProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).shopAutomations(shop));

/// "2.5" / "3" from milli-units.
String askodoxQtyText(Object? milli) {
  final qty = ((milli as num?) ?? 0) / 1000;
  return qty == qty.roundToDouble() ? '${qty.toInt()}' : qty.toStringAsFixed(qty * 10 == (qty * 10).roundToDouble() ? 1 : 2);
}

/// The 10-digit number as a WhatsApp link with the draft text; null when the number cannot be dialled.
Uri? askodoxWinbackLink(String phone, String text) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final ten = digits.length >= 10 ? digits.substring(digits.length - 10) : '';
  if (ten.isEmpty) return null;
  return Uri.parse('https://wa.me/91$ten?text=${Uri.encodeComponent(text)}');
}

class AskodoxShopAutomationsScreen extends ConsumerStatefulWidget {
  const AskodoxShopAutomationsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopAutomationsScreen> createState() => _AskodoxShopAutomationsScreenState();
}

class _AskodoxShopAutomationsScreenState extends ConsumerState<AskodoxShopAutomationsScreen> {
  final _message = TextEditingController();
  bool _messageSet = false;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _putAway(String kind, String card, {required bool forever}) async {
    try {
      await ref.read(askodoxPosRepositoryProvider).automationDismiss(kind, card, forever: forever);
    } catch (_) {}
    ref.invalidate(askodoxShopAutomationsProvider(widget.businessId));
  }

  Future<void> _draft(AskodoxJson group, bool te) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).lowStockDraft(widget.businessId, '${group['supplier_id']}');
      if (!mounted) return;
      _say(te
          ? 'Order draft సిద్ధం. Purchase orders లో చూసి మీరే పంపండి.'
          : 'Order draft is ready. Check it in Purchase orders and send it yourself.');
      ref.invalidate(askodoxShopAutomationsProvider(widget.businessId));
    } on AskodoxPosException catch (e) {
      if (mounted) _say(e.message(te));
    } catch (_) {
      if (mounted) _say(te ? 'ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి' : 'Check the internet and tap again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsapp(AskodoxJson person, bool te) async {
    final link = askodoxWinbackLink('${person['phone'] ?? ''}', _message.text.trim());
    final opened = link != null && await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _say(te ? 'WhatsApp తెరవలేకపోయాం' : 'Could not open WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final state = ref.watch(askodoxShopAutomationsProvider(widget.businessId));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ASKODOX గమనించింది' : 'ASKODOX noticed')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e is AskodoxPosException ? e.message(te) : (te ? 'ఇప్పుడు చూపలేకపోయాం' : 'Could not load now'),
              key: const Key('askodoxAutoError'), textAlign: TextAlign.center),
        )),
        data: (data) {
          final low = askodoxPosMap(data['low_stock']);
          final back = askodoxPosMap(data['winback']);
          final suppliers = askodoxPosList(low['suppliers']);
          final loose = askodoxPosList(low['no_supplier']);
          final people = askodoxPosList(back['people']);
          if (!_messageSet && back['draft'] is Map) {
            _message.text = '${(back['draft'] as Map)[te ? 'te' : 'en'] ?? ''}';
            _messageSet = true;
          }
          if (suppliers.isEmpty && loose.isEmpty && people.isEmpty) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(te ? 'ఇప్పుడు చెప్పడానికి ఏమీ లేదు. అన్నీ బాగున్నాయి.' : 'Nothing to tell you now. All good.',
                  key: const Key('askodoxAutoEmpty'), textAlign: TextAlign.center),
            ));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            if (suppliers.isNotEmpty || loose.isNotEmpty)
              Text(te ? 'Stock తక్కువ' : 'Running low', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            for (final g in suppliers) _supplierCard(g, te),
            if (loose.isNotEmpty)
              Card(
                key: const Key('askodoxAutoNoSupplier'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(te
                      ? 'ఇవి తక్కువ ఉన్నాయి, కానీ ఎవరి దగ్గర కొన్నారో తెలియదు: '
                          '${loose.map((l) => '${l['name']}').join(', ')}. ఒకసారి purchase bill ఎక్కిస్తే తర్వాత draft వస్తుంది.'
                      : 'Low, but no supplier is known yet: ${loose.map((l) => '${l['name']}').join(', ')}. '
                          'Record one purchase bill and the next draft comes by itself.'),
                ),
              ),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                  te
                      ? '${back['days']} రోజులుగా రాని regular customers'
                      : 'Regular customers not seen for ${back['days']} days',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(
                  key: const Key('askodoxWinbackMessage'),
                  controller: _message,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: te ? 'Message draft (మార్చుకోవచ్చు)' : 'Message draft (you can change it)',
                      helperText: te
                          ? 'ASKODOX తనంతట పంపదు. WhatsApp లో తెరుస్తాం, మీరే పంపాలి.'
                          : 'ASKODOX never sends it. It opens in WhatsApp for you to send.')),
              for (final p in people) _personCard(p, te),
            ],
          ]);
        },
      ),
    );
  }

  Widget _supplierCard(AskodoxJson group, bool te) {
    final lines = askodoxPosList(group['lines']);
    return Card(
      key: ValueKey('askodoxAutoSupplier-${group['supplier_id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${group['supplier']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(te
                  ? '${l['name']}: ఉన్నది ${askodoxQtyText(l['stock_milli'])} · order ${askodoxQtyText(l['qty_milli'])} ${l['unit']}'
                  : '${l['name']}: have ${askodoxQtyText(l['stock_milli'])} · order ${askodoxQtyText(l['qty_milli'])} ${l['unit']}'),
            ),
          const SizedBox(height: 8),
          FilledButton(
              key: ValueKey('askodoxAutoDraft-${group['supplier_id']}'),
              onPressed: _busy ? null : () => _draft(group, te),
              child: Text(te ? 'Order draft చేయి (పంపదు)' : 'Make an order draft (not sent)')),
          _putAwayRow('low_stock', '${group['ref']}', te),
        ]),
      ),
    );
  }

  Widget _personCard(AskodoxJson person, bool te) {
    return Card(
      key: ValueKey('askodoxAutoPerson-${person['customer_id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${person['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(te
              ? '${person['days']} రోజులుగా రాలేదు · ముందు ${person['bills']} బిల్లులు'
              : 'Not seen for ${person['days']} days · ${person['bills']} bills before'),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
              key: ValueKey('askodoxAutoWhatsApp-${person['customer_id']}'),
              onPressed: () => _whatsapp(person, te),
              icon: const Icon(Icons.send_rounded),
              label: Text(te ? 'WhatsApp లో తెరువు' : 'Open in WhatsApp')),
          _putAwayRow('winback', '${person['ref']}', te),
        ]),
      ),
    );
  }

  Widget _putAwayRow(String kind, String card, bool te) => Row(children: [
        TextButton(
            key: ValueKey('askodoxAutoNotNow-$card'),
            onPressed: () => _putAway(kind, card, forever: false),
            child: Text(te ? 'వద్దు' : 'Not now')),
        TextButton(
            key: ValueKey('askodoxAutoNever-$card'),
            onPressed: () => _putAway(kind, card, forever: true),
            child: Text(te ? 'ఇక చూపించకు' : 'Do not show again')),
      ]);
}
