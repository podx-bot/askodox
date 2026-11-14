import 'dart:typed_data';
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
class AskodoxMyBusinessScreen extends ConsumerStatefulWidget {
  const AskodoxMyBusinessScreen({super.key});

  @override
  ConsumerState<AskodoxMyBusinessScreen> createState() => _AskodoxMyBusinessScreenState();
}

class _AskodoxMyBusinessScreenState extends ConsumerState<AskodoxMyBusinessScreen> {
  final _name = TextEditingController();
  List<AskodoxJson>? _shops;
  AskodoxJson _states = const {};
  String? _state;
  String? _status;
  bool _busy = false;
  bool _failed = false;

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
      final shops = await repo.businesses();
      var states = _states;
      String? status;
      if (shops.isEmpty) {
        states = askodoxPosMap((await repo.meta())['states']);
      } else {
        final shop = await repo.shopState('${shops.first['id']}');
        status = '${askodoxPosMap(shop['profile'])['status'] ?? ''}';
      }
      if (mounted) {
        setState(() {
          _shops = shops;
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
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(te ? 'సేవ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not save. Try again.'),
          ],
        ],
      );
    } else {
      final id = '${shops.first['id']}';
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
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${shops.first['name']}', style: Theme.of(context).textTheme.titleLarge),
          ),
          tile('askodoxMyBusinessDetails', Icons.badge_outlined, te ? 'బిజినెస్ వివరాలు' : 'Business details',
              _statusText(te), '/me/business/$id/profile'),
          tile('askodoxMyBusinessBill', Icons.calculate_outlined, te ? 'బిల్లు చేయండి' : 'Make a bill',
              te ? 'మొత్తం వేసి, QR చూపండి, బిల్లు పంపండి' : 'Add amounts, show the QR, send the bill',
              '/me/business/$id/bill'),
          tile('askodoxMyBusinessPost', Icons.campaign_outlined, te ? 'ఈ రోజు పోస్ట్' : "Today's post",
              te ? 'ఫాలోవర్లకు ఒక చిత్రం' : 'One picture for your followers', '/shops/$id/post'),
          tile('askodoxMyBusinessPage', Icons.storefront_outlined, te ? 'నా షాప్ పేజీ' : 'My shop page',
              te ? 'కస్టమర్లకు కనిపించేది' : 'What customers see', '/shops/$id'),
          tile('askodoxMyBusinessAccounts', Icons.qr_code_2, te ? 'నా QR / ఖాతాలు' : 'My QR / accounts',
              te ? 'డబ్బు నేరుగా మీకే వస్తుంది' : 'Money comes straight to you', '/me/payment-methods'),
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
      final shop = await repo.shopState(widget.businessId);
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
    try {
      final saved = await ref
          .read(askodoxPosRepositoryProvider)
          .saveShopProfile(widget.businessId, {
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

  double get _total => _lines.fold(0, (sum, line) => sum + line.value);

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
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
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

  Future<void> _share() async {
    final boundary = _billKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List bytes = data!.buffer.asUint8List();
    await askodoxShareImage(bytes,
        name: 'askodox-bill', text: '$_shopName · ₹${_rupees(_total)} · ASKODOX');
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
          OutlinedButton.icon(
            key: const Key('askodoxQuickBillShare'),
            onPressed: total > 0 ? _share : null,
            icon: const Icon(Icons.share_outlined),
            label: Text(te ? 'బిల్లు పంపండి (WhatsApp మొదలైనవి)' : 'Send the bill (WhatsApp etc.)'),
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
