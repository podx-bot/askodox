import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'my_payment_alerts_screen.dart' show askodoxStaffRoleLabel;
import '../../../shared/widgets/navigator_section.dart' show AskodoxNavSection;
import 'pos_common.dart';

/// The shop's order desk settings (owner 2026-11-16): WHO hears each step of an order (new order -> owner / cashier,
/// kitchen -> the cook, ready -> waiter / cashier, delivery -> the delivery person) and the auto-confirm switch.
/// Nothing chosen for a step = the people of the matching role. Staff are added here too, with the order roles.
class AskodoxDeskSettingsScreen extends ConsumerStatefulWidget {
  const AskodoxDeskSettingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskSettingsScreen> createState() => _AskodoxDeskSettingsScreenState();
}

const askodoxDeskSteps = <(String, String, String)>[
  ('new', 'New order → who is told', 'కొత్త ఆర్డర్ → ఎవరికి'),
  ('kitchen', 'Kitchen (after accepted)', 'వంటగది (అంగీకరించాక)'),
  ('ready', 'Ready to serve / pick up', 'సిద్ధం (వడ్డించడం / ఇవ్వడం)'),
  ('delivery', 'Ready for delivery', 'డెలివరీకి సిద్ధం'),
];

const askodoxDeskStaffRoles = ['manager', 'cashier', 'kitchen', 'waiter', 'delivery'];

