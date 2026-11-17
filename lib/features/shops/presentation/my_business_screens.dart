import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/share/askodox_image_share.dart';
import '../../growth/data/growth_repository.dart' show AskodoxPlace;
import '../../home/presentation/question_mic.dart';
import '../../location/presentation/map_pin_picker.dart';
import '../../../shared/widgets/askodox_fill_bar.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxParsePaise;
import '../../business/presentation/biz_hub.dart';
import '../../pos/presentation/paper_bill.dart';
import '../../pos/presentation/pos_sale_screen.dart' show askodoxPrintInvoice;
import '../domain/name_change_rule.dart';

bool _bizTe(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String _bizLang(BuildContext context) => Localizations.localeOf(context).languageCode;

/// A mic inside one text box (owner 2026-11-14): what you say is added to the box.
Widget askodoxBoxMic(BuildContext context, TextEditingController box, {VoidCallback? changed}) => AskodoxQuestionMic(
      lang: _bizLang(context),
      followCentre: false,
      onText: (words) {
        final now = box.text.trim();
        box.text = now.isEmpty ? words : '$now $words';
        box.selection = TextSelection.collapsed(offset: box.text.length);
        changed?.call();
      },
    );

String _rupees(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

/// My business (Phase 1, owner 2026-11-14): ONE simple desk -- the shop's own details, a calculator bill that
/// can be shared, the UPI QR for the bill amount, and today's post. The full POS stays Phase 2.
/// The businesses this person OWNS (role `owner`). Staff roles (manager / cashier / attendant ...) never get the
/// owner's desk here; their own screens (e.g. payment sound) are reached elsewhere.
List<AskodoxJson> askodoxOwnedBusinesses(List<AskodoxJson> all) =>
    [for (final b in all) if ('${b['role']}' == 'owner') b];

class AskodoxMyBusinessScreen extends ConsumerStatefulWidget {
  const AskodoxMyBusinessScreen({super.key});

  @override
  ConsumerState<AskodoxMyBusinessScreen> createState() => _AskodoxMyBusinessScreenState();
}

class _AskodoxMyBusinessScreenState extends ConsumerState<AskodoxMyBusinessScreen> {
  final _name = TextEditingController();
  List<AskodoxJson>? _shops;
  List<String> _helping = const [];
  String? _selected;
  AskodoxJson _states = const {};
  String? _state;
  String? _status;
  bool _busy = false;
  bool _failed = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final all = await repo.businesses();
      // Owner 2026-11-15: a person added as staff (e.g. payment sound only) must never see or edit the
      // employer's business here. This desk shows ONLY the businesses this person owns.
      final shops = askodoxOwnedBusinesses(all);
      final helping = [for (final b in all) if ('${b['role']}' != 'owner') '${b['name']}'];
      var states = _states;
      String? status;
      if (_selected != null && !shops.any((b) => '${b['id']}' == _selected)) _selected = null;
      if (shops.isEmpty) {
        states = askodoxPosMap((await repo.meta())['states']);
      } else {
        final shop = await repo.shopState(_selected ?? '${shops.first['id']}');
        status = '${askodoxPosMap(shop['profile'])['status'] ?? ''}';
      }
      if (mounted) {
        setState(() {
          _shops = shops;
          _helping = helping;
          _states = states;
          _status = status;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final state = _state;
    if (name.isEmpty || state == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(askodoxPosRepositoryProvider)
          .createBusiness({'name': name, 'state_code': state, 'registration_type': 'unregistered'});
      _name.clear();
      _adding = false;
      await _load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusText(bool te) => switch (_status) {
        'verified' => te ? 'ASKODOX నిర్ధారించింది' : 'Verified by ASKODOX',
        'submitted' => te ? 'వివరాలు ఇచ్చారు · ASKODOX చూస్తుంది' : 'Details given · ASKODOX will check',
        _ => te ? 'వివరాలు పూర్తి చేయండి' : 'Complete your details',
      };

  /// The "start a business" boxes: used for the first business and for "Add another business".
  List<Widget> _createFields(bool te) => [
          Text(te ? 'మీ బిజినెస్ పేరు చెప్పండి' : 'Tell us your business name',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('askodoxMyBusinessName'),
            controller: _name,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: te ? 'షాప్ / బిజినెస్ పేరు' : 'Shop / business name', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('askodoxMyBusinessState'),
            initialValue: _state,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: te ? 'రాష్ట్రం' : 'State', border: const OutlineInputBorder()),
            items: [
              for (final entry in _states.entries)
                DropdownMenuItem<String>(value: entry.key, child: Text('${entry.value}')),
            ],
            onChanged: (value) => setState(() => _state = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || _name.text.trim().isEmpty || _state == null ? null : _create,
            child: Text(te ? 'మొదలుపెట్టండి' : 'Start'),
          ),
      ];

  String _shopLabel(AskodoxJson b, bool te) {
    final status = '${b['status'] ?? 'open'}';
    return status == 'open' ? '${b['name']}' : '${b['name']} · ${_statusLabel(status, te)}';
  }

  String _statusLabel(String status, bool te) => switch (status) {
        'paused' => te ? 'విరామంలో' : 'Paused',
        'closed' => te ? 'మూసివేశారు' : 'Closed',
        _ => te ? 'తెరిచి ఉంది' : 'Open',
      };

  Future<void> _setStatus(String id, String status, bool te) async {
    final note = TextEditingController();
    final ok = status == 'open'
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(status == 'paused'
                  ? (te ? 'బిజినెస్‌కు విరామం ఇవ్వాలా?' : 'Pause this business?')
                  : (te ? 'బిజినెస్ మూసివేయాలా?' : 'Close this business?')),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(te
                    ? 'కస్టమర్లకు కొత్త ఆర్డర్లు ఆగిపోతాయి (ఆన్‌లైన్ లిస్టింగ్లు దాగుతాయి, QR / కోడ్ పనిచేయదు). మీ బిల్లులు, లెక్కలు, కస్టమర్లు అలాగే ఉంటాయి. ఎప్పుడైనా మళ్ళీ తెరవవచ్చు.'
                    : 'New customer orders stop (online listings hide, the QR / code stops working). Your bills, accounts and customers stay. You can open it again any time.'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('askodoxBizStatusNote'),
                  controller: note,
                  maxLength: 160,
                  decoration: InputDecoration(
                      labelText: te ? 'కారణం (ఐచ్ఛికం)' : 'Reason (optional)', border: const OutlineInputBorder()),
                ),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
                FilledButton(
                    key: const Key('askodoxBizStatusConfirm'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(status == 'paused' ? (te ? 'విరామం' : 'Pause') : (te ? 'మూసివేయి' : 'Close'))),
              ],
            ),
          );
    final reason = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).setBusinessStatus(id, status, note: reason);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message(te))));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _statusCard(String id, String status, bool te) => Card(
        key: const Key('askodoxBusinessStatus'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(te ? 'బిజినెస్ స్థితి: ${_statusLabel(status, te)}' : 'Business status: ${_statusLabel(status, te)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final s in const ['open', 'paused', 'closed'])
                ChoiceChip(
                  key: Key('askodoxBizStatus-$s'),
                  label: Text(_statusLabel(s, te)),
                  selected: status == s,
                  onSelected: status == s ? null : (_) => _setStatus(id, s, te),
                ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = _bizTe(context);
    final shops = _shops;
    Widget body;
    if (shops == null) {
      body = _failed
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(te ? 'ఇప్పుడు లోడ్ కాలేదు.' : 'Could not load right now.'),
                TextButton(onPressed: _load, child: Text(te ? 'మళ్ళీ ప్రయత్నించండి' : 'Try again')),
              ]),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (shops.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_helping.isNotEmpty) ...[
            Card(
              key: const Key('askodoxMyBusinessHelping'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(te
                    ? 'మీరు ${_helping.join(', ')} లో సిబ్బందిగా ఉన్నారు. ఆ బిజినెస్ వివరాలు యజమాని మాత్రమే మారుస్తారు. మీ సొంత బిజినెస్ ఉంటే కింద మొదలుపెట్టండి.'
                    : 'You help at ${_helping.join(', ')}. Only its owner changes that business. If you have your own business, start it below.'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ..._createFields(te),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(te ? 'సేవ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not save. Try again.'),
          ],
        ],
      );
    } else {
      final current = shops.firstWhere((b) => '${b['id']}' == _selected, orElse: () => shops.first);
      final id = '${current['id']}';
      final status = '${current['status'] ?? 'open'}';
      final statusColor = switch (status) {
        'paused' => const Color(0xFFB45309),
        'closed' => const Color(0xFFB91C1C),
        _ => const Color(0xFF17784C),
      };
      // Owner 2026-11-18: ONE hub -- the shop card (tap: switch shop / open-pause-close / details), today's
      // numbers, three every-day buttons and the 6 groups. Every other business page opens from here.
      body = Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(askodoxBizHubProvider(id));
              await _load();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              children: [
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: const Key('askodoxMyBusinessShop'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (sheet) => SafeArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (shops.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DropdownButtonFormField<String>(
                                  key: const Key('askodoxMyBusinessPick'),
                                  initialValue: id,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                      labelText: te ? 'ఏ బిజినెస్?' : 'Which business?',
                                      border: const OutlineInputBorder()),
                                  items: [
                                    for (final b in shops)
                                      DropdownMenuItem<String>(value: '${b['id']}', child: Text(_shopLabel(b, te))),
                                  ],
                                  onChanged: (value) {
                                    Navigator.pop(sheet);
                                    setState(() => _selected = value);
                                    _load();
                                  },
                                ),
                              ),
                            _statusCard(id, status, te),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              key: const Key('askodoxMyBusinessAdd'),
                              onPressed: () {
                                Navigator.pop(sheet);
                                setState(() => _adding = true);
                              },
                              icon: const Icon(Icons.add_business_outlined),
                              label: Text(te ? 'ఇంకో బిజినెస్ చేర్చండి' : 'Add another business'),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: const Color(0xFFFFF1E3), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.storefront_outlined, color: Color(0xFFB45309)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${current['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            Text.rich(TextSpan(children: [
                              TextSpan(text: '● ${_statusLabel(status, te)}',
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800)),
                              TextSpan(text: te ? ' · ${_statusText(te)} · మార్చు' : ' · ${_statusText(te)} · change'),
                            ]), style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
                          ]),
                        ),
                        const Icon(Icons.expand_more),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AskodoxBizHubBody(businessId: id),
                if (_adding) ...[
                  const Divider(height: 28),
                  ..._createFields(te),
                  TextButton(onPressed: () => setState(() => _adding = false), child: Text(te ? 'వద్దు' : 'Cancel')),
                ],
              ],
            ),
          ),
        ),
        AskodoxAskBar(
          businessId: id,
          page: 'hub',
          hint: te ? '"ఈ రోజు ఎంత అమ్మాం?" "చికెన్ 65 ఆఫ్ చెయ్యి"' : '"How much did we sell today?"',
        ),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(te ? 'నా బిజినెస్' : 'My business')), body: body);
  }
}

