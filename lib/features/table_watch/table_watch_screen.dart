import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../pos/data/pos_repository.dart';
import '../pos/presentation/pos_common.dart';
import 'table_watch_logic.dart';

/// How often the open page reads the tables again.
const askodoxTableWatchRefresh = Duration(seconds: 30);

/// Table watch (owner 2026-11-27, design canvas "టేబుల్ వాచ్"): every table with who is sitting and for how long;
/// a table nobody has gone to is on top. The table's own QR is the signal -- no camera. Tap a table to act.
class AskodoxTableWatchScreen extends ConsumerStatefulWidget {
  const AskodoxTableWatchScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxTableWatchScreen> createState() => _AskodoxTableWatchScreenState();
}

class _AskodoxTableWatchScreenState extends ConsumerState<AskodoxTableWatchScreen> {
  AskodoxJson? _data;
  Object? _error;
  Timer? _timer;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(askodoxTableWatchRefresh, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final out = await _repo.tableWatch(widget.businessId);
      if (mounted) {
        setState(() {
          _data = out;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<AskodoxJson> Function() call) async {
    try {
      await call();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
    if (mounted) await _load();
  }

  void _openOrder(AskodoxJson t) {
    final pos = '${t['pos_order_id'] ?? ''}';
    context.push(pos.isNotEmpty ? '/pos/${widget.businessId}/order/$pos' : '/desk/${widget.businessId}');
  }

  Future<void> _tap(AskodoxJson t) async {
    final te = _te;
    final state = '${t['state']}';
    final id = '${t['id']}';
    if (state == 'empty') {
      askodoxPosSnack(context, te ? 'ఈ టేబుల్ ఖాళీగా ఉంది.' : 'This table is free.');
      return;
    }
    if (state == 'waiting' || state == 'eating') {
      _openOrder(t);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${te ? 'టేబుల్' : 'Table'} ${t['name']} · ${askodoxTableWatchTime(state, askodoxPosInt(t['minutes']))}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (t['seen'] != true)
              FilledButton(
                key: const Key('askodoxTableWatchSeen'),
                onPressed: () {
                  Navigator.of(sheet).pop();
                  unawaited(_act(() => _repo.tableWatchSeen(widget.businessId, id)));
                },
                child: Text(te ? 'నేను వెళ్తున్నా' : 'I am going'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('askodoxTableWatchTakeOrder'),
              onPressed: () {
                Navigator.of(sheet).pop();
                context.push('/pos/${widget.businessId}/tables');
              },
              child: Text(te ? 'ఆర్డర్ తీసుకో' : 'Take the order'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('askodoxTableWatchFree'),
              onPressed: () {
                Navigator.of(sheet).pop();
                unawaited(_act(() => _repo.tableWatchFree(widget.businessId, id)));
              },
              child: Text(te ? 'వెళ్ళిపోయారు · టేబుల్ ఖాళీ' : 'They left · table is free'),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final data = _data;
    return Scaffold(
      key: const Key('askodoxTableWatch'),
      appBar: AppBar(title: Text(te ? 'టేబుల్ వాచ్' : 'Table watch')),
      body: SafeArea(
        child: _error != null && data == null
            ? AskodoxPosError(error: _error!, onRetry: _load)
            : data == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(onRefresh: _load, child: _body(data, te)),
      ),
    );
  }

  Widget _body(AskodoxJson data, bool te) {
    final tables = askodoxTableWatchOrder(askodoxPosList(data['tables']));
    final alerts = askodoxPosList(data['alerts']);
    final counts = askodoxPosMap(data['counts']);
    final sitting = askodoxPosInt(counts['seated']) + askodoxPosInt(counts['unseen']) + askodoxPosInt(counts['waiting']) +
        askodoxPosInt(counts['eating']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text(te ? 'ఎవరు కూర్చున్నారు, ఎంతసేపైంది' : 'Who is sitting, and for how long',
          style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 8),
      Text('$sitting / ${tables.length}',
          key: const Key('askodoxTableWatchBusy'),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
      Text(te ? 'నిండిన టేబుల్స్' : 'Busy tables', style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 12),
      for (final a in alerts)
        Card(
          key: ValueKey('askodoxTableWatchAlert-${a['table_id']}'),
          color: AskodoxLook.accent,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.notifications_active_rounded, color: AskodoxLook.onAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(askodoxTableWatchAlert('${a['table_name']}', askodoxPosInt(a['minutes']), te),
                    style: const TextStyle(color: AskodoxLook.onAccent, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      if (tables.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(te ? 'ముందు "టేబుల్స్" పేజీలో టేబుల్స్ చేర్చండి.' : 'Add your tables on the Tables page first.',
              key: const Key('askodoxTableWatchNone'), textAlign: TextAlign.center),
        ),
      const SizedBox(height: 4),
      Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tables) _tile(t, te)]),
      const SizedBox(height: 16),
      Text(
          te
              ? 'టేబుల్ మీది QR స్కాన్ చేసిన క్షణం నుంచి సమయం లెక్కిస్తుంది. కెమెరా పెట్టాల్సిన పని ఉండదు. '
                  '${askodoxPosInt(data['unseen_minutes'])} నిమిషాలు దాటితే సిబ్బందికి నోటిఫికేషన్ వెళ్తుంది.'
              : 'The time counts from the moment the table’s QR is scanned. No camera is needed. '
                  'After ${askodoxPosInt(data['unseen_minutes'])} minutes the staff get a notification.',
          key: const Key('askodoxTableWatchNote'),
          style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
    ]);
  }

  Widget _tile(AskodoxJson t, bool te) {
    final state = '${t['state']}';
    final unseen = state == 'unseen';
    final border = switch (state) {
      'unseen' => AskodoxLook.accent,
      'seated' || 'waiting' => AskodoxLook.accentText,
      'eating' => AskodoxLook.good,
      _ => AskodoxLook.line,
    };
    final ink = unseen ? AskodoxLook.onAccent : AskodoxLook.text;
    final time = askodoxTableWatchTime(state, askodoxPosInt(t['minutes']));
    return SizedBox(
      width: 150,
      height: 104,
      child: InkWell(
        key: ValueKey('askodoxTableWatchTable-${t['id']}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(_tap(t)),
        child: Ink(
          decoration: BoxDecoration(
            color: unseen ? AskodoxLook.accent : AskodoxLook.cardA,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: state == 'empty' ? 1 : 2),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Expanded(
                child: Text('${t['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              ),
              if (time.isNotEmpty)
                Text(time,
                    key: ValueKey('askodoxTableWatchTime-${t['id']}'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: ink, fontFeatures: AskodoxLook.figures)),
            ]),
            const SizedBox(height: 4),
            Text(askodoxTableWatchText(state, te),
                key: ValueKey('askodoxTableWatchState-${t['id']}'),
                maxLines: 2,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: state == 'empty' ? AskodoxLook.muted : ink)),
          ]),
        ),
      ),
    );
  }
}
