import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/delivery_jobs_screens.dart' show askodoxRupee;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 23): all my branches `/me/branches`. Top = today's sales of every linked branch
/// together, middle = ONE list of the branches (tap = take it out of the link), bottom = ONE big button (link shops).
/// Each branch keeps its own bills and GST; only the delivery people become one pool. Old page stays at `?full=1`.
class AskodoxBranchesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBranchesStepsScreen({super.key});

  @override
  ConsumerState<AskodoxBranchesStepsScreen> createState() => _BranchesStepsState();
}

class _BranchesStepsState extends ConsumerState<AskodoxBranchesStepsScreen> {
  List<AskodoxJson> _shops = const [];
  List<AskodoxJson> _groups = const [];
  final Map<String, AskodoxJson> _today = {};
  bool _loaded = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final out = await _repo.myBranches();
      _shops = askodoxPosList(out['my_shops']);
      _groups = askodoxPosList(out['groups']);
      for (final g in _groups) {
        _today['${g['id']}'] = await _repo.branchesOverview('${g['id']}');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _link() async {
    final te = _te;
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'రెండు లేదా ఎక్కువ షాపులు టిక్ చేయండి' : 'Tick two or more of your own shops',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              for (final s in _shops)
                CheckboxListTile(
                  key: ValueKey('askodoxBranchesStepsPick-${s['id']}'),
                  contentPadding: EdgeInsets.zero,
                  value: picked.contains('${s['id']}'),
                  title: Text('${s['name']}'),
                  onChanged: (v) => setSheet(() => v == true ? picked.add('${s['id']}') : picked.remove('${s['id']}')),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('askodoxBranchesStepsLink'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: picked.length >= 2 ? () => Navigator.pop(ctx, true) : null,
                child: Text(te ? 'లింక్' : 'Link'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.saveBranches('', picked.toList());
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  Future<void> _remove(AskodoxJson b) async {
    final te = _te;
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text('${b['name']}'),
              content: Text(te ? 'ఈ శాఖని లింక్ నుంచి తీసేయాలా? దాని బిల్లులు అలాగే ఉంటాయి.' : 'Take this branch out of the link? Its bills stay as they are.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(te ? 'వద్దు' : 'No')),
                TextButton(key: const Key('askodoxBranchesStepsRemoveYes'), onPressed: () => Navigator.of(dialog).pop(true), child: Text(te ? 'తీసేయి' : 'Remove')),
              ],
            ));
    if (yes != true || !mounted) return;
    try {
      await _repo.leaveBranches('${b['id']}');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా అన్ని శాఖలు' : 'All my branches';
    final more = [
      AskodoxStepMore('askodoxBranchesStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push('/me/branches?full=1')),
    ];
    if (!_loaded) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    var sales = 0;
    var bills = 0;
    final rows = <AskodoxJson>[];
    for (final g in _groups) {
      final ov = _today['${g['id']}'];
      if (ov == null) continue;
      final total = askodoxPosMap(ov['total']);
      sales += askodoxPosInt(total['sales_paise']);
      bills += askodoxPosInt(total['invoices']);
      rows.addAll(askodoxPosList(ov['branches']));
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxBranchesSteps'),
      title: title,
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepBigNumber(askodoxRupee(sales),
            label: rows.isEmpty ? (te ? 'ఇంకా శాఖలు లింక్ చేయలేదు' : 'No branches linked yet') : (te ? 'ఈ రోజు మొత్తం · $bills బిల్లులు' : 'Today, all branches · $bills bills'),
            size: 44),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Padding(
              padding: const EdgeInsets.all(24),
              child: Text(te ? 'మీ సొంత షాపులను లింక్ చేస్తే డెలివరీ వాళ్ళు అన్నిటికీ కలిసి పనిచేస్తారు.' : 'Link your own shops and their delivery people work as one pool.',
                  textAlign: TextAlign.center)),
        for (final b in rows)
          AskodoxStepPersonRow(
            key: ValueKey('askodoxBranchesStepsRow-${b['id']}'),
            name: '${b['name']}',
            sub: '${b['invoices']} ${te ? 'బిల్లులు' : 'bills'}',
            amount: askodoxRupee(b['sales_paise']),
            onTap: () => _remove(b),
          ),
      ]),
      bottom: _shops.length < 2
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxBranchesStepsAdd'),
              label: te ? 'శాఖలను లింక్ చేయి' : 'Link shops',
              icon: Icons.link_rounded,
              onPressed: _link,
            ),
    );
  }
}