/// How a box is filled (owner 2026-11-14: a mic only where people write sentences; links are pasted;
/// numbers use the number pad; hours come from a clock; the address from a map pin).
enum _Fill { words, plain, link, phone, hours, place }

class _ProfileField {
  const _ProfileField(this.id, this.en, this.te, {this.must = false, this.lines = 1, this.fill = _Fill.plain});
  final String id;
  final String en;
  final String te;
  final bool must;
  final int lines;
  final _Fill fill;
}

const _profileFields = <_ProfileField>[
  _ProfileField('description', 'About your business', 'మీ బిజినెస్ గురించి', must: true, lines: 3, fill: _Fill.words),
  _ProfileField('address', 'Address', 'అడ్రస్', must: true, lines: 2, fill: _Fill.place),
  _ProfileField('hours', 'Open hours', 'తెరిచి ఉండే సమయం', must: true, fill: _Fill.hours),
  _ProfileField('landmark', 'Landmark', 'గుర్తు (ల్యాండ్‌మార్క్)'),
  _ProfileField('reg_number', 'GST / Udyam number (only ASKODOX sees it)', 'GST / Udyam నంబర్ (ASKODOX మాత్రమే చూస్తుంది)'),
  _ProfileField('whatsapp', 'WhatsApp number', 'వాట్సాప్ నంబర్', fill: _Fill.phone),
  _ProfileField('website', 'Website', 'వెబ్‌సైట్', fill: _Fill.link),
  _ProfileField('facebook', 'Facebook page', 'Facebook పేజీ', fill: _Fill.link),
  _ProfileField('instagram', 'Instagram', 'Instagram', fill: _Fill.link),
  _ProfileField('youtube', 'YouTube', 'YouTube', fill: _Fill.link),
  _ProfileField('offers', 'Offers / discounts', 'ఆఫర్లు / డిస్కౌంట్లు', lines: 2, fill: _Fill.words),
  _ProfileField('delivery', 'Delivery', 'డెలివరీ', fill: _Fill.words),
  _ProfileField('extra', 'Anything else', 'ఇంకేదైనా', lines: 3, fill: _Fill.words),
];

