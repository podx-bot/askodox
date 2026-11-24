import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise, askodoxParsePaise;
import '../../pos/presentation/collect_qr_sheet.dart';
import '../../pos/presentation/pos_common.dart';

/// Business Kit ways of working 3-5 (owner 2026-11-24, "do all of it"): ONE set of pages for every business that
/// works that way -- bookings (rooms, chairs, doctor, hall, rentals), job cards (repair, tailoring, cake, Mee Seva)
/// and monthly members (milk, tuition, gym, PG). Which shop sees which page comes from its kit (`kit.flows`).
/// ASKODOX never holds money: advances and payments here are records of what the shop received.

String _two(int n) => n.toString().padLeft(2, '0');
String _isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _clock(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$h:${_two(at.minute)} ${at.hour < 12 ? 'AM' : 'PM'}';
}

String _dayLabel(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  return at == null ? '' : '${_two(at.day)}/${_two(at.month)}';
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Day chips: today and the next six days (side by side, swipe sideways).
class _DayChips extends StatelessWidget {
  const _DayChips({required this.day, required this.onDay, this.prefix = 'askodoxWorkDay'});
  final DateTime day;
  final ValueChanged<DateTime> onDay;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: Key('$prefix-$i'),
              selected: _isoDay(day) == _isoDay(base.add(Duration(days: i))),
              label: Text(i == 0
                  ? (te ? 'ఈ రోజు' : 'Today')
                  : i == 1
                      ? (te ? 'రేపు' : 'Tomorrow')
                      : _dayLabel(base.add(Duration(days: i)).toIso8601String())),
              onSelected: (_) => onDay(base.add(Duration(days: i))),
            ),
          ),
      ]),
    );
  }
}

