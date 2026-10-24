import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Shop advance (store credit). ASKODOX only keeps the record: the money is
/// with the shop. Every deposit, deduction and refund waits for the
/// CUSTOMER's own approval in their ASKODOX app; the shop can never lower
/// the balance by itself. The terms text always comes from the server.

String askodoxAdvanceErrorText(Object e, bool te) {
  if (e is! AskodoxPosException) return te ? 'కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'That did not work. Please try again.';
  return switch (e.code) {
    'advance_off' => te ? 'ఈ షాప్‌లో షాప్ అడ్వాన్స్ ఆన్‌లో లేదు.' : 'Shop advance is not turned on for this shop.',
    'terms' => te ? 'ముందు నిబంధనలు చదివి అంగీకరించండి.' : 'Read and accept the terms first.',
    'max_balance' => te ? 'ఇది షాప్ పెట్టిన గరిష్ఠ పరిమితి దాటుతుంది.' : 'This would go over the shop\'s limit.',
    'insufficient' => te ? 'అడ్వాన్స్ బ్యాలెన్స్ ఈ మొత్తం కంటే తక్కువ.' : 'The advance balance is less than this amount.',
    'more_than_due' => te ? 'బాకీ ఉన్నంత వరకే అడ్వాన్స్ నుంచి కట్టవచ్చు.' : 'Only what is owed can be paid from the advance.',
    'customer_phone' => te
        ? 'కస్టమర్ మొబైల్ నంబర్ చేర్చండి — వారు తమ ASKODOX యాప్‌లో ఆమోదిస్తారు.'
        : 'Add the customer\'s mobile number — they approve in their own ASKODOX app.',
    'status' => te ? 'ఈ అభ్యర్థన ఇప్పటికే ముగిసింది.' : 'This request is already closed.',
    _ => e.message(te),
  };
}

String askodoxAdvanceKindText(String kind, bool te) => switch (kind) {
      'deposit' => te ? 'అడ్వాన్స్ జమ' : 'Advance paid',
      'redeem' => te ? 'బిల్లుకు వాడకం' : 'Used for a bill',
      'refund' => te ? 'తిరిగి ఇచ్చింది' : 'Refunded',
      _ => kind,
    };

String askodoxAdvanceStatusText(String status, bool te) => switch (status) {
      'pending' => te ? 'కస్టమర్ ఆమోదం కోసం' : 'Waiting for the customer',
      'approved' => te ? 'ఆమోదించారు' : 'Approved',
      'rejected' => te ? 'తిరస్కరించారు' : 'Rejected',
      'withdrawn' => te ? 'షాప్ వెనక్కి తీసుకుంది' : 'Withdrawn by the shop',
      'expired' => te ? 'గడువు ముగిసింది' : 'Expired',
      _ => status,
    };

String _terms(AskodoxJson data, bool te) => '${askodoxPosMap(data['terms'])[te ? 'te' : 'en'] ?? ''}';