/// The shop's own details: four required boxes first, the rest optional. Nothing here comes from Google.
class AskodoxBusinessProfileScreen extends ConsumerStatefulWidget {
  const AskodoxBusinessProfileScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBusinessProfileScreen> createState() => _AskodoxBusinessProfileScreenState();
}

class _AskodoxBusinessProfileScreenState extends ConsumerState<AskodoxBusinessProfileScreen> {
  final _boxes = {for (final f in _profileFields) f.id: TextEditingController()};
  // The shop name is typed (never spoken): a spoken name is where the wrong letters came from.
  final _name = TextEditingController();
  String _savedName = '';
  AskodoxNameChange? _nameRule;
  final _catOther = TextEditingController();
  final _subOther = TextEditingController();
  String _lat = '';
  String _lng = '';
  List<AskodoxJson> _cats = const [];
  String? _cat;
  String? _sub;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final box in _boxes.values) {
      box.dispose();
    }
    _name.dispose();
    _catOther.dispose();
    _subOther.dispose();
    super.dispose();
  }

  List<AskodoxJson> _subsOf(String? cat) {
    for (final c in _cats) {
      if (c['key'] == cat) return askodoxPosList(c['subs']);
    }
    return const [];
  }

  /// A stored value -> (dropdown choice, typed words). "other:words" and old free text become Others.
  (String?, String) _choice(String stored, Iterable<String> keys) {
    if (stored.isEmpty) return (null, '');
    if (stored.startsWith('other:')) return ('other', stored.substring(6));
    if (keys.contains(stored)) return (stored, '');
    return ('other', stored);
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      _cats = await repo.shopCategories();
    } catch (_) {}
    try {
      try {
        _nameRule = AskodoxNameChange.fromJson((await repo.business(widget.businessId))['name_change']);
      } catch (_) {}
      final shop = await repo.shopState(widget.businessId);
      _savedName = '${shop['name'] ?? ''}';
      _name.text = _savedName;
      final fields = askodoxPosMap(askodoxPosMap(shop['profile'])['fields']);
      for (final entry in _boxes.entries) {
        entry.value.text = '${fields[entry.key] ?? ''}';
      }
      if (_boxes['address']!.text.isEmpty) _boxes['address']!.text = '${shop['address'] ?? ''}';
      _lat = '${fields['lat'] ?? ''}';
      _lng = '${fields['lng'] ?? ''}';
      final (cat, catWords) = _choice('${fields['category'] ?? ''}', [for (final c in _cats) '${c['key']}']);
      _cat = cat;
      _catOther.text = catWords;
      final (sub, subWords) =
          _choice('${fields['subcategory'] ?? ''}', [for (final x in _subsOf(cat)) '${x['key']}']);
      _sub = sub;
      _subOther.text = subWords;
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  String _stored(String? choice, TextEditingController words) {
    if (choice == null) return '';
    if (choice != 'other') return choice;
    final typed = words.text.trim();
    return typed.isEmpty ? '' : 'other:$typed';
  }

  Future<void> _save() async {
    final te = _bizTe(context);
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final repo = ref.read(askodoxPosRepositoryProvider);
    final newName = _name.text.trim();
    if (newName.isEmpty) {
      setState(() {
        _busy = false;
        _message = te ? 'షాప్ పేరు ఖాళీగా ఉంచకండి.' : 'The shop name cannot be empty.';
      });
      return;
    }
    try {
      if (newName != _savedName) {
        await repo.renameBusiness(widget.businessId, newName);
        _savedName = newName;
      }
      final saved = await repo.saveShopProfile(widget.businessId, {
            for (final e in _boxes.entries) e.key: e.value.text.trim(),
            'lat': _lat,
            'lng': _lng,
            'category': _stored(_cat, _catOther),
            'subcategory': _cat == null ? '' : _stored(_cat == 'other' ? 'other' : _sub, _subOther),
          });
      final missing = askodoxPosMap(saved['profile'])['missing'];
      final left = missing is List ? missing.length : 0;
      if (mounted) {
        setState(() => _message = left == 0
            ? (te ? 'సేవ్ అయింది. ASKODOX చూసి నిర్ధారిస్తుంది.' : 'Saved. ASKODOX will check and verify.')
            : (te ? 'సేవ్ అయింది. ఇంకా $left తప్పనిసరి వివరాలు మిగిలాయి.' : 'Saved. $left required details are still empty.'));
      }
    } on AskodoxPosException catch (e) {
      // The server's own reason (for example "name can be changed after 12 Dec") is shown as it is.
      if (mounted) {
        setState(() => _message = e.kind == 'conflict' && e.detail.isNotEmpty
            ? e.detail
            : (te ? 'సేవ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not save. Try again.'));
      }
    } catch (_) {
      if (mounted) setState(() => _message = te ? 'సేవ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste(TextEditingController box) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) setState(() => box.text = text);
  }

  Future<void> _pickHours(TextEditingController box, bool te) async {
    final open = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 9, minute: 0), helpText: te ? 'తెరిచే సమయం' : 'Opens at');
    if (open == null || !mounted) return;
    final close = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 21, minute: 0), helpText: te ? 'మూసే సమయం' : 'Closes at');
    if (close == null || !mounted) return;
    final fmt = MaterialLocalizations.of(context);
    setState(() => box.text = '${fmt.formatTimeOfDay(open)} – ${fmt.formatTimeOfDay(close)}');
  }

  Future<void> _pickPlace(TextEditingController box, bool te) async {
    final lat = double.tryParse(_lat);
    final lng = double.tryParse(_lng);
    final place = await AskodoxMapPinPicker.open(context,
        title: te ? 'మీ షాప్ ఎక్కడ ఉంది?' : 'Where is your shop?',
        initial: lat != null && lng != null ? AskodoxPlace(latitude: lat, longitude: lng, label: box.text) : null);
    if (place == null || !mounted) return;
    setState(() {
      box.text = place.label;
      _lat = place.latitude.toStringAsFixed(6);
      _lng = place.longitude.toStringAsFixed(6);
    });
  }

  /// The right helper inside each box: mic for sentences, paste for links, clock for hours, map for the address.
  Widget? _suffix(_ProfileField f, bool te) {
    final box = _boxes[f.id]!;
    return switch (f.fill) {
      _Fill.words => askodoxBoxMic(context, box),
      _Fill.link => IconButton(
          key: Key('askodoxBusinessPaste-${f.id}'),
          tooltip: te ? 'పేస్ట్ చేయండి' : 'Paste',
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: () => _paste(box)),
      _Fill.hours => IconButton(
          key: const Key('askodoxBusinessHoursPick'),
          tooltip: te ? 'సమయం ఎంచుకోండి' : 'Pick the hours',
          icon: const Icon(Icons.schedule_rounded),
          onPressed: () => _pickHours(box, te)),
      _Fill.place => IconButton(
          key: const Key('askodoxBusinessMapPick'),
          tooltip: te ? 'మ్యాప్‌లో ఎంచుకోండి' : 'Pick on the map',
          icon: Icon(Icons.location_on_rounded, color: _lat.isEmpty ? null : const Color(0xFF16A34A)),
          onPressed: () => _pickPlace(box, te)),
      _ => null,
    };
  }

  TextInputType _keyboard(_Fill fill, int lines) => switch (fill) {
        _Fill.link => TextInputType.url,
        _Fill.phone => TextInputType.phone,
        _ => lines > 1 ? TextInputType.multiline : TextInputType.text,
      };

  Widget _otherBox(String key, TextEditingController box, String en, String teLabel, bool te) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: Key(key),
          controller: box,
          decoration: InputDecoration(
              labelText: te ? teLabel : en,
              border: const OutlineInputBorder(),
              suffixIcon: askodoxBoxMic(context, box)),
        ),
      );

  /// What you sell: category, then sub-category, both picked from the ready list; "Others" = type your own.
  List<Widget> _categoryPickers(bool te) {
    String label(AskodoxJson m) => '${te ? m['te'] : m['en']}';
    final others = te ? 'ఇతరాలు (మీరే రాయండి)' : 'Others (type your own)';
    final subs = _subsOf(_cat);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          key: const Key('askodoxBusinessCategory'),
          initialValue: _cat,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: te ? '★ ఏం అమ్ముతారు / చేస్తారు (కేటగిరీ)' : '★ What you sell / do (category)',
              border: const OutlineInputBorder()),
          items: [
            for (final c in _cats) DropdownMenuItem(value: '${c['key']}', child: Text(label(c))),
            DropdownMenuItem(value: 'other', child: Text(others)),
          ],
          onChanged: (v) => setState(() {
            _cat = v;
            _sub = null;
          }),
        ),
      ),
      if (_cat == 'other')
        _otherBox('askodoxBusinessCategoryOther', _catOther, 'Your category', 'మీ కేటగిరీ', te),
      if (_cat != null && _cat != 'other')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            key: ValueKey('askodoxBusinessSubcategory-$_cat'),
            initialValue: _sub,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: te ? 'సబ్ కేటగిరీ' : 'Sub-category', border: const OutlineInputBorder()),
            items: [
              for (final x in subs) DropdownMenuItem(value: '${x['key']}', child: Text(label(x))),
              DropdownMenuItem(value: 'other', child: Text(others)),
            ],
            onChanged: (v) => setState(() => _sub = v),
          ),
        ),
      if (_cat == 'other' || _sub == 'other')
        _otherBox('askodoxBusinessSubcategoryOther', _subOther, 'What exactly (e.g. country chicken)',
            'ఏమిటి సరిగ్గా (ఉదా: నాటు కోడి)', te),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _bizTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిజినెస్ వివరాలు' : 'Business details')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(te
                    ? '★ ఉన్నవి తప్పనిసరి. మిగతావి మీ ఇష్టం. ఇవే కస్టమర్లకు ముందు కనిపిస్తాయి.'
                    : '★ are required. The rest is up to you. Customers see these first.'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('askodoxBusinessName'),
                  controller: _name,
                  maxLength: 80,
                  enabled: _nameRule?.canChange ?? true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: te ? '★ షాప్ పేరు' : '★ Shop name',
                      helperMaxLines: 3,
                      helperText: _nameRule?.text(te) ?? (te ? 'టైప్ చేయండి; మైక్ ఇక్కడ లేదు' : 'Type it; no mic here'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ..._categoryPickers(te),
                for (final f in _profileFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      key: Key('askodoxBusinessField-${f.id}'),
                      controller: _boxes[f.id],
                      maxLines: f.lines,
                      keyboardType: _keyboard(f.fill, f.lines),
                      decoration: InputDecoration(
                          labelText: '${f.must ? '★ ' : ''}${te ? f.te : f.en}',
                          helperText: f.fill == _Fill.place && _lat.isNotEmpty
                              ? (te ? 'మ్యాప్‌లో పిన్ పెట్టారు ✓' : 'Pinned on the map ✓')
                              : null,
                          border: const OutlineInputBorder(),
                          suffixIcon: _suffix(f, te)),
                    ),
                  ),
                FilledButton(
                  key: const Key('askodoxBusinessProfileSave'),
                  onPressed: _busy ? null : _save,
                  child: Text(te ? 'సేవ్ చేయండి' : 'Save'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!),
                ],
              ],
            ),
    );
  }
}