Widget _box(TextEditingController c, String label, {Key? key, TextInputType? keyboard, int lines = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: c,
        keyboardType: keyboard,
        minLines: 1,
        maxLines: lines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );

// ================================================================== bookings (shop)

/// `/biz/:id/bookings` -- the day's bookings (side-by-side day chips), add a phone / walk-in booking, and set up what
/// can be booked (rooms by day, chairs / OP / slots by time).
class AskodoxBizBookingsScreen extends ConsumerStatefulWidget {
  const AskodoxBizBookingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizBookingsScreen> createState() => _AskodoxBizBookingsScreenState();
}

class _AskodoxBizBookingsScreenState extends ConsumerState<AskodoxBizBookingsScreen> {
  DateTime _day = DateTime.now();
  AskodoxJson? _data;
  List<AskodoxJson> _items = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final items = await repo.bookItems(widget.businessId);
      final data = await repo.shopBookings(widget.businessId, day: _isoDay(_day));
      if (mounted) {
        setState(() {
          _items = items;
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    try {
      await job();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  Future<void> _editItem([AskodoxJson? item]) async {
    final te = askodoxPosTe(context);
    final name = TextEditingController(text: '${item?['name'] ?? ''}');
    final minutes = TextEditingController(text: '${item?['slot_minutes'] ?? 30}');
    final capacity = TextEditingController(text: '${item?['capacity'] ?? 1}');
    final price = TextEditingController(
        text: askodoxPosInt(item?['price_paise']) > 0 ? askodoxPaise(askodoxPosInt(item?['price_paise']), symbol: false) : '');
    var mode = '${item?['mode'] ?? 'slot'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(te ? 'బుక్ చేసేది' : 'Bookable thing'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _box(name, te ? 'పేరు (రూమ్ 101, కుర్చీ 1, డా. రావు OP, హాల్)' : 'Name (Room 101, Chair 1, Dr Rao OP, Hall)',
                  key: const Key('askodoxBookItemName')),
              SegmentedButton<String>(
                key: const Key('askodoxBookItemMode'),
                segments: [
                  ButtonSegment(value: 'slot', label: Text(te ? 'సమయం ప్రకారం' : 'By time')),
                  ButtonSegment(value: 'day', label: Text(te ? 'రోజుల ప్రకారం' : 'By day')),
                ],
                selected: {mode},
                onSelectionChanged: (v) => set(() => mode = v.first),
              ),
              const SizedBox(height: 10),
              if (mode == 'slot')
                _box(minutes, te ? 'ఒక్కసారికి ఎన్ని నిమిషాలు' : 'Minutes each time', keyboard: TextInputType.number),
              _box(capacity, te ? 'ఎంత మంది పడతారు' : 'How many people it takes', keyboard: TextInputType.number),
              _box(price, mode == 'day' ? (te ? 'ఒక రోజు ధర (₹)' : 'Price a day (₹)') : (te ? 'ధర (₹)' : 'Price (₹)'),
                  keyboard: const TextInputType.numberWithOptions(decimal: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxBookItemSave'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final body = <String, Object?>{
      if (item != null) 'id': item['id'],
      'name': name.text.trim(),
      'mode': mode,
      'slot_minutes': int.tryParse(minutes.text.trim()) ?? 30,
      'capacity': int.tryParse(capacity.text.trim()) ?? 1,
      'price_paise': askodoxParsePaise(price.text) ?? 0,
    };
    name.dispose();
    minutes.dispose();
    capacity.dispose();
    price.dispose();
    if (ok == true && '${body['name']}'.isNotEmpty) {
      await _run(() => ref.read(askodoxPosRepositoryProvider).saveBookItem(widget.businessId, body));
    }
  }

  Future<void> _itemsSheet() async {
    final te = askodoxPosTe(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          Text(te ? 'బుక్ చేసేవి' : 'What can be booked', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          for (final it in _items)
            ListTile(
              key: Key('askodoxBookItem-${it['id']}'),
              title: Text('${it['name']}'),
              subtitle: Text(it['mode'] == 'day'
                  ? (te ? 'రోజుల ప్రకారం · ${it['capacity']} మంది' : 'By day · ${it['capacity']} people')
                  : (te ? '${it['slot_minutes']} నిమి · ${it['capacity']} మంది' : '${it['slot_minutes']} min · ${it['capacity']} people')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_editItem(it));
              },
            ),
          FilledButton.icon(
            key: const Key('askodoxBookItemAdd'),
            onPressed: () {
              Navigator.pop(sheet);
              unawaited(_editItem());
            },
            icon: const Icon(Icons.add),
            label: Text(te ? 'కొత్తది చేర్చు' : 'Add one'),
          ),
        ]),
      ),
    );
  }

  Future<void> _addBooking() async {
    final te = askodoxPosTe(context);
    if (_items.isEmpty) return _itemsSheet();
    var item = _items.first;
    var time = const TimeOfDay(hour: 10, minute: 0);
    var nights = 1;
    final name = TextEditingController();
    final phone = TextEditingController();
    final people = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(te ? 'బుకింగ్ (${_dayLabel(_day.toIso8601String())})' : 'Booking (${_dayLabel(_day.toIso8601String())})'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                key: const Key('askodoxBookingItem'),
                initialValue: '${item['id']}',
                isExpanded: true,
                items: [for (final it in _items) DropdownMenuItem(value: '${it['id']}', child: Text('${it['name']}'))],
                onChanged: (v) => set(() => item = _items.firstWhere((it) => '${it['id']}' == v)),
              ),
              const SizedBox(height: 10),
              if (item['mode'] == 'day')
                Row(children: [
                  Text(te ? 'రాత్రులు: $nights' : 'Nights: $nights'),
                  const Spacer(),
                  IconButton(onPressed: nights > 1 ? () => set(() => nights--) : null, icon: const Icon(Icons.remove)),
                  IconButton(onPressed: () => set(() => nights++), icon: const Icon(Icons.add)),
                ])
              else
                OutlinedButton.icon(
                  key: const Key('askodoxBookingTime'),
                  onPressed: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: time);
                    if (picked != null) set(() => time = picked);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(time.format(ctx)),
                ),
              const SizedBox(height: 10),
              _box(name, te ? 'పేరు' : 'Name', key: const Key('askodoxBookingName')),
              _box(phone, te ? 'ఫోన్ నంబర్' : 'Phone number', keyboard: TextInputType.phone),
              _box(people, te ? 'ఎంత మంది' : 'People', keyboard: TextInputType.number),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxBookingSave'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(te ? 'బుక్ చేయి' : 'Book')),
          ],
        ),
      ),
    );
    final body = <String, Object?>{
      'item_id': item['id'],
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'people': int.tryParse(people.text.trim()) ?? 1,
      if (item['mode'] == 'day') ...{
        'from_date': _isoDay(_day),
        'to_date': _isoDay(_day.add(Duration(days: nights))),
      } else
        'at': '${_isoDay(_day)}T${_two(time.hour)}:${_two(time.minute)}:00',
    };
    name.dispose();
    phone.dispose();
    people.dispose();
    if (ok == true) await _run(() => ref.read(askodoxPosRepositoryProvider).addBooking(widget.businessId, body));
  }

  String _statusName(String s, bool te) => switch (s) {
        'booked' => te ? 'బుక్ అయింది' : 'Booked',
        'arrived' => te ? 'వచ్చారు' : 'Arrived',
        'done' => te ? 'అయిపోయింది' : 'Done',
        'cancelled' => te ? 'రద్దు' : 'Cancelled',
        'no_show' => te ? 'రాలేదు' : 'No show',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final bookings = askodoxPosList(_data?['bookings']);
    const next = {
      'booked': ['arrived', 'done', 'no_show', 'cancelled'],
      'arrived': ['done', 'cancelled'],
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బుకింగ్స్' : 'Bookings'), actions: [
        IconButton(
            key: const Key('askodoxBookItems'),
            tooltip: te ? 'బుక్ చేసేవి' : 'What can be booked',
            onPressed: _itemsSheet,
            icon: const Icon(Icons.tune)),
      ]),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                _DayChips(
                    day: _day,
                    onDay: (d) {
                      setState(() => _day = d);
                      unawaited(_load());
                    },
                    prefix: 'askodoxBookDay'),
                if (_data == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                if (_data != null && _items.isEmpty)
                  Card(
                    child: ListTile(
                      key: const Key('askodoxBookStart'),
                      leading: const Icon(Icons.add_home_work_outlined),
                      title: Text(te ? 'ముందు బుక్ చేసేవి చేర్చండి' : 'First add what can be booked'),
                      subtitle: Text(te ? 'రూమ్‌లు, కుర్చీలు, డాక్టర్ OP, హాల్, ట్రాక్టర్…' : 'Rooms, chairs, a doctor\'s OP, a hall, a tractor…'),
                      onTap: () => _editItem(),
                    ),
                  ),
                if (_data != null && _items.isNotEmpty && bookings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(te ? 'ఈ రోజు బుకింగ్స్ లేవు.' : 'No bookings this day.', textAlign: TextAlign.center),
                  ),
                for (final b in bookings)
                  Card(
                    key: Key('askodoxBooking-${b['id']}'),
                    child: ListTile(
                      title: Text(b['mode'] == 'day'
                          ? '${b['item']} · ${_dayLabel('${b['start']}')} → ${_dayLabel('${b['end']}')}'
                          : '${b['item']} · ${_clock('${b['start']}')}'),
                      subtitle: Text([
                        if ('${b['customer_name']}'.isNotEmpty) '${b['customer_name']}',
                        if ('${b['customer_phone'] ?? ''}'.isNotEmpty) '${b['customer_phone']}',
                        '${b['people']} ${te ? 'మంది' : 'people'}',
                        if (b['from_app'] == true) 'ASKODOX',
                        _statusName('${b['status']}', te),
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            key: Key('askodoxBookingQr-${b['id']}'),
                            tooltip: 'UPI QR',
                            onPressed: () => askodoxShowCollectQr(context, ref,
                                businessId: widget.businessId, kind: 'booking', refId: '${b['id']}'),
                            icon: const Icon(Icons.qr_code_2_rounded)),
                        if ((next['${b['status']}'] ?? const []).isNotEmpty)
                          PopupMenuButton<String>(
                              key: Key('askodoxBookingMenu-${b['id']}'),
                              onSelected: (s) => _run(() =>
                                  ref.read(askodoxPosRepositoryProvider).bookingStatus(widget.businessId, '${b['id']}', s)),
                              itemBuilder: (_) => [
                                for (final s in next['${b['status']}']!) PopupMenuItem(value: s, child: Text(_statusName(s, te))),
                              ],
                            ),
                      ]),
                    ),
                  ),
                if (askodoxPosInt(_data?['upcoming']) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(te
                        ? 'తర్వాతి రోజుల్లో ఇంకా ${_data?['upcoming']} బుకింగ్స్ ఉన్నాయి.'
                        : '${_data?['upcoming']} more bookings on later days.'),
                  ),
              ]),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('askodoxBookAdd'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _data == null ? null : _addBooking,
            icon: const Icon(Icons.add),
            label: Text(te ? 'బుకింగ్ చేయి' : 'Add a booking'),
          ),
        ),
      ),
    );
  }
}