class _TermsBox extends StatelessWidget {
  const _TermsBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxAdvanceTerms'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFF59E0B)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

// ------------------------------------------------------------- owner settings
class AskodoxPosAdvanceSettingsScreen extends ConsumerStatefulWidget {
  const AskodoxPosAdvanceSettingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosAdvanceSettingsScreen> createState() => _AskodoxPosAdvanceSettingsScreenState();
}

class _AskodoxPosAdvanceSettingsScreenState extends ConsumerState<AskodoxPosAdvanceSettingsScreen> {
  AskodoxJson? _data;
  Object? _error;
  bool _accepted = false;
  bool _busy = false;
  final _limit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).advanceSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _limit.text = askodoxPaise(askodoxPosInt(d['max_balance_paise']), symbol: false);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(bool enabled) async {
    final te = askodoxPosTe(context);
    final d = _data;
    if (d == null) return;
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).updateAdvanceSettings(widget.businessId, {
        'enabled': enabled,
        'max_balance_paise': askodoxParsePaise(_limit.text) ?? askodoxPosInt(d['max_balance_paise']),
        if (enabled) 'accept_terms_version': d['terms_version'],
      });
      if (mounted) setState(() => _data = out);
    } catch (e) {
      if (mounted) askodoxPosSnack(context, askodoxAdvanceErrorText(e, te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ అడ్వాన్స్' : 'Shop advance')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxAdvanceSettings'), padding: const EdgeInsets.all(12), children: [
                  Text(
                    te
                        ? 'కస్టమర్లు ముందుగా డబ్బు ఇస్తే, అది వారి పేరు మీద నమోదు అవుతుంది; తర్వాత బిల్లులకు వాడుకోవచ్చు. ప్రతి మార్పుకీ కస్టమర్ తమ యాప్‌లో ఆమోదించాలి — మీరు సొంతంగా బ్యాలెన్స్ తగ్గించలేరు.'
                        : 'When customers pay in advance it is recorded in their name and used for later bills. The customer approves every change in their own app — you can never lower the balance by yourself.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  _TermsBox(text: _terms(d, te)),
                  const SizedBox(height: 12),
                  AskodoxPosField(
                    controller: _limit,
                    number: true,
                    label: te ? 'ఒక్కో కస్టమర్ గరిష్ఠ అడ్వాన్స్ (₹)' : 'Most advance per customer (₹)',
                    hint: '${te ? 'గరిష్ఠం' : 'at most'} ${askodoxPaise(askodoxPosInt(d['hard_max_paise']))}',
                  ),
                  if (d['enabled'] == true) ...[
                    ListTile(
                      key: const Key('askodoxAdvanceOn'),
                      leading: const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
                      title: Text(te ? 'ఆన్‌లో ఉంది' : 'Turned on'),
                    ),
                    Row(children: [
                      FilledButton(onPressed: _busy ? null : () => _save(true), child: Text(te ? 'పరిమితి సేవ్' : 'Save limit')),
                      const SizedBox(width: 8),
                      OutlinedButton(
                          key: const Key('askodoxAdvanceTurnOff'),
                          onPressed: _busy ? null : () => _save(false),
                          child: Text(te ? 'ఆఫ్ చేయి' : 'Turn off')),
                    ]),
                  ] else ...[
                    CheckboxListTile(
                      key: const Key('askodoxAdvanceAccept'),
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(te ? 'పై నిబంధనలు చదివాను, అంగీకరిస్తున్నాను' : 'I have read and accept the terms above'),
                    ),
                    FilledButton(
                      key: const Key('askodoxAdvanceTurnOn'),
                      onPressed: _accepted && !_busy ? () => _save(true) : null,
                      child: Text(te ? 'ఆన్ చేయి' : 'Turn on'),
                    ),
                  ],
                ]),
    );
  }
}