/// How a bill was paid (owner 2026-11-16): the app the customer used, cash, card, or `due` (not paid in full).
const askodoxBillPayModes = <(String, String, String)>[
  ('cash', 'Cash', 'క్యాష్'),
  ('phonepe', 'PhonePe', 'PhonePe'),
  ('gpay', 'Google Pay', 'Google Pay'),
  ('paytm', 'Paytm', 'Paytm'),
  ('other_upi', 'Other UPI', 'ఇతర UPI'),
  ('card', 'Card', 'కార్డ్'),
  ('due', 'Pending / part paid', 'బాకీ / సగం కట్టారు'),
];

class _BillLine {
  /// The item's NUMBER on the shop's menu ("3"): fills the name and today's rate from the menu.
  final no = TextEditingController();
  String unit = 'kg';
  final name = TextEditingController();
  final amount = TextEditingController();
  // Today's rate and the weight / quantity: the total fills itself (rate x weight) and can still be typed over.
  final rate = TextEditingController();
  final qty = TextEditingController();

  double get value => double.tryParse(amount.text.trim().replaceAll(',', '')) ?? 0;
  double get rateValue => double.tryParse(rate.text.trim().replaceAll(',', '')) ?? 0;
  double get qtyValue => double.tryParse(qty.text.trim().replaceAll(',', '')) ?? 0;

  /// rate x weight -> total, only while both are filled.
  void recompute() {
    if (rateValue > 0 && qtyValue > 0) {
      final t = rateValue * qtyValue;
      amount.text = t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(2);
    }
  }

  /// "Chicken (30 kg x ₹210)" -- what the bill and the invoice show.
  String label(String unit) {
    final n = name.text.trim();
    if (rateValue > 0 && qtyValue > 0) {
      String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
      return '${n.isEmpty ? '' : '$n '}(${f(qtyValue)} $unit × ₹${f(rateValue)})'.trim();
    }
    return n;
  }