// ================================================================== job cards (shop)

/// `/biz/:id/jobs` -- job cards: what came in, what is being worked on, what is ready (customer told), delivered.
class AskodoxBizJobsScreen extends ConsumerStatefulWidget {
  const AskodoxBizJobsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizJobsScreen> createState() => _AskodoxBizJobsScreenState();
}

class _AskodoxBizJobsScreenState extends ConsumerState<AskodoxBizJobsScreen> {
  String _tab = 'open';
  AskodoxJson? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(askodoxPosRepositoryProvider).shopJobs(widget.businessId, status: _tab);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _move(AskodoxJson job, String status) async {
    final te = askodoxPosTe(context);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).updateJob(widget.businessId, '${job['id']}', {'status': status});
      final wa = '${out['whatsapp_url'] ?? ''}';
      if (!mounted) return;
      if (status == 'ready') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(job['in_app'] == true
              ? (te ? 'కస్టమర్‌కి ASKODOX లో చెప్పాను.' : 'The customer was told in ASKODOX.')
              : (te ? 'రెడీ. కస్టమర్‌కి WhatsApp లో చెప్పండి.' : 'Ready. Tell the customer on WhatsApp.')),
          action: wa.isEmpty ? null : SnackBarAction(label: 'WhatsApp', onPressed: () => unawaited(_openUrl(wa))),
        ));
      }
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _add() async {
    final te = askodoxPosTe(context);
    final item = TextEditingController();
    final details = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final estimate = TextEditingController();
    final advance = TextEditingController();
    var ready = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(te ? 'కొత్త జాబ్' : 'New job'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _box(item, te ? 'ఏమిటి (ఫోన్ మోడల్, జాకెట్, కేక్…)' : 'What (phone model, blouse, cake…)',
                  key: const Key('askodoxJobItem')),
              _box(details, te ? 'ఏం చేయాలి (సమస్య, కొలతలు, మెసేజ్)' : 'What to do (problem, measurements, message)',
                  key: const Key('askodoxJobDetails'), lines: 3),
              _box(name, te ? 'కస్టమర్ పేరు' : 'Customer name'),
              _box(phone, te ? 'ఫోన్ నంబర్' : 'Phone number', keyboard: TextInputType.phone),
              Row(children: [
                Expanded(
                    child: _box(estimate, te ? 'అంచనా ₹' : 'Estimate ₹',
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _box(advance, te ? 'అడ్వాన్స్ ₹' : 'Advance ₹',
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
              ]),
              OutlinedButton.icon(
                key: const Key('askodoxJobReady'),
                onPressed: () async {
                  final picked = await showDatePicker(
                      context: ctx, initialDate: ready, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null) set(() => ready = picked);
                },
                icon: const Icon(Icons.event),
                label: Text(te ? 'రెడీ: ${_dayLabel(ready.toIso8601String())}' : 'Ready by ${_dayLabel(ready.toIso8601String())}'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxJobSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final body = <String, Object?>{
      'item': item.text.trim(),
      'details': details.text.trim(),
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'estimate_paise': askodoxParsePaise(estimate.text) ?? 0,
      'advance_paise': askodoxParsePaise(advance.text) ?? 0,
      'ready_by': _isoDay(ready),
      'client_txn_id': 'job-${DateTime.now().microsecondsSinceEpoch}',
    };
    for (final c in [item, details, name, phone, estimate, advance]) {
      c.dispose();
    }
    if (ok != true || '${body['item']}'.isEmpty) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).addJob(widget.businessId, body);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final jobs = askodoxPosList(_data?['jobs']);
    final counts = askodoxPosMap(_data?['counts']);
    String name(String s) => switch (s) {
          'received' => te ? 'తీసుకున్నాం' : 'Received',
          'working' => te ? 'పని జరుగుతోంది' : 'Working',
          'ready' => te ? 'రెడీ' : 'Ready',
          'delivered' => te ? 'ఇచ్చేశాం' : 'Delivered',
          'cancelled' => te ? 'రద్దు' : 'Cancelled',
          _ => s,
        };
    const next = {
      'received': ['working', 'ready'],
      'working': ['ready'],
      'ready': ['delivered'],
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'జాబ్ కార్డ్స్' : 'Job cards')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Wrap(spacing: 6, children: [
                  for (final t in const ['open', 'delivered', 'cancelled'])
                    ChoiceChip(
                      key: Key('askodoxJobsTab-$t'),
                      selected: _tab == t,
                      label: Text(t == 'open'
                          ? (te
                              ? 'జరుగుతున్నవి (${askodoxPosInt(counts['received']) + askodoxPosInt(counts['working']) + askodoxPosInt(counts['ready'])})'
                              : 'Open (${askodoxPosInt(counts['received']) + askodoxPosInt(counts['working']) + askodoxPosInt(counts['ready'])})')
                          : name(t)),
                      onSelected: (_) {
                        setState(() => _tab = t);
                        unawaited(_load());
                      },
                    ),
                ]),
                const SizedBox(height: 8),
                if (_data == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                if (_data != null && jobs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(te ? 'ఇక్కడ జాబ్స్ లేవు.' : 'No jobs here.', textAlign: TextAlign.center),
                  ),
                for (final j in jobs)
                  Card(
                    key: Key('askodoxJob-${j['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('#${j['token']}  ', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          Expanded(child: Text('${j['item']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                          Chip(label: Text(name('${j['status']}')), visualDensity: VisualDensity.compact),
                        ]),
                        if ('${j['details']}'.isNotEmpty) Text('${j['details']}'),
                        Text([
                          if ('${j['customer_name']}'.isNotEmpty) '${j['customer_name']}',
                          if ('${j['customer_phone'] ?? ''}'.isNotEmpty) '${j['customer_phone']}',
                          if ('${j['ready_by']}'.isNotEmpty) '${te ? 'రెడీ' : 'Ready by'} ${_dayLabel('${j['ready_by']}')}',
                          if (askodoxPosInt(j['estimate_paise']) > 0) '${te ? 'అంచనా' : 'Est.'} ${askodoxPaise(askodoxPosInt(j['estimate_paise']))}',
                          if (askodoxPosInt(j['advance_paise']) > 0) '${te ? 'అడ్వాన్స్' : 'Adv.'} ${askodoxPaise(askodoxPosInt(j['advance_paise']))}',
                          if (askodoxPosInt(j['balance_paise']) > 0) '${te ? 'మిగతా' : 'Balance'} ${askodoxPaise(askodoxPosInt(j['balance_paise']))}',
                        ].join(' · '), style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
                        if ((next['${j['status']}'] ?? const []).isNotEmpty || askodoxPosInt(j['balance_paise']) > 0) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            if (askodoxPosInt(j['balance_paise']) > 0)
                              OutlinedButton.icon(
                                key: Key('askodoxJobQr-${j['id']}'),
                                icon: const Icon(Icons.qr_code_2_rounded),
                                label: const Text('UPI QR'),
                                onPressed: () => askodoxShowCollectQr(context, ref,
                                    businessId: widget.businessId, kind: 'job', refId: '${j['id']}').then((_) => _load()),
                              ),
                            for (final s in next['${j['status']}'] ?? const <String>[])
                              FilledButton.tonal(
                                key: Key('askodoxJobMove-${j['id']}-$s'),
                                onPressed: () => _move(j, s),
                                child: Text(name(s)),
                              ),
                          ]),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('askodoxJobAdd'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(te ? 'కొత్త జాబ్' : 'New job'),
          ),
        ),
      ),
    );
  }
}

// ================================================================== monthly (shop)

/// `/biz/:id/monthly` -- plans (milk, tuition, gym, PG ...), members and this month's money: who paid, who still owes.
class AskodoxBizMonthlyScreen extends ConsumerStatefulWidget {
  const AskodoxBizMonthlyScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizMonthlyScreen> createState() => _AskodoxBizMonthlyScreenState();
}

class _AskodoxBizMonthlyScreenState extends ConsumerState<AskodoxBizMonthlyScreen> {
  List<AskodoxJson> _plans = const [];
  AskodoxJson? _month;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final plans = await repo.monthlyPlans(widget.businessId);
      final month = await repo.monthly(widget.businessId);
      if (mounted) {
        setState(() {
          _plans = plans;
          _month = month;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<Object?> Function() job) async {
    try {
      await job();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  Future<void> _addPlan() async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త నెల ప్లాన్' : 'New monthly plan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _box(name, te ? 'పేరు (రోజూ 1 లీటర్ పాలు, 10వ తరగతి ట్యూషన్…)' : 'Name (1 L milk daily, Class 10 tuition…)',
              key: const Key('askodoxPlanName')),
          _box(amount, te ? 'నెలకి ₹' : '₹ a month', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxPlanSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    final body = {'name': name.text.trim(), 'amount_paise': askodoxParsePaise(amount.text) ?? 0};
    name.dispose();
    amount.dispose();
    if (ok == true && body['name'] != '') {
      await _run(() => ref.read(askodoxPosRepositoryProvider).saveMonthlyPlan(widget.businessId, body));
    }
  }

  Future<void> _addMember() async {
    final te = askodoxPosTe(context);
    final plans = [for (final p in _plans) if (p['active'] == true) p];
    if (plans.isEmpty) return _addPlan();
    var plan = '${plans.first['id']}';
    var dueDay = 5;
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(te ? 'కొత్త సభ్యుడు' : 'New member'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                key: const Key('askodoxMemberPlan'),
                initialValue: plan,
                isExpanded: true,
                items: [
                  for (final p in plans)
                    DropdownMenuItem(
                        value: '${p['id']}', child: Text('${p['name']} · ${askodoxPaise(askodoxPosInt(p['amount_paise']))}')),
                ],
                onChanged: (v) => set(() => plan = v ?? plan),
              ),
              const SizedBox(height: 10),
              _box(name, te ? 'పేరు' : 'Name', key: const Key('askodoxMemberName')),
              _box(phone, te ? 'ఫోన్ నంబర్' : 'Phone number', keyboard: TextInputType.phone),
              Row(children: [
                Text(te ? 'ప్రతి నెల $dueDay వ తేదీకి కట్టాలి' : 'Pays by day $dueDay each month'),
                const Spacer(),
                IconButton(onPressed: dueDay > 1 ? () => set(() => dueDay--) : null, icon: const Icon(Icons.remove)),
                IconButton(onPressed: dueDay < 28 ? () => set(() => dueDay++) : null, icon: const Icon(Icons.add)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(
                key: const Key('askodoxMemberSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final body = {'plan_id': plan, 'name': name.text.trim(), 'phone': phone.text.trim(), 'due_day': dueDay};
    name.dispose();
    phone.dispose();
    if (ok == true && body['name'] != '') {
      await _run(() => ref.read(askodoxPosRepositoryProvider).addMonthlyMember(widget.businessId, body));
    }
  }

  Future<void> _more(AskodoxJson m) async {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              key: const Key('askodoxMemberPart'),
              title: Text(te ? 'కొంచెం కట్టారు' : 'Paid a part'),
              onTap: () => Navigator.pop(sheet, 'part')),
          ListTile(title: Text(te ? 'ఈ నెల వదిలేయి' : 'Let this month go'), onTap: () => Navigator.pop(sheet, 'waive')),
          ListTile(title: Text(te ? 'కొన్నాళ్లు ఆపు' : 'Pause'), onTap: () => Navigator.pop(sheet, 'paused')),
          ListTile(title: Text(te ? 'మళ్ళీ మొదలు' : 'Start again'), onTap: () => Navigator.pop(sheet, 'active')),
          ListTile(title: Text(te ? 'పూర్తిగా ఆపు' : 'Stop'), onTap: () => Navigator.pop(sheet, 'stopped')),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    final id = '${m['id']}';
    if (pick == 'part') {
      final amount = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(te ? 'ఎంత కట్టారు?' : 'How much was paid?'),
          content: _box(amount, '₹', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సరే' : 'OK'))],
        ),
      );
      final paise = askodoxParsePaise(amount.text) ?? 0;
      amount.dispose();
      if (ok == true && paise > 0) await _run(() => repo.payMonthly(widget.businessId, id, {'amount_paise': paise}));
    } else if (pick == 'waive') {
      await _run(() => repo.payMonthly(widget.businessId, id, {'waive': true}));
    } else {
      await _run(() => repo.monthlyMemberStatus(widget.businessId, id, pick));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final members = askodoxPosList(_month?['members']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నెలవారీ (${_month?['month'] ?? ''})' : 'Monthly (${_month?['month'] ?? ''})')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (_month != null)
                  Row(children: [
                    Expanded(
                        child: Card(
                            child: ListTile(
                                title: Text(askodoxPaise(askodoxPosInt(_month?['owed_paise'])),
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
                                subtitle: Text(te ? 'ఇంకా రావాలి' : 'Still to come')))),
                    Expanded(
                        child: Card(
                            child: ListTile(
                                title: Text(askodoxPaise(askodoxPosInt(_month?['collected_paise'])),
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF17784C))),
                                subtitle: Text(te ? 'వచ్చింది' : 'Received')))),
                  ]),
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in _plans)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                            label: Text('${p['name']} · ${askodoxPaise(askodoxPosInt(p['amount_paise']))} · ${p['members']}')),
                      ),
                    ActionChip(
                        key: const Key('askodoxPlanAdd'),
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(te ? 'ప్లాన్' : 'Plan'),
                        onPressed: _addPlan),
                  ]),
                ),
                if (_month == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                if (_month != null && members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                        te ? 'ముందు ఒక ప్లాన్, తర్వాత సభ్యులను చేర్చండి.' : 'Add a plan first, then its members.',
                        textAlign: TextAlign.center),
                  ),
                for (final m in members)
                  Card(
                    key: Key('askodoxMember-${m['id']}'),
                    child: ListTile(
                      onLongPress: () => _more(m),
                      title: Text('${m['name']} · ${m['plan']}'),
                      subtitle: Text(m['status'] != 'active'
                          ? (m['status'] == 'paused' ? (te ? 'ఆపారు' : 'Paused') : (te ? 'ఆగిపోయింది' : 'Stopped'))
                          : askodoxPosInt(m['left_paise']) == 0
                              ? (te ? 'ఈ నెల కట్టారు ✓' : 'Paid this month ✓')
                              : '${te ? 'రావాలి' : 'Due'} ${askodoxPaise(askodoxPosInt(m['left_paise']))}'
                                  '${m['late'] == true ? (te ? ' · ఆలస్యం' : ' · late') : ''}'),
                      trailing: askodoxPosInt(m['left_paise']) == 0
                          ? IconButton(onPressed: () => _more(m), icon: const Icon(Icons.more_vert))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              if ('${m['whatsapp_url'] ?? ''}'.isNotEmpty)
                                IconButton(
                                    key: Key('askodoxMemberRemind-${m['id']}'),
                                    tooltip: te ? 'WhatsApp లో గుర్తు చేయి' : 'Remind on WhatsApp',
                                    onPressed: () => _openUrl('${m['whatsapp_url']}'),
                                    icon: const Icon(Icons.chat_outlined)),
                              IconButton(
                                  key: Key('askodoxMemberQr-${m['id']}'),
                                  tooltip: 'UPI QR',
                                  onPressed: () => askodoxShowCollectQr(context, ref,
                                      businessId: widget.businessId,
                                      kind: 'member',
                                      refId: '${m['id']}',
                                      month: '${_month?['month'] ?? ''}').then((_) => _load()),
                                  icon: const Icon(Icons.qr_code_2_rounded)),
                              FilledButton.tonal(
                                key: Key('askodoxMemberPaid-${m['id']}'),
                                onPressed: () => _run(() => ref
                                    .read(askodoxPosRepositoryProvider)
                                    .payMonthly(widget.businessId, '${m['id']}', const <String, Object?>{})),
                                child: Text(te ? 'కట్టారు' : 'Paid'),
                              ),
                            ]),
                    ),
                  ),
              ]),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('askodoxMemberAdd'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _month == null ? null : _addMember,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(te ? 'సభ్యుడిని చేర్చు' : 'Add a member'),
          ),
        ),
      ),
    );
  }
}

