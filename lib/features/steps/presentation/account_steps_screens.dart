import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_advance_screens.dart' show AskodoxPosCustomerAdvanceCard;
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 6): Customer account `/pos/:id/customers/:cid` and Supplier account
/// `/pos/:id/suppliers/:sid`. The account on one screen (balance on top, the month's lines, ONE big button); the
/// money job is 3 steps: how much -> how paid -> done. The old pages stay at `?full=1`.
/// Money is only recorded (ASKODOX never holds it).

class AskodoxCustomerAccountStepsScreen extends StatelessWidget {
  const AskodoxCustomerAccountStepsScreen({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  Widget build(BuildContext context) => _AccountSteps(businessId: businessId, otherId: customerId, supplier: false);
}

class AskodoxSupplierAccountStepsScreen extends StatelessWidget {
  const AskodoxSupplierAccountStepsScreen({super.key, required this.businessId, required this.supplierId});
  final String businessId;
  final String supplierId;

  @override
  Widget build(BuildContext context) => _AccountSteps(businessId: businessId, otherId: supplierId, supplier: true);
}

class _AccountSteps extends ConsumerStatefulWidget {
  const _AccountSteps({required this.businessId, required this.otherId, required this.supplier});
  final String businessId;
  final String otherId;
  final bool supplier;

  @override
  ConsumerState<_AccountSteps> createState() => _AccountState();
}

class _AccountState extends ConsumerState<_AccountSteps> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AskodoxJson? _data;
  Object? _error;
  int _step = 0; // 0 = the account, 1 = how much, 2 = how paid, 3 = done
  String _typed = '';
  String _method = 'cash';
  bool _busy = false;
  int _saved = 0;
  final String _txn = askodoxNewTxnId();

  bool get _te => askodoxPosTe(context);
  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);
  int get _closing => askodoxPosInt(_data?['closing_paise']);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = widget.supplier
          ? await _repo.supplierStatement(widget.businessId, widget.otherId, _ym)
          : await _repo.statement(widget.businessId, widget.otherId, _ym);
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

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _data = null;
    });
    unawaited(_load());
  }

  String get _name => '${askodoxPosMap(_data?[widget.supplier ? 'supplier' : 'customer'])['name'] ?? ''}';

  Future<void> _save() async {
    final te = _te;
    final paise = askodoxKeypadPaise(_typed);
    if (paise <= 0) return;
    setState(() => _busy = true);
    try {
      final body = {'client_txn_id': '$_txn-$_saved', 'method': _method, 'amount_paise': paise, 'reference': ''};
      if (widget.supplier) {
        await _repo.paySupplier(widget.businessId, widget.otherId, body);
      } else {
        await _repo.collect(widget.businessId, widget.otherId, body);
      }
      _saved++;
      await _load();
      if (mounted) setState(() => _step = 3);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxAccountStepsPrev', te ? 'ముందు నెల' : 'Previous month', Icons.chevron_left, () => _shift(-1)),
      AskodoxStepMore('askodoxAccountStepsNext', te ? 'తర్వాత నెల' : 'Next month', Icons.chevron_right, () => _shift(1)),
      if (!widget.supplier)
        AskodoxStepMore('askodoxAccountStepsCrm', te ? 'కస్టమర్ చరిత్ర (CRM)' : 'Customer history (CRM)', Icons.history,
            () => context.push('/pos/$id/crm/customer/${widget.otherId}')),
      AskodoxStepMore(
          'askodoxAccountStepsFull',
          te ? 'పాత ఖాతా పేజీ (షేర్, రిఫరెన్స్)' : 'Old account page (share, reference)',
          Icons.menu_book_rounded,
          () => context.push('/pos/$id/${widget.supplier ? 'suppliers' : 'customers'}/${widget.otherId}?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final sup = widget.supplier;
    final title = sup ? (te ? 'సప్లయర్ ఖాతా' : 'Supplier account') : (te ? 'కస్టమర్ ఖాతా' : 'Customer account');
    switch (_step) {
      case 1:
        return AskodoxStepScaffold(
          key: const Key('askodoxAccountSteps1'),
          title: title,
          sub: _name,
          step: 1,
          question: sup ? (te ? 'ఎంత చెల్లించారు?' : 'How much did you pay?') : (te ? 'ఎంత వచ్చింది?' : 'How much came?'),
          onBack: () => setState(() => _step = 0),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            AskodoxStepAmountPad(
              value: _typed,
              quick: _closing > 0 ? [(te ? 'మొత్తం' : 'All', '${_closing ~/ 100}')] : const [],
              onChanged: (v) => setState(() => _typed = v),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxAccountStepsToMethod'),
            label: te ? 'తర్వాత' : 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: askodoxKeypadPaise(_typed) > 0 ? () => setState(() => _step = 2) : null,
          ),
        );
      case 2:
        return AskodoxStepScaffold(
          key: const Key('askodoxAccountSteps2'),
          title: title,
          sub: _name,
          step: 2,
          question: te ? 'ఎలా?' : 'How was it paid?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            AskodoxStepBigNumber(askodoxStepRupees(askodoxKeypadPaise(_typed)), size: 40),
            const SizedBox(height: 12),
            for (final (k, en, tel, icon) in const [
              ('cash', 'Cash', 'క్యాష్', Icons.payments_outlined),
              ('upi', 'UPI / online', 'UPI / ఆన్‌లైన్', Icons.phone_android),
              ('bank_transfer', 'Bank transfer', 'బ్యాంక్', Icons.account_balance_outlined),
              ('cheque', 'Cheque', 'చెక్', Icons.receipt_long_outlined),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AskodoxStepChoice(
                  key: Key('askodoxAccountStepsMethod-$k'),
                  icon: icon,
                  color: askodoxStepGreen,
                  title: te ? tel : en,
                  sub: '',
                  selected: _method == k,
                  onTap: () => setState(() => _method = k),
                ),
              ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxAccountStepsSave'),
            label: te ? 'సేవ్ ✓' : 'Save ✓',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        );
      case 3:
        return AskodoxStepScaffold(
          key: const Key('askodoxAccountSteps3'),
          title: title,
          sub: _name,
          step: 3,
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
            const Center(child: AskodoxStepDoneMark()),
            const SizedBox(height: 26),
            AskodoxStepBigNumber(
                sup
                    ? (te ? '${askodoxStepRupees(askodoxKeypadPaise(_typed))} చెల్లించాం' : '${askodoxStepRupees(askodoxKeypadPaise(_typed))} paid')
                    : (te ? '${askodoxStepRupees(askodoxKeypadPaise(_typed))} వచ్చింది' : '${askodoxStepRupees(askodoxKeypadPaise(_typed))} received'),
                label: _name,
                size: 32),
            const SizedBox(height: 10),
            Center(
              child: AskodoxStepPill(
                  _closing > 0
                      ? (te ? 'ఇంకా బాకీ ${askodoxStepRupees(_closing)}' : 'Still due ${askodoxStepRupees(_closing)}')
                      : (te ? 'బాకీ లేదు ✓' : 'Nothing due ✓'),
                  kind: _closing > 0 ? 'warn' : 'good'),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxAccountStepsBack'),
            label: te ? 'ఖాతాకి' : 'Back to account',
            icon: Icons.arrow_back_rounded,
            onPressed: () => setState(() {
              _step = 0;
              _typed = '';
            }),
          ),
        );
      default:
        final d = _data;
        final entries = askodoxPosList(d?['entries']);
        return AskodoxStepScaffold(
          key: Key(sup ? 'askodoxSupplierAccountSteps' : 'askodoxCustomerAccountSteps'),
          title: title,
          sub: _name.isEmpty ? _ym : '$_name · $_ym',
          more: _more(),
          body: _error != null && d == null
              ? AskodoxPosError(error: _error!, onRetry: _load)
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                        AskodoxStepBigNumber(askodoxStepRupees(_closing),
                            label: sup ? (te ? 'ఇవ్వాల్సింది' : 'You owe') : (te ? 'రావాల్సిన బాకీ' : 'Baaki to collect'), size: 40),
                        const SizedBox(height: 10),
                        if (!sup) AskodoxPosCustomerAdvanceCard(businessId: widget.businessId, customerId: widget.otherId),
                        if (entries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(te ? 'ఈ నెల ఎంట్రీలు లేవు.' : 'No entries this month.',
                                key: const Key('askodoxAccountStepsNone'), textAlign: TextAlign.center),
                          ),
                        for (var i = 0; i < entries.length; i++) _row(entries[i], i, te),
                      ]),
                    ),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxAccountStepsPay'),
            label: sup ? (te ? 'చెల్లించాం' : 'Paid') : (te ? 'డబ్బు వచ్చింది' : 'Money received'),
            icon: Icons.currency_rupee,
            onPressed: d == null ? null : () => setState(() => _step = 1),
          ),
        );
    }
  }

  Widget _row(AskodoxJson e, int i, bool te) {
    final up = widget.supplier ? askodoxPosInt(e['owed_paise']) != 0 : askodoxPosInt(e['debit_paise']) > 0;
    final amount = widget.supplier
        ? (up ? askodoxPosInt(e['owed_paise']) : askodoxPosInt(e['paid_paise']))
        : (up ? askodoxPosInt(e['debit_paise']) : askodoxPosInt(e['credit_paise']));
    final note = '${e['note'] ?? ''}'.isEmpty || '${e['note']}' == 'null' ? '${e['kind'] ?? ''}' : '${e['note']}';
    return AskodoxStepPersonRow(
      key: Key('askodoxAccountStepsRow-$i'),
      name: note,
      sub: '${e['local_date']}',
      amount: '${up ? '+' : '−'}${askodoxStepRupees(amount)}',
      amountColor: up ? askodoxStepWarn : askodoxStepDone,
      onTap: () {},
    );
  }
}