  void dispose() {
    no.dispose();
    name.dispose();
    amount.dispose();
    rate.dispose();
    qty.dispose();
  }
}

/// A calculator bill (no catalogue): type the amounts, show the UPI QR for the total, share the bill picture.
/// The bill is not stored; the money goes straight to the shop's own UPI.
class AskodoxQuickBillScreen extends ConsumerStatefulWidget {
  const AskodoxQuickBillScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxQuickBillScreen> createState() => _AskodoxQuickBillScreenState();
}

class _AskodoxQuickBillScreenState extends ConsumerState<AskodoxQuickBillScreen> {
  final _billKey = GlobalKey();
  final _lines = <_BillLine>[_BillLine()];
  String _shopName = '';
  String _upi = '';
  String _payee = '';
  // Real bill (owner 2026-11-15): advance + pending on a customer; GST only when the shop is registered.
  final _advance = TextEditingController();
  final _custName = TextEditingController();
  final _custPhone = TextEditingController();
  bool _gstShop = false;
  int _rateBp = 0;
  String _method = 'cash';
  bool _saving = false;
  String _txn = askodoxNewTxnId();
  AskodoxJson? _saved;
  // Owner 2026-11-17: Cash | Online | Baaki, "both" = part cash + part online (the rest is baaki).
  bool _split = false;
  final _cashPart = TextEditingController();
  final _onlinePart = TextEditingController();
  AskodoxJson? _sound; // a payment voice alert of this amount in the last 15 min (PhonePe / GPay / bank SMS ...)
  String? _reviseOf; // editing a saved bill = the same-day revise (a new bill replaces the old one)
  AskodoxJson? _paper;

  bool get _online => const ['online', 'phonepe', 'gpay', 'paytm', 'bhim', 'other_upi', 'card'].contains(_method);
  int _paise(TextEditingController c) => askodoxParsePaise(c.text.trim().isEmpty ? '0' : c.text) ?? 0;

  double get _total => _lines.fold(0, (sum, line) => sum + line.value);
  int get _typedAdvancePaise => askodoxParsePaise(_advance.text.trim().isEmpty ? '0' : _advance.text) ?? 0;

  /// What was paid now: the typed amount, else the whole bill -- unless the cashier chose "pending".
  int get _advancePaise {
    if (_split) return _paise(_cashPart) + _paise(_onlinePart);
    final typed = _typedAdvancePaise;
    if (_method == 'due') return typed;
    return (_total * 100).round();
  }

  /// The shop's menu by item number (billing by number).
  Map<int, AskodoxJson> _menuByNo = const {};

  void _applyNumber(int i) {
    final line = _lines[i];
    final item = _menuByNo[int.tryParse(line.no.text.trim()) ?? 0];
    if (item == null) return;
    line.name.text = '${item['name']}';
    line.unit = '${item['unit'] ?? 'pcs'}';
    line.rate.text = _rupees(askodoxPosInt(item['price_paise']) / 100);
    if (line.qtyValue <= 0) line.qty.text = '1';
    line.recompute();
    _txn = askodoxNewTxnId();
  }

  void _newBill() {
    setState(() {
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..add(_BillLine());
      _advance.clear();
      _custName.clear();
      _custPhone.clear();
      _method = 'cash';
      _split = false;
      _cashPart.clear();
      _onlinePart.clear();
      _sound = null;
      _reviseOf = null;
      _paper = null;
      _saved = null;
      _txn = askodoxNewTxnId();
    });
  }

  /// The app the money came in on, from a payment alert's source ("com.phonepe.app", "sms" ...).
  static String _appOf(AskodoxJson ev) {
    final s = '${ev['source_app']} ${ev['source_label']}'.toLowerCase();
    if (s.contains('phonepe')) return 'phonepe';
    if (s.contains('paisa') || s.contains('google') || s.contains('gpay')) return 'gpay';
    if (s.contains('paytm')) return 'paytm';
    if (s.contains('bhim')) return 'bhim';
    return 'other_upi';
  }