// ================================================================== the customer's side

/// `/shops/:id/book` -- a customer books: the day, the time (or nights), how many -> what is free -> book.
class AskodoxShopBookScreen extends ConsumerStatefulWidget {
  const AskodoxShopBookScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopBookScreen> createState() => _AskodoxShopBookScreenState();
}

class _AskodoxShopBookScreenState extends ConsumerState<AskodoxShopBookScreen> {
  DateTime _day = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  int _nights = 1;
  int _people = 1;
  AskodoxJson? _slots;
  AskodoxJson? _days;
  bool _busy = false;
  String? _done;

  Future<void> _find() async {
    setState(() => _busy = true);
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final slots = await repo.freeToBook(widget.businessId, {
        'mode': 'slot',
        'at': '${_isoDay(_day)}T${_two(_time.hour)}:${_two(_time.minute)}:00',
        'people': _people,
      });
      final days = await repo.freeToBook(widget.businessId, {
        'mode': 'day',
        'from_date': _isoDay(_day),
        'to_date': _isoDay(_day.add(Duration(days: _nights))),
        'people': _people,
      });
      if (mounted) {
        setState(() {
          _slots = slots;
          _days = days;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _book(AskodoxJson item) async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item['mode'] == 'day'
              ? '${_dayLabel('${item['start']}')} → ${_dayLabel('${item['end']}')} · $_people ${te ? 'మంది' : 'people'}'
              : '${_dayLabel('${item['start']}')} ${_clock('${item['start']}')} · $_people ${te ? 'మంది' : 'people'}'),
          if (askodoxPosInt(item['price_paise']) > 0)
            Text('${askodoxPaise(askodoxPosInt(item['price_paise']))}${item['mode'] == 'day' ? (te ? ' / రోజు' : ' / day') : ''}'
                ' · ${te ? 'షాప్‌కే నేరుగా కట్టండి' : 'pay the shop directly'}'),
          const SizedBox(height: 10),
          _box(name, te ? 'మీ పేరు' : 'Your name', key: const Key('askodoxShopBookName')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxShopBookConfirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'బుక్ చేయి' : 'Book')),
        ],
      ),
    );
    final body = <String, Object?>{
      'item_id': item['id'],
      'name': name.text.trim(),
      'people': _people,
      if (item['mode'] == 'day') ...{
        'from_date': _isoDay(_day),
        'to_date': _isoDay(_day.add(Duration(days: _nights))),
      } else
        'at': '${_isoDay(_day)}T${_two(_time.hour)}:${_two(_time.minute)}:00',
    };
    name.dispose();
    if (ok != true) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).book(widget.businessId, body);
      if (mounted) {
        setState(() => _done = te
            ? 'బుక్ అయింది ✓ షాప్‌కి తెలియజేశాం. "నా బుకింగ్స్" లో చూడండి.'
            : 'Booked ✓ The shop has been told. See "My bookings".');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final free = [...askodoxPosList(_days?['free']), ...askodoxPosList(_slots?['free'])];
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బుక్ చేయండి' : 'Book')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _DayChips(day: _day, onDay: (d) => setState(() => _day = d), prefix: 'askodoxShopBookDay'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: const Key('askodoxShopBookTime'),
            onPressed: () async {
              final picked = await showTimePicker(context: context, initialTime: _time);
              if (picked != null && mounted) setState(() => _time = picked);
            },
            icon: const Icon(Icons.schedule),
            label: Text(_time.format(context)),
          ),
          InputChip(
            label: Text(te ? 'రాత్రులు $_nights' : 'Nights $_nights'),
            onPressed: () => setState(() => _nights = _nights >= 14 ? 1 : _nights + 1),
          ),
          InputChip(
            label: Text(te ? '$_people మంది' : '$_people people'),
            onPressed: () => setState(() => _people = _people >= 20 ? 1 : _people + 1),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('askodoxShopBookFind'),
          onPressed: _busy ? null : _find,
          child: Text(te ? 'ఖాళీ ఉన్నవి చూపించు' : 'Show what is free'),
        ),
        if (_done != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_done!, key: const Key('askodoxShopBookDone'))),
        if ((_slots != null || _days != null) && free.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(te ? 'ఆ సమయానికి ఖాళీ లేదు. వేరే సమయం / రోజు చూడండి.' : 'Nothing free then. Try another time or day.'),
          ),
        for (final f in free)
          Card(
            child: ListTile(
              key: Key('askodoxShopBookFree-${f['id']}'),
              title: Text('${f['name']}'),
              subtitle: Text([
                f['mode'] == 'day'
                    ? (te ? '$_nights రాత్రులు' : '$_nights nights')
                    : '${_clock('${f['start']}')} · ${f['slot_minutes']} ${te ? 'నిమి' : 'min'}',
                if (askodoxPosInt(f['price_paise']) > 0) askodoxPaise(askodoxPosInt(f['price_paise'])),
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _book(f),
            ),
          ),
      ]),
    );
  }
}