class _AskodoxDeskSettingsScreenState extends ConsumerState<AskodoxDeskSettingsScreen> {
  AskodoxJson? _data;
  Object? _error;
  final _phone = TextEditingController();
  final _label = TextEditingController();
  final _custom = TextEditingController();
  List<AskodoxJson> _quick = const [];
  String _role = 'cashier';
  // Welcome on a QR scan + thanks at the end (owner 2026-11-17); the shop changes the words or turns it off.
  AskodoxJson? _welcome;
  final _hello = TextEditingController();
  final _again = TextEditingController();
  final _thanks = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadWelcome());
  }

  @override
  void dispose() {
    _phone.dispose();
    _label.dispose();
    _custom.dispose();
    _hello.dispose();
    _again.dispose();
    _thanks.dispose();
    super.dispose();
  }

  Future<void> _loadWelcome() async {
    try {
      final w = await ref.read(askodoxPosRepositoryProvider).welcomeSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _welcome = w;
        _hello.text = '${w['hello'] ?? ''}';
        _again.text = '${w['again'] ?? ''}';
        _thanks.text = '${w['thanks'] ?? ''}';
      });
    } catch (_) {}
  }

  Future<void> _saveWelcome({bool? enabled}) => _guard(() async {
        final w = await ref.read(askodoxPosRepositoryProvider).saveWelcome(widget.businessId, {
          if (enabled != null) 'enabled': enabled,
          'hello': _hello.text.trim(),
          'again': _again.text.trim(),
          'thanks': _thanks.text.trim(),
        });
        if (mounted) {
          setState(() => _welcome = w);
          askodoxPosSnack(context, askodoxPosTe(context) ? 'సేవ్ అయింది ✓' : 'Saved ✓');
        }
        return null;
      });

  Widget _welcomeCard(bool te) {
    final w = _welcome;
    if (w == null) return const SizedBox.shrink();
    final defaults = askodoxPosMap(w['defaults']);
    final on = w['enabled'] == true;
    Widget box(String key, TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            key: Key('askodoxDeskWelcome-$key'),
            controller: c,
            enabled: on,
            maxLength: 160,
            decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: label,
                hintText: '${defaults[key] ?? ''}',
                hintMaxLines: 2,
                counterText: ''),
          ),
        );
    return Card(
      key: const Key('askodoxDeskWelcomeCard'),
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            key: const Key('askodoxDeskWelcomeOn'),
            contentPadding: EdgeInsets.zero,
            value: on,
            title: Text(te ? '🙏 స్వాగతం / ధన్యవాదాలు' : '🙏 Welcome / thank you', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(te
                ? 'QR స్కాన్ చేయగానే కస్టమర్ ఫోన్‌లో పేరుతో స్వాగతం, ఆర్డర్ అయిపోయాక ధన్యవాదాలు. {name} = కస్టమర్ పేరు, {shop} = షాప్ పేరు. ఖాళీ = కింద చూపిన మాట.'
                : 'On the QR scan the customer sees a welcome with their name; after the order, a thank you. {name} = customer, {shop} = your shop. Empty = the grey text.'),
            onChanged: (v) => _saveWelcome(enabled: v),
          ),
          box('hello', _hello, te ? 'మొదటిసారి వచ్చినవారికి' : 'First visit'),
          box('again', _again, te ? 'మళ్ళీ వచ్చినవారికి' : 'Returning customer'),
          box('thanks', _thanks, te ? 'చివర్లో ధన్యవాదాలు' : 'Thank you at the end'),
          const SizedBox(height: 8),
          FilledButton(key: const Key('askodoxDeskWelcomeSave'), onPressed: on ? () => _saveWelcome() : null, child: Text(te ? 'సేవ్' : 'Save')),
        ]),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).deskSettings(widget.businessId);
      final q = await ref.read(askodoxPosRepositoryProvider).deskRequestSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _quick = askodoxPosList(q['requests']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guard(Future<Object?> Function() action) async {
    final te = askodoxPosTe(context);
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _toggle(String step, String id, bool on) => _guard(() async {
        final routing = askodoxPosMap(_data?['routing']);
        final now = <String>{for (final x in (routing[step] as List? ?? const [])) '$x'};
        on ? now.add(id) : now.remove(id);
        final d = await ref.read(askodoxPosRepositoryProvider).deskSettingsSave(widget.businessId, routing: {step: now.toList()});
        if (mounted) setState(() => _data = d);
        return null;
      });

  /// Table quick requests (water / gravy / onions / bill ...): switch the built-in ones on / off, add the shop's own.
  Future<void> _saveQuick({List<String>? off, List<AskodoxJson>? custom}) => _guard(() async {
        final q = await ref.read(askodoxPosRepositoryProvider).deskRequestSettingsSave(widget.businessId, off: off, custom: custom);
        if (mounted) setState(() => _quick = askodoxPosList(q['requests']));
        return null;
      });

  List<String> get _offKeys => [for (final r in _quick) if (r['custom'] != true && r['enabled'] != true) '${r['key']}'];
  List<AskodoxJson> get _customRows => [for (final r in _quick) if (r['custom'] == true) {'key': r['key'], 'en': r['en'], 'te': r['te']}];

  Future<void> _addQuick() async {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    _custom.clear();
    await _saveQuick(custom: [..._customRows, {'en': text, 'te': text}]);
  }

  Future<void> _addStaff() => _guard(() async {
        final te = askodoxPosTe(context);
        final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
        if (phone.length < 10) {
          askodoxPosSnack(context, te ? '10 అంకెల నంబర్ రాయండి.' : 'Enter a 10 digit number.');
          return null;
        }
        await ref.read(askodoxPosRepositoryProvider).setMember(widget.businessId, phone.substring(phone.length - 10), _role, label: _label.text.trim());
        if (!mounted) return null;
        _phone.clear();
        _label.clear();
        askodoxPosSnack(context, te ? 'చేర్చాం. వాళ్ళు ఆ నంబర్ తో ASKODOX లో సైన్ ఇన్ చేయాలి.' : 'Added. They sign in to ASKODOX with that number.');
        await _load();
        return null;
      });

  Future<void> _removeStaff(AskodoxJson p) => _guard(() async {
        final te = askodoxPosTe(context);
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(te ? '"${p['label']}" ని తీసేయాలా?' : 'Remove "${p['label']}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'తీసేయి' : 'Remove')),
            ],
          ),
        );
        if (ok != true) return null;
        await ref.read(askodoxPosRepositoryProvider).removeMember(widget.businessId, '${p['last4']}');
        await _load();
        return null;
      });

  String _chosenNames(String step, List<AskodoxJson> people, AskodoxJson routing, bool te) {
    final chosen = ((routing[step] as List?) ?? const []).map((e) => '$e').toSet();
    final names = [
      for (final p in people)
        if (chosen.contains('${p['id']}')) p['you'] == true ? (te ? 'మీరు' : 'You') : '${p['label']}',
    ];
    return names.isEmpty ? (te ? 'పాత్ర ప్రకారం ▾' : 'By role ▾') : '${names.join(', ')} ▾';
  }

  Future<void> _pickPeople((String, String, String) step, List<AskodoxJson> people, AskodoxJson routing, bool te) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final chosen = ((askodoxPosMap(_data?['routing'])[step.$1] as List?) ?? const []).map((e) => '$e').toSet();
        return SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(te ? step.$3 : step.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(te ? 'ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్లకి వెళ్తుంది.' : 'Choose nobody and the people of that role are told.',
                style: const TextStyle(fontSize: 12.5)),
            for (final p in people)
              CheckboxListTile(
                key: Key('askodoxDeskRoute-${step.$1}-${p['id']}'),
                contentPadding: EdgeInsets.zero,
                value: chosen.contains('${p['id']}'),
                title: Text(p['you'] == true ? (te ? 'మీరు' : 'You') : '${p['label']}'),
                subtitle: Text(askodoxStaffRoleLabel('${p['role']}', te)),
                onChanged: (v) async {
                  await _toggle(step.$1, '${p['id']}', v ?? false);
                  setSheet(() {});
                },
              ),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final people = askodoxPosList(_data?['people']);
    final routing = askodoxPosMap(_data?['routing']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఆర్డర్ అలర్ట్స్ & సిబ్బంది' : 'Order alerts & staff')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxDeskSettings'), padding: const EdgeInsets.all(14), children: [
                  // Owner 2026-11-17: no auto-accept. A person accepts every order: the owner, or the people the owner allows.
                  Card(
                    child: ListTile(
                      key: const Key('askodoxDeskAutoConfirm'),
                      leading: const Icon(Icons.how_to_reg_outlined),
                      title: Text(te ? 'ఆర్డర్ ఒప్పుకునేది ఎవరు' : 'Who accepts orders', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(te
                          ? 'మొదట మీరే. ఎవరికైనా అనుమతి ఇవ్వండి — పేరు, ఫోన్, పాత్ర. మార్చు / ఆపు / తీసేయి.'
                          : 'You first. Allow anyone — name, phone, role. Edit / pause / remove.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('/pos/${widget.businessId}/staff');
                        await _load();
                      },
                    ),
                  ),
                  const Divider(),
                  Text(te ? 'ఏ స్టెప్ ఎవరికి వినిపించాలి?' : 'Who is told at each step?', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(te ? 'ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్ళకి (యజమానికి కూడా) వెళ్తుంది.' : 'Choose nobody and the people of that role (and you) are told.',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 6),
                  // Owner 2026-11-17: a small table (one row per step, the chosen people in one button), not chip walls.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(children: [
                        for (final (i, step) in askodoxDeskSteps.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              Container(width: 6, height: 34, decoration: BoxDecoration(
                                  color: AskodoxNavSection.palette[i % AskodoxNavSection.palette.length].$2,
                                  borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(te ? step.$3 : step.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 170),
                                child: OutlinedButton(
                                  key: Key('askodoxDeskRoutePick-${step.$1}'),
                                  onPressed: () => _pickPeople(step, people, routing, te),
                                  child: Text(_chosenNames(step.$1, people, routing, te), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  const Divider(height: 28),
                  Text(te ? 'టేబుల్ దగ్గర కస్టమర్ అడిగేవి' : 'What a table can ask for', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                      te
                          ? 'కస్టమర్ ఆర్డర్ అంగీకరించాక నీళ్లు, ఎక్స్‌ట్రా గ్రేవీ, ఆనియన్స్, బిల్ లాంటివి బటన్‌తో లేదా మాటతో అడుగుతారు. వెయిటర్‌కి టేబుల్ పేరుతో వెళ్తుంది.'
                          : 'After you accept the order, the customer taps or says water, extra gravy, onions, the bill... The waiter gets it with the table name.',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final r in _quick)
                      if (r['custom'] != true)
                        FilterChip(
                          key: Key('askodoxQuickReq-${r['key']}'),
                          label: Text(te ? '${r['te']}' : '${r['en']}'),
                          selected: r['enabled'] == true,
                          selectedColor: const Color(0xFFE7F5EE),
                          onSelected: (v) {
                            final off = _offKeys.toSet();
                            v ? off.remove('${r['key']}') : off.add('${r['key']}');
                            _saveQuick(off: off.toList());
                          },
                        )
                      else
                        InputChip(
                          key: Key('askodoxQuickReq-${r['key']}'),
                          label: Text('${r['en']}'),
                          onDeleted: () => _saveQuick(custom: [for (final c in _customRows) if (c['key'] != r['key']) c]),
                        ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('askodoxQuickReqAdd'),
                    controller: _custom,
                    onSubmitted: (_) => _addQuick(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: te ? 'మీ సొంతది చేర్చండి (ఉదా: అప్పడం)' : 'Add your own (e.g. Papad)',
                      suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addQuick),
                    ),
                  ),
                  const Divider(height: 28),
                  Text(te ? 'సిబ్బంది' : 'Staff', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  for (final p in people.where((p) => p['role'] != 'owner'))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${p['label']}'),
                      subtitle: Text(askodoxStaffRoleLabel('${p['role']}', te)),
                      trailing: IconButton(
                          key: Key('askodoxDeskStaffRemove-${p['id']}'),
                          tooltip: te ? 'తీసేయి' : 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeStaff(p)),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                      key: const Key('askodoxDeskStaffPhone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: te ? 'ఫోన్ నంబర్' : 'Phone number', border: const OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(
                      key: const Key('askodoxDeskStaffName'),
                      controller: _label,
                      decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name', border: const OutlineInputBorder())),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('askodoxDeskStaffRole'),
                    initialValue: _role,
                    decoration: InputDecoration(labelText: te ? 'పాత్ర' : 'Role', border: const OutlineInputBorder()),
                    items: [for (final r in askodoxDeskStaffRoles) DropdownMenuItem(value: r, child: Text(askodoxStaffRoleLabel(r, te)))],
                    onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                      key: const Key('askodoxDeskStaffAdd'),
                      onPressed: _addStaff,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(te ? 'సిబ్బందిని చేర్చు' : 'Add staff')),
                  _welcomeCard(te),
                ]),
    );
  }
}

/// Today / this week / this month: bills, sales, how it was paid, dues, best sellers and the latest bills.
class AskodoxDeskSalesScreen extends ConsumerStatefulWidget {
  const AskodoxDeskSalesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskSalesScreen> createState() => _AskodoxDeskSalesScreenState();
}

class _AskodoxDeskSalesScreenState extends ConsumerState<AskodoxDeskSalesScreen> {
  String _period = 'day';
  AskodoxJson? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).shopSales(widget.businessId, period: _period);
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

  String _method(String m, bool te) => switch (m) {
        'cash' => te ? 'క్యాష్' : 'Cash',
        'upi' => 'UPI',
        'card' => te ? 'కార్డ్' : 'Card',
        'bank_transfer' => te ? 'బ్యాంక్' : 'Bank',
        'advance' => te ? 'అడ్వాన్స్' : 'Advance',
        _ => m,
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final days = askodoxPosList(d?['days']);
    final maxDay = days.fold<int>(1, (m, x) => askodoxPosInt(x['sales_paise']) > m ? askodoxPosInt(x['sales_paise']) : m);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'అమ్మకాలు' : 'Sales')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : ListView(key: const Key('askodoxDeskSales'), padding: const EdgeInsets.all(14), children: [
              SegmentedButton<String>(
                key: const Key('askodoxDeskSalesPeriod'),
                segments: [
                  ButtonSegment(value: 'day', label: Text(te ? 'ఈరోజు' : 'Today')),
                  ButtonSegment(value: 'week', label: Text(te ? 'ఈ వారం' : 'This week')),
                  ButtonSegment(value: 'month', label: Text(te ? 'ఈ నెల' : 'This month')),
                ],
                selected: {_period},
                onSelectionChanged: (v) {
                  setState(() {
                    _period = v.first;
                    _data = null;
                  });
                  unawaited(_load());
                },
              ),
              const SizedBox(height: 12),
              if (d == null)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(askodoxPaise(askodoxPosInt(d['net_paise'])), key: const Key('askodoxDeskSalesTotal'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      Text('${d['bills']} ${te ? 'బిల్లులు' : 'bills'} · ${te ? 'బాకీ' : 'Dues'} ${askodoxPaise(askodoxPosInt(d['dues_paise']))}'),
                      if (askodoxPosInt(d['returns_paise']) > 0) Text('${te ? 'రిటర్న్' : 'Returns'} ${askodoxPaise(askodoxPosInt(d['returns_paise']))}'),
                      if (askodoxPosInt(d['cancelled']) > 0) Text('${te ? 'రద్దు' : 'Cancelled'} ${d['cancelled']}'),
                    ]),
                  ),
                ),
                if (askodoxPosList(d['payments']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(te ? 'ఎలా చెల్లించారు' : 'How it was paid', style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final p in askodoxPosList(d['payments']))
                    ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(_method('${p['method']}', te)), trailing: Text(askodoxPaise(askodoxPosInt(p['amount_paise'])))),
                ],
                if (_period != 'day') ...[
                  const SizedBox(height: 8),
                  Text(te ? 'రోజు వారీ' : 'Day by day', style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final x in days)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(width: 44, child: Text('${x['date']}'.substring(5), style: const TextStyle(fontSize: 12))),
                        Expanded(child: LinearProgressIndicator(value: askodoxPosInt(x['sales_paise']) <= 0 ? 0 : askodoxPosInt(x['sales_paise']) / maxDay, minHeight: 8)),
                        SizedBox(width: 84, child: Text(askodoxPaise(askodoxPosInt(x['sales_paise'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                      ]),
                    ),
                ],
                if (askodoxPosList(d['top_items']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(te ? 'ఎక్కువ అమ్మినవి' : 'Best sellers', style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final i in askodoxPosList(d['top_items']))
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${i['name']}'),
                        subtitle: Text('× ${(askodoxPosInt(i['qty_milli']) / 1000).toStringAsFixed(askodoxPosInt(i['qty_milli']) % 1000 == 0 ? 0 : 2)}'),
                        trailing: Text(askodoxPaise(askodoxPosInt(i['total_paise'])))),
                ],
                if (askodoxPosList(d['recent']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(te ? 'ఇటీవలి బిల్లులు' : 'Latest bills', style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final b in askodoxPosList(d['recent']))
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['number']}${'${b['customer']}'.isEmpty ? '' : ' · ${b['customer']}'}'),
                        subtitle: askodoxPosInt(b['balance_paise']) > 0 ? Text('${te ? 'బాకీ' : 'Due'} ${askodoxPaise(askodoxPosInt(b['balance_paise']))}', style: const TextStyle(color: Color(0xFFB91C1C))) : null,
                        trailing: Text(askodoxPaise(askodoxPosInt(b['total_paise'])))),
                ],
                const SizedBox(height: 8),
                Text(te ? 'మీ బిల్లుల నుంచి మాత్రమే. UPI / కార్డ్ మొత్తాలు క్యాషియర్ నిర్ధారించినవి.' : '${d['note']}', style: const TextStyle(fontSize: 12)),
              ],
            ]),
    );
  }
}