  /// Looks for a payment voice alert of exactly the online amount in the last 15 minutes; the cashier confirms it.
  Future<void> _findSound() async {
    final want = _split ? _paise(_onlinePart) : (_total * 100).round();
    if (want <= 0) return;
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(minutes: 15)).toIso8601String();
      final events = askodoxPosList((await ref
              .read(askodoxPosRepositoryProvider)
              .paymentEvents(widget.businessId, since: since, q: (want / 100).toStringAsFixed(want % 100 == 0 ? 0 : 2), limit: 5))['events']);
      final hit = events.where((e) => askodoxPosInt(e['amount_paise']) == want && e['test'] != true).firstOrNull;
      if (mounted) setState(() => _sound = hit);
    } catch (_) {}
  }

  /// ✏ on a saved bill: the same lines come back to change; saving makes a new bill and cancels the old (same day).
  void _revise() {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      _reviseOf = '${saved['id']}';
      _saved = null;
      _paper = null;
      _txn = askodoxNewTxnId();
    });
  }

  /// The saved bill to the customer's NUMBER: an ASKODOX user gets it in the app; anyone else gets a WhatsApp
  /// message opened straight on that number (no contact needed).
  Future<void> _sendToNumber() async {
    final te = _bizTe(context);
    final messenger = ScaffoldMessenger.of(context);
    final digits = _custPhone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) {
      messenger.showSnackBar(SnackBar(content: Text(te ? 'కస్టమర్ 10 అంకెల నంబర్ రాయండి.' : "Type the customer's 10-digit number.")));
      return;
    }
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).billSend(widget.businessId, '${_saved!['id']}', digits);
      if ('${out['channel']}' == 'askodox') {
        messenger.showSnackBar(SnackBar(
            content: Text(te ? 'బిల్లు కస్టమర్ ASKODOX యాప్‌లోకి వెళ్ళింది ✓' : "Sent to the customer's ASKODOX app ✓")));
        return;
      }
      final text = '${out['text'] ?? ''}';
      final uri = Uri.parse('https://wa.me/${out['whatsapp_to']}?text=${Uri.encodeComponent(text)}');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(SnackBar(
            content: Text(te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.')));
      }
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _advance.dispose();
    _custName.dispose();
    _custPhone.dispose();
    _cashPart.dispose();
    _onlinePart.dispose();
    super.dispose();
  }

  _BillLine _lineAt(int index) {
    while (_lines.length <= index) {
      _lines.add(_BillLine());
    }
    return _lines[index];
  }

  /// Turns the typed lines into a REAL bill: numbered, GST only for a registered shop, the advance as paid,
  /// the rest pending on the customer. The same request twice is the same bill (txn id).
  Future<void> _makeReal() async {
    final te = _bizTe(context);
    setState(() => _saving = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).quickBill(widget.businessId, {
        'lines': [
          for (final l in _lines)
            if (l.value > 0)
              {
                'name': l.name.text.trim(),
                'amount_paise': (l.value * 100).round(),
                if (l.rateValue > 0 && l.qtyValue > 0) ...{
                  'rate_paise': (l.rateValue * 100).round(),
                  'qty_milli': (l.qtyValue * 1000).round(),
                },
              }
        ],
        'advance_paise': _split ? 0 : _advancePaise,
        'method': _method == 'due' ? 'cash' : _method,
        if (_split) ...{'cash_paise': _paise(_cashPart), 'online_paise': _paise(_onlinePart)},
        if (_reviseOf != null) 'revise_of': _reviseOf,
        'name': _custName.text.trim(),
        'phone': _custPhone.text.trim(),
        'rate_bp': _gstShop ? _rateBp : 0,
        'client_txn_id': _txn,
      });
      if (mounted) {
        setState(() {
          _saved = out;
          _reviseOf = null;
        });
        if ('${out['revise_note'] ?? ''}'.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${out['revise_note']}')));
        }
        unawaited(_loadPaper('${out['id']}'));
      }
    } on AskodoxPosException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.code == 'balance' || e.code == 'payment'
                ? (te ? 'బాకీ ఉంటే కస్టమర్ పేరు లేదా ఫోన్ రాయండి, లేదా అడ్వాన్స్ రాయండి.' : 'For a pending balance give the customer name or phone, or enter the advance.')
                : e.message(te))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadPaper(String invoiceId) async {
    try {
      final paper = await ref.read(askodoxPosRepositoryProvider).billPaper(widget.businessId, invoiceId);
      if (mounted) setState(() => _paper = paper);
    } catch (_) {}
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final biz = await repo.business(widget.businessId);
      if (mounted) setState(() => _gstShop = '${biz['registration_type'] ?? 'unregistered'}' != 'unregistered');
    } catch (_) {}
    try {
      final menu = askodoxPosList((await repo.deskMenu(widget.businessId))['items']);
      if (mounted) {
        setState(() => _menuByNo = {
              for (final m in menu)
                if (askodoxPosInt(m['item_no']) > 0) askodoxPosInt(m['item_no']): m,
            });
      }
    } catch (_) {}
    try {
      final shop = await repo.shopState(widget.businessId);
      if (mounted) setState(() => _shopName = '${shop['name']}');
    } catch (_) {}
    try {
      final upis = [
        for (final m in await repo.myPaymentMethods())
          if ('${m['upi_id'] ?? ''}'.isNotEmpty) m,
      ];
      if (upis.isNotEmpty && mounted) {
        final m = upis.firstWhere((u) => u['is_default'] == true, orElse: () => upis.first);
        setState(() {
          _upi = '${m['upi_id']}';
          _payee = '${m['payee_name'] ?? ''}';
        });
      }
    } catch (_) {}
  }

  void _showQr(bool te) {
    final total = _total;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(te ? '₹${_rupees(total)} కట్టండి' : 'Pay ₹${_rupees(total)}'),
        content: _upi.isEmpty
            ? Text(te
                ? 'మీ UPI QR ఇంకా జోడించలేదు. "నా QR / ఖాతాలు" లో జోడించండి.'
                : 'Your UPI QR is not added yet. Add it in "My QR / accounts".')
            : SizedBox(
                width: 240,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  QrImageView(
                    key: const Key('askodoxQuickBillQr'),
                    data: 'upi://pay?pa=${Uri.encodeComponent(_upi)}'
                        '${_payee.isEmpty ? '' : '&pn=${Uri.encodeComponent(_payee)}'}'
                        '&am=${total.toStringAsFixed(2)}&cu=INR',
                    size: 220,
                  ),
                  const SizedBox(height: 8),
                  Text(_upi),
                ]),
              ),
        actions: [
          if (_upi.isEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.push('/me/payment-methods');
              },
              child: Text(te ? 'జోడించండి' : 'Add'),
            ),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(te ? 'సరే' : 'OK')),
        ],
      ),
    );
  }

  /// The bill as a picture: straight into WhatsApp ([whatsapp]) or the share sheet. Never silent: a phone that
  /// cannot share gets a message (owner 2026-11-15, pani A).
  Future<void> _share({bool whatsapp = false}) async {
    final te = _bizTe(context);
    final boundary = _billKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List bytes = data!.buffer.asUint8List();
    final upiLine = _upi.isEmpty ? '' : '\nUPI: $_upi';
    final ok = await askodoxShareImage(bytes,
        name: 'askodox-bill',
        text: '${_shopName.isEmpty ? 'Bill' : _shopName} · ₹${_rupees(_total)}$upiLine · ASKODOX',
        packages: whatsapp ? askodoxWhatsAppPackages : const []);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(te ? 'ఈ ఫోన్‌లో షేర్ తెరుచుకోలేదు. యాప్ అప్‌డేట్ చేసి మళ్ళీ ప్రయత్నించండి.' : 'Sharing did not open on this phone. Update the app and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _bizTe(context);
    final total = _total;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లు' : 'Bill')),
      bottomNavigationBar: AskodoxFillBar(
        lang: _bizLang(context),
        onFilled: () => setState(() {
          _txn = askodoxNewTxnId();
          for (final l in _lines) {
            l.recompute();
          }
        }),
        fields: () => [
          for (var i = 0; i < _lines.length + 3; i++) ...[
            if (_menuByNo.isNotEmpty)
              AskodoxFillField('no-$i', te ? '${i + 1}వ వస్తువు మెనూ నంబర్' : 'Item ${i + 1} menu number', kind: 'number',
                  apply: (t) => setState(() {
                        _lineAt(i).no.text = t;
                        _applyNumber(i);
                      })),
            AskodoxFillField('rate-$i', te ? '${i + 1}వ వస్తువు ఈ రోజు రేటు' : 'Item ${i + 1} rate today', kind: 'number',
                controller: i < _lines.length ? _lines[i].rate : null,
                apply: i < _lines.length ? null : (t) => setState(() => _lineAt(i).rate.text = t)),
            AskodoxFillField('qty-$i', te ? '${i + 1}వ వస్తువు బరువు కిలోలలో' : 'Item ${i + 1} weight in kg', kind: 'number',
                controller: i < _lines.length ? _lines[i].qty : null,
                apply: i < _lines.length ? null : (t) => setState(() => _lineAt(i).qty.text = t)),
            AskodoxFillField('item-$i', te ? '${i + 1}వ వస్తువు పేరు' : 'Item ${i + 1} name',
                controller: i < _lines.length ? _lines[i].name : null,
                apply: i < _lines.length ? null : (t) => setState(() => _lineAt(i).name.text = t)),
            AskodoxFillField('amount-$i', te ? '${i + 1}వ వస్తువు రూపాయలు' : 'Item ${i + 1} amount in rupees',
                kind: 'number',
                controller: i < _lines.length ? _lines[i].amount : null,
                apply: i < _lines.length ? null : (t) => setState(() => _lineAt(i).amount.text = t)),
          ],
          AskodoxFillField('advance', te ? 'అడ్వాన్స్ (ముందే కట్టినది)' : 'Advance paid', kind: 'number', controller: _advance),
          AskodoxFillField('customer', te ? 'కస్టమర్ పేరు' : 'Customer name', controller: _custName),
          AskodoxFillField('phone', te ? 'కస్టమర్ ఫోన్' : 'Customer phone', kind: 'phone', controller: _custPhone),
          AskodoxFillField('method', te ? 'చెల్లింపు విధానం' : 'Payment method',
              kind: 'choice',
              options: [for (final m in askodoxBillPayModes) m.$1],
              apply: (t) => setState(() => _method = t)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                Row(children: [
                  if (_menuByNo.isNotEmpty) ...[
                    SizedBox(
                      width: 68,
                      child: TextField(
                        key: Key('askodoxQuickBillNo-$i'),
                        controller: _lines[i].no,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _applyNumber(i)),
                        decoration: InputDecoration(labelText: te ? 'నం.' : 'No.', border: const OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _lines[i].name,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: te ? 'వస్తువు (ఉదా: చికెన్)' : 'Item (e.g. Chicken)',
                          border: const OutlineInputBorder(),
                          suffixIcon: askodoxBoxMic(context, _lines[i].name, changed: () => setState(() {}))),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: Key('askodoxQuickBillRate-$i'),
                      controller: _lines[i].rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _lines[i].recompute()),
                      decoration: InputDecoration(labelText: te ? 'ఈ రోజు రేటు ₹' : "Today's rate ₹", border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: Key('askodoxQuickBillQty-$i'),
                      controller: _lines[i].qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _lines[i].recompute()),
                      decoration: InputDecoration(labelText: te ? 'ఎన్ని / బరువు' : 'Count / weight', border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: Key('askodoxQuickBillAmount-$i'),
                      controller: _lines[i].amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: te ? 'మొత్తం ₹' : 'Total ₹', border: const OutlineInputBorder()),
                    ),
                  ),
                  if (_lines.length > 1)
                    IconButton(
                      key: Key('askodoxQuickBillRemove-$i'),
                      tooltip: te ? 'లైన్ తీసేయి' : 'Remove line',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                    ),
                ]),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lines.add(_BillLine())),
              icon: const Icon(Icons.add),
              label: Text(te ? 'ఇంకో లైన్' : 'Add a line'),
            ),
          ),
          const SizedBox(height: 8),
          Text(te ? 'ఎలా కట్టారు?' : 'How was it paid?', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          // Owner 2026-11-17: three big buttons, "both" for part cash + part online; what is left is baaki.
          Row(children: [
            for (final m in const [('cash', '💵', 'Cash', 'క్యాష్'), ('online', '📱', 'Online', 'ఆన్‌లైన్'), ('due', '📒', 'Baaki', 'బాకీ')])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Material(
                    color: (m.$1 == 'online' ? _online : _method == m.$1) && !_split ? const Color(0xFF1E3FA0) : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: Key('askodoxQuickBillPay-${m.$1}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _split = false;
                          _method = m.$1;
                          _txn = askodoxNewTxnId();
                        });
                        if (m.$1 == 'online') unawaited(_findSound());
                      },
                      child: SizedBox(
                        height: 58,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(m.$2, style: const TextStyle(fontSize: 18)),
                          Text(te ? m.$4 : m.$3,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: (m.$1 == 'online' ? _online : _method == m.$1) && !_split ? Colors.white : const Color(0xFF1F2937))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          CheckboxListTile(
            key: const Key('askodoxQuickBillSplit'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _split,
            title: Text(te ? 'రెండూ — కొంత క్యాష్, కొంత ఆన్‌లైన్ (మిగిలింది బాకీ)' : 'Both — part cash, part online (the rest is baaki)'),
            onChanged: (v) => setState(() {
              _split = v ?? false;
              if (_split && !_online) _method = 'online';
              _txn = askodoxNewTxnId();
            }),
          ),
          if (_split)
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('askodoxQuickBillCashPart'),
                  controller: _cashPart,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() => _txn = askodoxNewTxnId()),
                  decoration: InputDecoration(labelText: te ? 'క్యాష్ ₹' : 'Cash ₹', border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('askodoxQuickBillOnlinePart'),
                  controller: _onlinePart,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() => _txn = askodoxNewTxnId()),
                  onEditingComplete: () => unawaited(_findSound()),
                  decoration: InputDecoration(labelText: te ? 'ఆన్‌లైన్ ₹' : 'Online ₹', border: const OutlineInputBorder()),
                ),
              ),
            ]),
          if (_online || _split) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in askodoxBillPayModes.where((m) => const ['phonepe', 'gpay', 'paytm', 'other_upi', 'card'].contains(m.$1)))
                ChoiceChip(
                  key: Key('askodoxQuickBillApp-${m.$1}'),
                  visualDensity: VisualDensity.compact,
                  label: Text(te ? m.$3 : m.$2),
                  selected: _method == m.$1,
                  onSelected: (on) => setState(() {
                    _method = on ? m.$1 : 'online';
                    _txn = askodoxNewTxnId();
                  }),
                ),
            ]),
            if (_sound != null)
              Container(
                key: const Key('askodoxQuickBillSound'),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFE7F5EE), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Text('🔔', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        te
                            ? '${_sound!['source_label']} లో ₹${_rupees(askodoxPosInt(_sound!['amount_paise']) / 100)} సౌండ్ వచ్చింది — ఇదేనా?'
                            : '${_sound!['source_label']}: ₹${_rupees(askodoxPosInt(_sound!['amount_paise']) / 100)} alert came — this one?',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    key: const Key('askodoxQuickBillSoundYes'),
                    onPressed: () => setState(() {
                      _method = _appOf(_sound!);
                      _sound = null;
                      _txn = askodoxNewTxnId();
                    }),
                    child: Text(te ? 'అవును' : 'Yes'),
                  ),
                ]),
              ),
          ],
          if (_method == 'due' && !_split) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('askodoxQuickBillAdvance'),
              controller: _advance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _txn = askodoxNewTxnId()),
              decoration: InputDecoration(
                  labelText: te ? 'ఇప్పుడు కట్టింది ₹ (ఏమీ లేకపోతే ఖాళీ)' : 'Paid now ₹ (empty if nothing)', border: const OutlineInputBorder()),
            ),
          ],
          if (_advancePaise < (total * 100).round() && (_method == 'due' || _split) && total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(te ? 'బాకీ ₹${_rupees(total - _advancePaise / 100)} — కస్టమర్ పేరు / నంబర్ రాయండి' : 'Baaki ₹${_rupees(total - _advancePaise / 100)} — add the customer name / number',
                  key: const Key('askodoxQuickBillPending'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _custName,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: te ? 'కస్టమర్ పేరు' : 'Customer name', border: const OutlineInputBorder(), suffixIcon: askodoxBoxMic(context, _custName))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                  controller: _custPhone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: te ? 'కస్టమర్ నంబర్ (బిల్లు పంపడానికి)' : 'Customer number (to send the bill)',
                      border: const OutlineInputBorder())),
            ),
          ]),
          if (_gstShop) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              key: const Key('askodoxQuickBillGst'),
              initialValue: _rateBp,
              decoration: InputDecoration(labelText: te ? 'GST % (ధరలో కలిసి ఉంది)' : 'GST % (included in the prices)', border: const OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0, child: Text('0%')),
                DropdownMenuItem(value: 500, child: Text('5%')),
                DropdownMenuItem(value: 1200, child: Text('12%')),
                DropdownMenuItem(value: 1800, child: Text('18%')),
              ],
              onChanged: (v) => setState(() => _rateBp = v ?? 0),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('askodoxQuickBillSave'),
            onPressed: total > 0 && !_saving && _saved == null ? _makeReal : null,
            icon: const Icon(Icons.receipt_long),
            label: Text(_reviseOf != null
                ? (te ? 'మార్చిన బిల్లు సేవ్ చేయి (పాతది రద్దు)' : 'Save the changed bill (old one cancelled)')
                : (te ? 'నిజమైన బిల్లు చేయండి (నంబర్ వస్తుంది)' : 'Make the real bill (gets a number)')),
          ),
          if (_saved != null)
            Card(
              key: const Key('askodoxQuickBillSaved'),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${te ? 'బిల్లు' : 'Bill'} ${_saved!['number'] ?? ''} ✓  ${te ? 'కట్టింది' : 'Paid'} ₹${_rupees(askodoxPosInt(_saved!['advance_paise']) / 100)} · ${te ? 'బాకీ' : 'Pending'} ₹${_rupees(askodoxPosInt(_saved!['pending_paise']) / 100)}'
                        '${'${_saved!['revised_from'] ?? ''}'.isNotEmpty ? (te ? '\n(${_saved!['revised_from']} బదులు)' : '\n(replaces ${_saved!['revised_from']})') : ''}'),
                  ),
                  // Edit = the same day revise: the lines come back, saving makes a new bill and cancels this one.
                  OutlinedButton.icon(
                    key: const Key('askodoxQuickBillEdit'),
                    onPressed: _revise,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(te ? 'మార్చు' : 'Edit'),
                  ),
                ]),
              ),
            ),
          if (_saved != null && _paper != null) ...[
            const SizedBox(height: 6),
            AskodoxPaperBill(paper: _paper!, te: te),
          ],
          if (_saved != null) ...[
            const SizedBox(height: 6),
            FilledButton.icon(
              key: const Key('askodoxQuickBillSendNumber'),
              onPressed: _sendToNumber,
              icon: const Icon(Icons.send_rounded),
              label: Text(te ? 'ఈ నంబర్‌కి బిల్లు పంపు (ASKODOX / WhatsApp)' : 'Send the bill to this number (ASKODOX / WhatsApp)'),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxQuickBillPrint'),
                  onPressed: () => askodoxPrintInvoice(context, ref, _saved!),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(te ? 'ప్రింట్' : 'Print'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxQuickBillHistory'),
                  onPressed: () => context.push('/bills/${widget.businessId}'),
                  icon: const Icon(Icons.history),
                  label: Text(te ? 'హిస్టరీ' : 'History'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxQuickBillNew'),
                  onPressed: _newBill,
                  icon: const Icon(Icons.add),
                  label: Text(te ? 'కొత్త బిల్లు' : 'New bill'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _billKey,
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_shopName.isEmpty ? 'ASKODOX' : _shopName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        if (_custName.text.trim().isNotEmpty)
                          Text('${te ? 'కస్టమర్' : 'Customer'}: ${_custName.text.trim()}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                        const SizedBox(height: 8),
                        for (final line in _lines)
                          if (line.value > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(line.label(line.unit).isEmpty ? '—' : line.label(line.unit),
                                          style: const TextStyle(color: Color(0xFF0F172A)))),
                                  Text('₹${_rupees(line.value)}', style: const TextStyle(color: Color(0xFF0F172A))),
                                ],
                              ),
                            ),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                                child: Text(te ? 'మొత్తం' : 'Total',
                                    style: const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)))),
                            Text('₹${_rupees(total)}',
                                key: const Key('askodoxQuickBillTotal'),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: const Text('Billed with ASKODOX', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('askodoxQuickBillShowQr'),
            onPressed: total > 0 ? () => _showQr(te) : null,
            icon: const Icon(Icons.qr_code_2),
            label: Text(te ? 'QR చూపండి (స్కాన్ చేసి కట్టడానికి)' : 'Show QR (scan to pay)'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('askodoxQuickBillWhatsApp'),
            onPressed: total > 0 ? () => _share(whatsapp: true) : null,
            icon: const Icon(Icons.chat_rounded),
            label: Text(te ? 'WhatsApp లో బిల్లు పంపండి' : 'Send the bill on WhatsApp'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('askodoxQuickBillShare'),
            onPressed: total > 0 ? () => _share() : null,
            icon: const Icon(Icons.share_outlined),
            label: Text(te ? 'ఇతర యాప్‌లలో పంపండి' : 'Send in another app'),
          ),
          const SizedBox(height: 8),
          Text(te
              ? 'బిల్లు పంపడం మీ ఇష్టం. డబ్బు నేరుగా మీ UPI కే వస్తుంది; ASKODOX డబ్బు పట్టుకోదు.'
              : 'Sending the bill is optional. Money goes straight to your UPI; ASKODOX never holds it.'),
        ],
      ),
    );
  }
}
