import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import 'delivery_jobs_screens.dart' show askodoxRupee;
import 'pos_common.dart';

/// Owner 2026-11-24 ("must work for businesses with multiple branches"): the owner links his OWN shops; their delivery
/// people become one pool and he sees today for every branch together. Each branch keeps its own bills and GST.
class AskodoxBranchesScreen extends ConsumerStatefulWidget {
  const AskodoxBranchesScreen({super.key});

  @override
  ConsumerState<AskodoxBranchesScreen> createState() => _BranchesState();
}

class _BranchesState extends ConsumerState<AskodoxBranchesScreen> {
  List<AskodoxJson> _shops = const [];
  List<AskodoxJson> _groups = const [];
  final Set<String> _picked = {};
  final Map<String, AskodoxJson> _today = {};
  bool _loaded = false;

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
    try {
      await _repo.saveBranches('', _picked.toList());
      _picked.clear();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా అన్ని శాఖలు' : 'All my branches')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              for (final g in _groups) ...[
                Text('${g['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                if (_today['${g['id']}'] != null) ..._overview(te, _today['${g['id']}']!),
                const SizedBox(height: 14),
              ],
              Text(te ? 'శాఖలను లింక్ చేయండి' : 'Link your shops', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(te ? 'రెండు లేదా ఎక్కువ షాపులు టిక్ చేయండి.' : 'Tick two or more of your own shops.'),
              for (final s in _shops)
                CheckboxListTile(
                  key: ValueKey('askodoxBranchPick-${s['id']}'),
                  value: _picked.contains('${s['id']}'),
                  title: Text('${s['name']}'),
                  onChanged: (v) => setState(() => v == true ? _picked.add('${s['id']}') : _picked.remove('${s['id']}')),
                ),
              FilledButton(
                key: const ValueKey('askodoxBranchLink'),
                onPressed: _picked.length >= 2 ? _link : null,
                child: Text(te ? 'లింక్' : 'Link'),
              ),
            ]),
    );
  }

  List<Widget> _overview(bool te, AskodoxJson ov) {
    final total = (ov['total'] as Map?)?.cast<String, Object?>() ?? const {};
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${te ? 'ఈ రోజు మొత్తం' : 'Today, all branches'}: ${askodoxRupee(total['sales_paise'])} · ${total['invoices']} ${te ? 'బిల్లులు' : 'bills'}'
                ' · ${total['delivery_done']} ${te ? 'డెలివరీలు' : 'deliveries'} · ${te ? 'బాకీ' : 'Dues'} ${askodoxRupee(total['dues_paise'])}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const Divider(),
            for (final b in askodoxPosList(ov['branches']))
              Row(children: [
                Expanded(child: Text('${b['name']}')),
                Text('${askodoxRupee(b['sales_paise'])} · ${b['invoices']}'),
                IconButton(
                  key: ValueKey('askodoxBranchRemove-${b['id']}'),
                  tooltip: te ? 'తీసేయి' : 'Remove',
                  icon: const Icon(Icons.link_off_rounded, size: 20),
                  onPressed: () async {
                    try {
                      await _repo.leaveBranches('${b['id']}');
                      await _load();
                    } on AskodoxPosException catch (e) {
                      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
                    }
                  },
                ),
              ]),
          ]),
        ),
      ),
    ];
  }
}