// ------------------------------------------------------------- shop: one customer
/// The advance block on a customer's account screen.
class AskodoxPosCustomerAdvanceCard extends ConsumerStatefulWidget {
  const AskodoxPosCustomerAdvanceCard({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  ConsumerState<AskodoxPosCustomerAdvanceCard> createState() => _AskodoxPosCustomerAdvanceCardState();
}

class _AskodoxPosCustomerAdvanceCardState extends ConsumerState<AskodoxPosCustomerAdvanceCard> {
  AskodoxJson? _view;
  bool _off = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final settings = await repo.advanceSettings(widget.businessId);
      if (settings['enabled'] != true) {
        if (mounted) setState(() => _off = true);
        return;
      }
      final view = await repo.customerAdvance(widget.businessId, widget.customerId);
      if (mounted) {
        setState(() {
          _off = false;
          _view = view;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _off = true);
    }
  }

  Future<void> _request(String kind) async {
    final te = askodoxPosTe(context);
    final view = _view;
    final amount = TextEditingController(
        text: kind == 'redeem' && view != null
            ? askodoxPaise(
                [askodoxPosInt(view['due_paise']), askodoxPosInt(view['balance_paise'])].reduce((a, b) => a < b ? a : b),
                symbol: false)
            : '');
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(switch (kind) {
            'deposit' => te ? 'అడ్వాన్స్ తీసుకున్నాం' : 'Advance received',
            'redeem' => te ? 'బాకీ అడ్వాన్స్ నుంచి కట్టు' : 'Pay dues from advance',
            _ => te ? 'అడ్వాన్స్ తిరిగి ఇవ్వు' : 'Refund advance',
          }),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (kind != 'redeem')
              Wrap(spacing: 6, children: [
                for (final m in ['cash', 'upi', 'bank_transfer'])
                  ChoiceChip(
                      key: ValueKey('askodoxAdvanceMethod-$m'),
                      label: Text(m),
                      selected: method == m,
                      onSelected: (_) => setLocal(() => method = m)),
              ]),
            AskodoxPosField(controller: amount, number: true, label: te ? 'మొత్తం (₹)' : 'Amount (₹)'),
            Text(
              te ? 'కస్టమర్ తమ ASKODOX యాప్‌లో ఆమోదించిన తర్వాతే ఇది లెక్కలోకి వస్తుంది.' : 'This counts only after the customer approves it in their ASKODOX app.',
              style: const TextStyle(fontSize: 12),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxAdvanceSend'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(te ? 'ఆమోదానికి పంపు' : 'Send for approval')),
          ],
        ),
      ),
    );
    final paise = askodoxParsePaise(amount.text);
    if (ok != true || paise == null || paise <= 0 || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).requestAdvance(widget.businessId, widget.customerId, kind, {
        'amount_paise': paise,
        if (kind != 'redeem') 'method': method,
        'client_txn_id': askodoxNewTxnId(),
      });
      if (mounted) {
        askodoxPosSnack(context, te ? 'కస్టమర్ ఆమోదం కోసం పంపాం.' : 'Sent to the customer for approval.');
        await _load();
      }
    } catch (e) {
      if (mounted) askodoxPosSnack(context, askodoxAdvanceErrorText(e, te));
    }
  }

  Future<void> _withdraw(String entryId) async {
    final te = askodoxPosTe(context);
    try {
      await ref.read(askodoxPosRepositoryProvider).withdrawAdvance(widget.businessId, entryId);
      await _load();
    } catch (e) {
      if (mounted) askodoxPosSnack(context, askodoxAdvanceErrorText(e, te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final view = _view;
    if (_off || view == null) return const SizedBox.shrink();
    final entries = askodoxPosList(view['entries']);
    final pending = entries.where((e) => e['status'] == 'pending').toList();
    return Card(
      key: const Key('askodoxPosAdvanceCard'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(te ? 'షాప్ అడ్వాన్స్' : 'Shop advance', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Text(askodoxPaise(askodoxPosInt(view['balance_paise'])),
                key: const Key('askodoxPosAdvanceBalance'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            IconButton(tooltip: te ? 'రిఫ్రెష్' : 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
          for (final e in pending)
            ListTile(
              key: ValueKey('askodoxPosAdvancePending-${e['id']}'),
              dense: true,
              leading: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309)),
              title: Text('${askodoxAdvanceKindText('${e['kind']}', te)} · ${askodoxPaise(askodoxPosInt(e['amount_paise']))}'),
              subtitle: Text(askodoxAdvanceStatusText('pending', te)),
              trailing: TextButton(onPressed: () => _withdraw('${e['id']}'), child: Text(te ? 'వెనక్కి' : 'Withdraw')),
            ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton(
                key: const Key('askodoxPosAdvanceDeposit'),
                onPressed: () => _request('deposit'),
                child: Text(te ? '+ అడ్వాన్స్' : '+ Advance')),
            if (askodoxPosInt(view['balance_paise']) > 0 && askodoxPosInt(view['due_paise']) > 0)
              OutlinedButton(
                  key: const Key('askodoxPosAdvanceRedeem'),
                  onPressed: () => _request('redeem'),
                  child: Text(te ? 'బాకీ అడ్వాన్స్‌తో కట్టు' : 'Pay dues from advance')),
            if (askodoxPosInt(view['balance_paise']) > 0)
              TextButton(
                  key: const Key('askodoxPosAdvanceRefund'),
                  onPressed: () => _request('refund'),
                  child: Text(te ? 'తిరిగి ఇవ్వు' : 'Refund')),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- customer: my advances
class AskodoxMyShopAdvancesScreen extends ConsumerStatefulWidget {
  const AskodoxMyShopAdvancesScreen({super.key});

  @override
  ConsumerState<AskodoxMyShopAdvancesScreen> createState() => _AskodoxMyShopAdvancesScreenState();
}

class _AskodoxMyShopAdvancesScreenState extends ConsumerState<AskodoxMyShopAdvancesScreen> {
  AskodoxJson? _data;
  Object? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).myAdvances();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<bool> _acceptTerms(String shop) async {
    final te = askodoxPosTe(context);
    var accepted = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(te ? '$shop — షాప్ అడ్వాన్స్' : '$shop — shop advance'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _TermsBox(text: _terms(_data ?? const {}, te)),
              CheckboxListTile(
                key: const Key('askodoxMyAdvanceAccept'),
                value: accepted,
                onChanged: (v) => setLocal(() => accepted = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(te ? 'చదివాను, అర్థమైంది, అంగీకరిస్తున్నాను' : 'I have read, understood and accept this'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxMyAdvanceAcceptOk'),
                onPressed: accepted ? () => Navigator.pop(ctx, true) : null,
                child: Text(te ? 'కొనసాగు' : 'Continue')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _decide(AskodoxJson shop, AskodoxJson entry, bool approve) async {
    final te = askodoxPosTe(context);
    String? terms;
    if (approve && shop['accepted_terms'] != true) {
      if (!await _acceptTerms('${shop['shop']}')) return;
      terms = '${_data?['terms_version']}';
    }
    final id = '${entry['id']}';
    setState(() => _busy.add(id));
    try {
      await ref.read(askodoxPosRepositoryProvider).decideAdvance(id, approve: approve, acceptTermsVersion: terms);
      if (mounted) {
        askodoxPosSnack(context, approve ? (te ? 'ఆమోదించారు.' : 'Approved.') : (te ? 'తిరస్కరించారు.' : 'Rejected.'));
      }
    } catch (e) {
      if (mounted) askodoxPosSnack(context, askodoxAdvanceErrorText(e, te));
    } finally {
      _busy.remove(id);
      await _load();
    }
  }

  String _ask(AskodoxJson e, String shop, bool te) {
    final amount = askodoxPaise(askodoxPosInt(e['amount_paise']));
    return switch ('${e['kind']}') {
      'deposit' => te ? 'మీరు $shop కి $amount అడ్వాన్స్ ఇచ్చారా?' : 'Did you give $shop $amount as an advance?',
      'redeem' => te ? 'మీ బాకీ కోసం మీ అడ్వాన్స్ నుంచి $amount తీసుకోవచ్చా?' : 'May $shop take $amount from your advance for your dues?',
      _ => te ? '$shop మీకు $amount తిరిగి ఇచ్చిందా?' : 'Did $shop give you $amount back?',
    };
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final shops = d == null ? const <AskodoxJson>[] : askodoxPosList(d['shops']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ అడ్వాన్సులు' : 'Shop advances')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(key: const Key('askodoxMyAdvances'), padding: const EdgeInsets.all(12), children: [
                    _TermsBox(text: _terms(d, te)),
                    const SizedBox(height: 10),
                    if (shops.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(te ? 'ఏ షాప్‌లోనూ అడ్వాన్స్ లేదు.' : 'No shop advances yet.', key: const Key('askodoxMyAdvancesEmpty')),
                      ),
                    for (final shop in shops)
                      Card(
                        key: ValueKey('askodoxMyAdvanceShop-${shop['business_id']}'),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${shop['shop']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                              Text(askodoxPaise(askodoxPosInt(shop['balance_paise'])),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            ]),
                            for (final e in askodoxPosList(shop['pending']))
                              Container(
                                key: ValueKey('askodoxMyAdvancePending-${e['id']}'),
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_ask(e, '${shop['shop']}', te), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    FilledButton(
                                      key: ValueKey('askodoxMyAdvanceApprove-${e['id']}'),
                                      onPressed: _busy.contains('${e['id']}') ? null : () => _decide(shop, e, true),
                                      child: Text(te ? 'అవును, ఆమోదిస్తున్నా' : 'Yes, approve'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      key: ValueKey('askodoxMyAdvanceReject-${e['id']}'),
                                      onPressed: _busy.contains('${e['id']}') ? null : () => _decide(shop, e, false),
                                      child: Text(te ? 'కాదు' : 'No'),
                                    ),
                                  ]),
                                ]),
                              ),
                            for (final e in askodoxPosList(shop['history']).take(10))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${askodoxAdvanceKindText('${e['kind']}', te)} · '
                                    '${askodoxPaise(askodoxPosInt(e['amount_paise']))}'),
                                subtitle: Text('${askodoxAdvanceStatusText('${e['status']}', te)} · '
                                    '${'${e['decided_at'] ?? e['requested_at'] ?? ''}'.split('T').first}'),
                              ),
                          ]),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
