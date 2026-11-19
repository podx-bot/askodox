import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _dayClock(DateTime t, bool te) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? _clock(t) : '${t.day}/${t.month} ${_clock(t)}';
}

/// Customer: reserve a table ahead of time (owner 2026-11-19). Pick when you will come and how many people; the
/// tables free around that time are listed; one tap reserves. Returns true when a table was reserved.
Future<bool> askodoxReserveTable(BuildContext context, WidgetRef ref, String businessId, String shopName) async {
  final te = askodoxPosTe(context);
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _ReserveSheet(businessId: businessId, shopName: shopName, te: te),
  );
  return done == true;
}

class _ReserveSheet extends ConsumerStatefulWidget {
  const _ReserveSheet({required this.businessId, required this.shopName, required this.te});
  final String businessId;
  final String shopName;
  final bool te;

  @override
  ConsumerState<_ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends ConsumerState<_ReserveSheet> {
  int _minutes = 60;
  DateTime? _picked;
  int _people = 2;
  List<AskodoxJson>? _tables;
  bool _hasTables = true;
  bool _busy = false;
  String? _error;
  final _txn = askodoxNewTxnId();

  DateTime get _at => _picked ?? DateTime.now().add(Duration(minutes: _minutes));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _tables = null;
      _error = null;
    });
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).freeTables(widget.businessId, _at.toUtc().toIso8601String(), _people);
      if (!mounted) return;
      setState(() {
        _tables = askodoxPosList(out['tables']);
        _hasTables = out['has_tables'] != false;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() {
          _tables = const [];
          _error = e.message(widget.te);
        });
      }
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (time == null) return;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1)); // a time already past today = tomorrow
    setState(() => _picked = at);
    await _load();
  }

  Future<void> _book(AskodoxJson table) async {
    final te = widget.te;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).reserveTable(widget.businessId, {
        'table_id': table['id'],
        'at': _at.toUtc().toIso8601String(),
        'people': _people,
        'client_txn_id': _txn,
      });
      messenger.showSnackBar(SnackBar(
          content: Text(te
              ? '${out['table_name']} రిజర్వ్ అయింది ✓ ${_dayClock(_at, te)} · 15 నిమిషాలు ఆగుతుంది'
              : '${out['table_name']} reserved ✓ ${_dayClock(_at, te)} · held for 15 minutes')));
      navigator.pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() => _error = e.message(te));
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final tables = _tables;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.shopName} · ${te ? 'టేబుల్ రిజర్వ్' : 'Reserve a table'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Text(te ? 'ఎప్పుడు వస్తారు?' : 'When will you come?', style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, children: [
            for (final (m, en, tel) in const [(30, '30 min', '30 నిమిషాల్లో'), (60, '1 hour', '1 గంటలో'), (120, '2 hours', '2 గంటల్లో')])
              ChoiceChip(
                key: ValueKey('askodoxReserveIn-$m'),
                label: Text(te ? tel : en),
                selected: _picked == null && _minutes == m,
                onSelected: (_) {
                  setState(() {
                    _picked = null;
                    _minutes = m;
                  });
                  _load();
                },
              ),
            ChoiceChip(
              key: const Key('askodoxReservePick'),
              label: Text(_picked == null ? (te ? 'టైమ్ ఎంచుకో' : 'Pick a time') : _dayClock(_picked!, te)),
              selected: _picked != null,
              onSelected: (_) => _pickTime(),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(te ? 'ఎంత మంది?' : 'How many people?', style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                key: const Key('askodoxReservePeopleLess'),
                onPressed: _people <= 1
                    ? null
                    : () {
                        setState(() => _people--);
                        _load();
                      },
                icon: const Icon(Icons.remove_circle_outline)),
            Text('$_people', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            IconButton(
                key: const Key('askodoxReservePeopleMore'),
                onPressed: _people >= 20
                    ? null
                    : () {
                        setState(() => _people++);
                        _load();
                      },
                icon: const Icon(Icons.add_circle)),
          ]),
          if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
          const SizedBox(height: 4),
          if (tables == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (!_hasTables)
            Text(te ? 'ఈ షాప్ ఇంకా టేబుల్స్ పెట్టలేదు.' : 'This shop has not set up its tables yet.')
          else if (tables.isEmpty)
            Text(te ? 'ఆ సమయానికి ఖాళీ టేబుల్ లేదు. వేరే టైమ్ ఎంచుకోండి.' : 'No table is free at that time. Try another time.')
          else ...[
            Text('${te ? 'ఖాళీ టేబుల్స్' : 'Free tables'} · ${_dayClock(_at, te)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .35),
              child: ListView(shrinkWrap: true, children: [
                for (final t in tables)
                  ListTile(
                    key: ValueKey('askodoxReserveTable-${t['id']}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.table_restaurant_outlined),
                    title: Text('${t['name']}${'${t['area'] ?? ''}'.isEmpty ? '' : ' · ${t['area']}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${t['seats']} ${te ? 'సీట్లు' : 'seats'}'),
                    trailing: FilledButton(
                      onPressed: _busy ? null : () => _book(t),
                      child: Text(te ? 'రిజర్వ్' : 'Reserve'),
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Shop: today's reservations (arrived / cancel). Opened from the Tables screen.
Future<void> askodoxShowShopReservations(BuildContext context, WidgetRef ref, String businessId) async {
  final te = askodoxPosTe(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _ShopReservations(businessId: businessId, te: te),
  );
}

class _ShopReservations extends ConsumerStatefulWidget {
  const _ShopReservations({required this.businessId, required this.te});
  final String businessId;
  final bool te;

  @override
  ConsumerState<_ShopReservations> createState() => _ShopReservationsState();
}

class _ShopReservationsState extends ConsumerState<_ShopReservations> {
  List<AskodoxJson>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(askodoxPosRepositoryProvider).shopReservations(widget.businessId);
      if (mounted) setState(() => _rows = rows);
    } on AskodoxPosException catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  Future<void> _set(String id, String status) async {
    try {
      await ref.read(askodoxPosRepositoryProvider).shopReservationStatus(widget.businessId, id, status);
    } on AskodoxPosException catch (_) {
      // the reload below shows the real state
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final rows = _rows;
    String label(String s) => switch (s) {
          'booked' => te ? 'రిజర్వ్ అయింది' : 'Reserved',
          'arrived' => te ? 'వచ్చారు' : 'Arrived',
          'no_show' => te ? 'రాలేదు' : 'Did not come',
          _ => te ? 'రద్దు' : 'Cancelled',
        };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'టేబుల్ రిజర్వేషన్లు' : 'Table reservations', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Text(te ? 'ఇప్పుడు రిజర్వేషన్లు లేవు.' : 'No reservations right now.')
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .6),
              child: ListView(shrinkWrap: true, children: [
                for (final r in rows)
                  ListTile(
                    key: ValueKey('askodoxShopReservation-${r['id']}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_seat_outlined),
                    title: Text(
                        '${r['table_name']} · ${_dayClock(DateTime.tryParse('${r['at']}')?.toLocal() ?? DateTime.now(), te)} · ${r['people']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${'${r['customer_name'] ?? ''}'.isEmpty ? '' : '${r['customer_name']} · '}${label('${r['status']}')}'),
                    trailing: '${r['status']}' != 'booked'
                        ? null
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(onPressed: () => _set('${r['id']}', 'arrived'), child: Text(te ? 'వచ్చారు' : 'Arrived')),
                            IconButton(
                                tooltip: te ? 'రద్దు' : 'Cancel',
                                onPressed: () => _set('${r['id']}', 'cancelled'),
                                icon: const Icon(Icons.close_rounded, color: Color(0xFFB42318))),
                          ]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