/// `/me/bookings`, `/me/jobs`, `/me/monthly` -- the customer's own: bookings (cancel before it starts), job cards
/// (where my phone / blouse / cake is) and monthly plans (what is left to pay this month).
class AskodoxMyWorkScreen extends ConsumerStatefulWidget {
  const AskodoxMyWorkScreen({super.key, required this.kind});
  final String kind;

  @override
  ConsumerState<AskodoxMyWorkScreen> createState() => _AskodoxMyWorkScreenState();
}

class _AskodoxMyWorkScreenState extends ConsumerState<AskodoxMyWorkScreen> {
  List<AskodoxJson>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final rows = switch (widget.kind) {
        'jobs' => await repo.myJobs(),
        'monthly' => await repo.myMonthly(),
        _ => await repo.myBookings(),
      };
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final title = switch (widget.kind) {
      'jobs' => te ? 'నా జాబ్స్ (రిపేర్ / ఆర్డర్)' : 'My jobs (repairs / orders)',
      'monthly' => te ? 'నా నెలవారీ' : 'My monthly plans',
      _ => te ? 'నా బుకింగ్స్' : 'My bookings',
    };
    final rows = _rows ?? const <AskodoxJson>[];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _rows == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'ఏమీ లేవు.' : 'Nothing yet.')),
                    for (final r in rows)
                      Card(
                        child: ListTile(
                          key: Key('askodoxMyWork-${widget.kind}-${r['id'] ?? r['plan']}'),
                          title: Text(switch (widget.kind) {
                            'jobs' => '${r['shop']} · #${r['token']} ${r['item']}',
                            'monthly' => '${r['shop']} · ${r['plan']}',
                            _ => '${r['shop']} · ${r['item']}',
                          }),
                          subtitle: Text(switch (widget.kind) {
                            'jobs' => [
                                '${r['status']}' == 'ready' ? (te ? 'రెడీ — వెళ్లి తీసుకోండి' : 'Ready — go and collect') : '${r['status']}',
                                if (askodoxPosInt(r['balance_paise']) > 0)
                                  '${te ? 'మిగతా' : 'Balance'} ${askodoxPaise(askodoxPosInt(r['balance_paise']))}',
                              ].join(' · '),
                            'monthly' => askodoxPosInt(r['left_paise']) == 0
                                ? (te ? '${r['month']} కట్టారు ✓' : '${r['month']} paid ✓')
                                : '${r['month']} ${te ? 'కట్టాలి' : 'due'} ${askodoxPaise(askodoxPosInt(r['left_paise']))}',
                            _ => '${_dayLabel('${r['start']}')} ${r['mode'] == 'day' ? '→ ${_dayLabel('${r['end']}')}' : _clock('${r['start']}')} · ${r['status']}',
                          }),
                          trailing: widget.kind == 'bookings' && r['status'] == 'booked'
                              ? TextButton(
                                  key: Key('askodoxMyBookingCancel-${r['id']}'),
                                  onPressed: () async {
                                    try {
                                      await ref.read(askodoxPosRepositoryProvider).cancelMyBooking('${r['id']}');
                                      await _load();
                                    } on AskodoxPosException catch (e) {
                                      if (context.mounted) askodoxPosSnack(context, e.message(te));
                                    }
                                  },
                                  child: Text(te ? 'రద్దు' : 'Cancel'))
                              : null,
                        ),
                      ),
                  ]),
                ),
    );
  }
}
