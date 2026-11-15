import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/share/askodox_image_share.dart';
import '../../growth/data/growth_repository.dart' show AskodoxPlace;
import '../../home/presentation/question_mic.dart';
import '../../location/presentation/map_pin_picker.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxParsePaise;
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
      Widget tile(String key, IconData icon, String title, String subtitle, String route) => Card(
            child: ListTile(
              key: Key(key),
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push(route);
                if (mounted) _load();
              },
            ),
          );
      body = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (shops.length > 1)
            Padding(
              padding: const EdgeInsets.all(8),
              child: DropdownButtonFormField<String>(
                key: const Key('askodoxMyBusinessPick'),
                initialValue: id,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: te ? 'ఏ బిజినెస్?' : 'Which business?', border: const OutlineInputBorder()),
                items: [
                  for (final b in shops)
                    DropdownMenuItem<String>(value: '${b['id']}', child: Text(_shopLabel(b, te))),
                ],
                onChanged: (value) {
                  setState(() => _selected = value);
                  _load();
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${current['name']}', style: Theme.of(context).textTheme.titleLarge),
            ),
          _statusCard(id, '${current['status'] ?? 'open'}', te),
          tile('askodoxMyBusinessDetails', Icons.badge_outlined, te ? 'బిజినెస్ వివరాలు' : 'Business details',
              _statusText(te), '/me/business/$id/profile'),
          tile('askodoxMyBusinessBill', Icons.calculate_outlined, te ? 'బిల్లు చేయండి' : 'Make a bill',
              te ? 'మొత్తం వేసి, QR చూపండి, బిల్లు పంపండి' : 'Add amounts, show the QR, send the bill',
              '/me/business/$id/bill'),
          tile('askodoxMyBusinessDesk', Icons.receipt_long_outlined, te ? 'ఆర్డర్స్ డెస్క్' : 'Orders desk',
              te ? 'టేబుల్ / షాప్ QR ఆర్డర్లు, మెనూ, డెలివరీ' : 'Table / shop QR orders, menu, delivery', '/desk/$id'),
          tile('askodoxMyBusinessPost', Icons.campaign_outlined, te ? 'ఈ రోజు పోస్ట్' : "Today's post",
              te ? 'ఫాలోవర్లకు ఒక చిత్రం' : 'One picture for your followers', '/shops/$id/post'),
          tile('askodoxMyBusinessPage', Icons.storefront_outlined, te ? 'నా షాప్ పేజీ' : 'My shop page',
              te ? 'కస్టమర్లకు కనిపించేది' : 'What customers see', '/shops/$id'),
          tile('askodoxMyBusinessAccounts', Icons.qr_code_2, te ? 'నా QR / ఖాతాలు' : 'My QR / accounts',
              te ? 'డబ్బు నేరుగా మీకే వస్తుంది' : 'Money comes straight to you', '/me/payment-methods'),
          const SizedBox(height: 8),
          if (_adding) ...[
            const Divider(),
            ..._createFields(te),
            TextButton(onPressed: () => setState(() => _adding = false), child: Text(te ? 'వద్దు' : 'Cancel')),
          ] else
            OutlinedButton.icon(
              key: const Key('askodoxMyBusinessAdd'),
              onPressed: () => setState(() => _adding = true),
              icon: const Icon(Icons.add_business_outlined),
              label: Text(te ? 'ఇంకో బిజినెస్ చేర్చండి' : 'Add another business'),
            ),
        ],
      );
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

class _BillLine {
  final name = TextEditingController();
  final amount = TextEditingController();

  double get value => double.tryParse(amount.text.trim().replaceAll(',', '')) ?? 0;

  void dispose() {
    name.dispose();
    amount.dispose();
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

  double get _total => _lines.fold(0, (sum, line) => sum + line.value);
  int get _advancePaise => askodoxParsePaise(_advance.text.trim().isEmpty ? '0' : _advance.text) ?? 0;

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
    super.dispose();
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
            if (l.value > 0) {'name': l.name.text.trim(), 'amount_paise': (l.value * 100).round()}
        ],
        'advance_paise': _advancePaise,
        'method': _method,
        'name': _custName.text.trim(),
        'phone': _custPhone.text.trim(),
        'rate_bp': _gstShop ? _rateBp : 0,
        'client_txn_id': _txn,
      });
      if (mounted) setState(() => _saved = out);
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

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final biz = await repo.business(widget.businessId);
      if (mounted) setState(() => _gstShop = '${biz['registration_type'] ?? 'unregistered'}' != 'unregistered');
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _lines[i].name,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: te ? 'వస్తువు (ఇష్టమైతే)' : 'Item (optional)',
                          border: const OutlineInputBorder(),
                          suffixIcon: askodoxBoxMic(context, _lines[i].name, changed: () => setState(() {}))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: Key('askodoxQuickBillAmount-$i'),
                      controller: _lines[i].amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '₹', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
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
          Text(te ? 'ముందే కట్టినది / బాకీ' : 'Advance paid / pending', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('askodoxQuickBillAdvance'),
                controller: _advance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _txn = askodoxNewTxnId()),
                decoration: InputDecoration(labelText: te ? 'అడ్వాన్స్ ₹' : 'Advance ₹', border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _method,
              items: [
                DropdownMenuItem(value: 'cash', child: Text(te ? 'క్యాష్' : 'Cash')),
                const DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text(te ? 'కార్డ్' : 'Card')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'cash'),
            ),
          ]),
          if (_advancePaise > 0 && _advancePaise < (total * 100).round())
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(te ? 'బాకీ ₹${_rupees(total - _advancePaise / 100)}' : 'Pending ₹${_rupees(total - _advancePaise / 100)}',
                  key: const Key('askodoxQuickBillPending'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _custName,
                  decoration: InputDecoration(labelText: te ? 'కస్టమర్ పేరు' : 'Customer name', border: const OutlineInputBorder(), suffixIcon: askodoxBoxMic(context, _custName))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                  controller: _custPhone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: te ? 'ఫోన్' : 'Phone', border: const OutlineInputBorder())),
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
            label: Text(te ? 'నిజమైన బిల్లు చేయండి (నంబర్ వస్తుంది)' : 'Make the real bill (gets a number)'),
          ),
          if (_saved != null)
            Card(
              key: const Key('askodoxQuickBillSaved'),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                    '${te ? 'బిల్లు' : 'Bill'} ${_saved!['number'] ?? ''} ✓  ${te ? 'కట్టింది' : 'Paid'} ₹${_rupees(askodoxPosInt(_saved!['advance_paise']) / 100)} · ${te ? 'బాకీ' : 'Pending'} ₹${_rupees(askodoxPosInt(_saved!['pending_paise']) / 100)}'),
              ),
            ),
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
                        const SizedBox(height: 8),
                        for (final line in _lines)
                          if (line.value > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(line.name.text.trim().isEmpty ? '—' : line.name.text.trim(),
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
