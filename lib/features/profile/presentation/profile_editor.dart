import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../../shared/widgets/askodox_guided_field.dart';
import '../../guide/in_app_guide.dart';
import '../../home/domain/active_role.dart';
import '../../home/presentation/question_mic.dart';
import '../../location/application/location_controller.dart';
import '../data/user_profile_repository.dart';

/// Opens the ONE profile editor (mini boxes, one open at a time). [section] opens that box first.
Future<bool?> askodoxOpenProfileEditor(BuildContext context, WidgetRef ref, AskodoxUserProfile profile,
    {required bool telugu, String? section}) {
  final place = ref.read(locationControllerProvider).displayLocation;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: AskodoxProfileEditor(profile: profile, telugu: telugu, currentPlace: place, initialSection: section),
    ),
  );
}

/// Required details per role (mirror of the backend ROLE_REQUIRED for these roles).
const _roleRequired = <String, List<String>>{
  'seller': ['business_type', 'working_hours'],
  'service_provider': ['services', 'service_area_km', 'availability'],
  'job_seeker': ['skills', 'availability'],
  'delivery_partner': ['service_types', 'operating_area', 'vehicle_type'],
};

/// Fields a guide walkthrough points at -> the box that holds them (opened for the guide).
const _guideTargets = <String, String>{
  'askodoxEditName': 'personal',
  'askodoxEditEmail': 'personal',
  'askodoxEditAddress': 'addresses',
  'askodoxEditShop': 'business',
};

class _Phone {
  _Phone(this.kind, String number, {this.from = '', this.to = '', this.sameAsPersonal = false, this.locked = false})
      : number = TextEditingController(text: number);
  String kind;
  final TextEditingController number;
  String from;
  String to;
  bool sameAsPersonal;

  /// The verified sign-in number: shown, hours editable, never changed here.
  final bool locked;
}

class _Address {
  _Address(this.kind, String text) : text = TextEditingController(text: text);
  String kind;
  final TextEditingController text;
}

/// Profile editor: a grid of mini boxes (each shows done / what is missing); tapping one opens it.
/// Numbers and addresses are lists you can add to, change and delete. Roles are chosen ONCE here and
/// each held role adds its own box. The verified number and known place are filled in for you; the
/// "say or paste" box puts e-mails, links, numbers, GST and hours into the right boxes.
class AskodoxProfileEditor extends ConsumerStatefulWidget {
  const AskodoxProfileEditor(
      {super.key, required this.profile, required this.telugu, this.currentPlace, this.initialSection});

  final AskodoxUserProfile profile;
  final bool telugu;
  final String? currentPlace;
  final String? initialSection;

  @override
  ConsumerState<AskodoxProfileEditor> createState() => _AskodoxProfileEditorState();
}

class _AskodoxProfileEditorState extends ConsumerState<AskodoxProfileEditor> {
  AskodoxUserProfile get p => widget.profile;
  late final _name = TextEditingController(text: p.name ?? '');
  late final _lastName = TextEditingController(text: p.lastName ?? '');
  late final _email = TextEditingController(text: p.email ?? '');
  late final _shop = TextEditingController(text: p.businessName ?? '');
  late final _category = TextEditingController(text: p.businessCategory ?? '');
  late final _subcategory = TextEditingController(text: p.businessSubcategory ?? '');
  late final _gstin = TextEditingController(text: p.gstin ?? '');
  late final _businessEmail = TextEditingController(text: p.businessEmail ?? '');
  final _paste = TextEditingController();
  late final Map<String, TextEditingController> _links = {
    for (final kind in const ['website', 'facebook', 'youtube', 'instagram', 'whatsapp', 'other'])
      kind: TextEditingController(text: p.links.where((l) => l['kind'] == kind).map((l) => l['url']).firstOrNull ?? ''),
  };
  late final List<_Phone> _phones = _initialPhones();
  late final List<_Address> _addresses = _initialAddresses();
  late final Map<String, Map<String, TextEditingController>> _roleFields = {};
  late String? _open = widget.initialSection;
  final _keys = <String, GlobalKey>{};
  bool _saving = false;
  String? _error;
  String? _notice;

  String _t(String en, String te) => widget.telugu ? te : en;

  String get _mobileDigits {
    final d = (p.mobile ?? '').replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  List<_Phone> _initialPhones() {
    final saved = p.phones;
    final personal = saved.where((x) => x['kind'] == 'personal').firstOrNull;
    return [
      if (_mobileDigits.isNotEmpty)
        _Phone('personal', _mobileDigits,
            from: '${personal?['from'] ?? ''}', to: '${personal?['to'] ?? ''}', locked: true),
      for (final x in saved)
        if (x['kind'] != 'personal')
          _Phone('${x['kind'] ?? 'other'}', '${x['number'] ?? ''}',
              from: '${x['from'] ?? ''}', to: '${x['to'] ?? ''}', sameAsPersonal: x['same_as_personal'] == true),
    ];
  }

  List<_Address> _initialAddresses() {
    final out = [for (final a in p.addresses) _Address('${a['kind'] ?? 'other'}', '${a['text'] ?? ''}')];
    // Pre-fill: no home address yet -> the place the phone already knows.
    if (!out.any((a) => a.kind == 'home') && (widget.currentPlace ?? '').trim().isNotEmpty) {
      out.insert(0, _Address('home', widget.currentPlace!.trim()));
    }
    if (out.isEmpty) out.add(_Address('home', ''));
    return out;
  }

  Map<String, TextEditingController> _fieldsFor(String role) => _roleFields.putIfAbsent(role, () => {
        for (final f in askodoxRoleProfileFields[role] ?? const <String>[])
          f: TextEditingController(text: _text(p.roleDetails[role]?[f])),
      });

  static String _text(Object? v) => v is List ? v.join(', ') : (v == null ? '' : '$v');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_open == 'roles') {
        // Asked for the roles: show the role chips (and open the first role box that needs something).
        _open = _sections().where((s) => !s.done && (s.id.startsWith('role-') || s.id == 'business')).map((s) => s.id).firstOrNull;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _keys['roles']?.currentContext;
          if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx);
        });
        return;
      }
      // Open the first box that still needs something (unless the caller asked for one).
      _open ??= _sections().where((s) => !s.done).map((s) => s.id).firstOrNull;
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _lastName, _email, _shop, _category, _subcategory, _gstin, _businessEmail, _paste,
      ..._links.values]) {
      c.dispose();
    }
    for (final ph in _phones) {
      ph.number.dispose();
    }
    for (final a in _addresses) {
      a.text.dispose();
    }
    for (final m in _roleFields.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  bool get _sells {
    final owned = ref.read(askodoxRoleProvider).owned;
    return owned.contains(AskodoxUserRole.seller) || owned.contains(AskodoxUserRole.serviceProvider) || p.businessName != null;
  }

  List<String> get _heldRoleKeys => [
        for (final r in askodoxProfileRoles)
          if (ref.read(askodoxRoleProvider).owned.contains(r) && askodoxRoleProfileFields.containsKey(askodoxRoleKey(r.name)))
            askodoxRoleKey(r.name),
      ];

  // ------------------------------------------------------------ boxes and their state
  List<({String id, IconData icon, String title, String status, bool done})> _sections() {
    final missing = <String, int>{};
    final personalDone = _name.text.trim().isNotEmpty;
    final phonesDone = _phones.any((x) => x.from.isNotEmpty) || _phones.length > 1;
    final homeDone = _addresses.any((a) => a.kind == 'home' && a.text.text.trim().isNotEmpty);
    final linksCount = _links.values.where((c) => c.text.trim().isNotEmpty).length;
    final out = <({String id, IconData icon, String title, String status, bool done})>[
      (
        id: 'personal',
        icon: Icons.person_outline_rounded,
        title: _t('Name & e-mail', 'పేరు & ఈమెయిల్'),
        status: personalDone ? _t('✓ Done', '✓ పూర్తి') : _t('Name needed', 'పేరు కావాలి'),
        done: personalDone
      ),
      (
        id: 'phones',
        icon: Icons.call_outlined,
        title: _t('Numbers & hours', 'నంబర్లు & టైమింగ్స్'),
        status: phonesDone
            ? _t('✓ ${_phones.length} number(s)', '✓ ${_phones.length} నంబర్(లు)')
            : _t('Add reachable hours', 'అందుబాటు సమయం ఇవ్వండి'),
        done: phonesDone
      ),
      (
        id: 'addresses',
        icon: Icons.place_outlined,
        title: _t('Addresses', 'చిరునామాలు'),
        status: homeDone ? _t('✓ ${_addresses.where((a) => a.text.text.trim().isNotEmpty).length} saved', '✓ ${_addresses.where((a) => a.text.text.trim().isNotEmpty).length} ఉన్నాయి') : _t('Home address needed', 'ఇంటి చిరునామా కావాలి'),
        done: homeDone
      ),
      (
        id: 'links',
        icon: Icons.link_rounded,
        title: _t('Website & social pages', 'వెబ్‌సైట్ & సోషల్ పేజీలు'),
        status: linksCount > 0 ? _t('✓ $linksCount added', '✓ $linksCount ఉన్నాయి') : _t('Optional', 'ఐచ్ఛికం'),
        done: true
      ),
    ];
    if (_sells) {
      final need = [if (_shop.text.trim().isEmpty) 'shop', if (_category.text.trim().isEmpty) 'category'].length;
      out.add((
        id: 'business',
        icon: Icons.storefront_outlined,
        title: _t('Shop / business', 'షాప్ / వ్యాపారం'),
        status: need == 0 ? _t('✓ Done', '✓ పూర్తి') : _t('$need needed', '$need కావాలి'),
        done: need == 0
      ));
    }
    for (final role in _heldRoleKeys) {
      final fields = _fieldsFor(role);
      final req = _roleRequired[role] ?? const <String>[];
      missing[role] = req.where((f) => (fields[f]?.text.trim() ?? '').isEmpty).length;
      out.add((
        id: 'role-$role',
        icon: switch (role) {
          'seller' => Icons.sell_outlined,
          'service_provider' => Icons.handyman_outlined,
          'job_seeker' => Icons.work_outline_rounded,
          _ => Icons.delivery_dining_outlined,
        },
        title: askodoxUserRoleLabel(
            askodoxProfileRoles.firstWhere((r) => askodoxRoleKey(r.name) == role), telugu: widget.telugu),
        status: missing[role] == 0 ? _t('✓ Done', '✓ పూర్తి') : _t('${missing[role]} needed', '${missing[role]} కావాలి'),
        done: missing[role] == 0
      ));
    }
    return out;
  }

  void _toggle(String id) {
    setState(() => _open = _open == id ? null : id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
    });
  }

  // ------------------------------------------------------------ say or paste -> the right boxes
  void _fillFrom(String text) {
    final filled = <String>[];
    final emails = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]{2,}').allMatches(text).map((m) => m[0]!).toList();
    for (final e in emails) {
      if (_email.text.trim().isEmpty) {
        _email.text = e;
        filled.add(_t('e-mail', 'ఈమెయిల్'));
      } else if (_sells && _businessEmail.text.trim().isEmpty && e != _email.text.trim()) {
        _businessEmail.text = e;
        filled.add(_t('business e-mail', 'వ్యాపార ఈమెయిల్'));
      }
    }
    for (final m in RegExp(r'(https?://\S+|www\.\S+|wa\.me/\S+)').allMatches(text)) {
      var url = m[0]!.replaceAll(RegExp(r'[),.]+$'), '');
      if (!url.startsWith('http')) url = 'https://$url';
      final host = url.toLowerCase();
      final kind = host.contains('facebook.') || host.contains('fb.')
          ? 'facebook'
          : host.contains('youtube.') || host.contains('youtu.be')
              ? 'youtube'
              : host.contains('instagram.')
                  ? 'instagram'
                  : host.contains('wa.me') || host.contains('whatsapp')
                      ? 'whatsapp'
                      : 'website';
      if (_links[kind]!.text.trim().isEmpty) {
        _links[kind]!.text = url;
        filled.add(kind);
      }
    }
    final gst = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b').firstMatch(text.toUpperCase());
    if (gst != null && _sells && _gstin.text.trim().isEmpty) {
      _gstin.text = gst[0]!;
      filled.add('GST');
    }
    for (final m in RegExp(r'(?<!\d)(?:\+?91[\s-]?)?([6-9]\d{4}[\s-]?\d{5})(?!\d)').allMatches(text)) {
      final digits = m[1]!.replaceAll(RegExp(r'\D'), '');
      if (digits == _mobileDigits || _phones.any((x) => x.number.text.replaceAll(RegExp(r'\D'), '') == digits)) continue;
      _phones.add(_Phone(_sells ? 'business' : 'other', digits));
      filled.add(_t('number', 'నంబర్'));
    }
    final hours = _hoursIn(text);
    if (hours != null) {
      final target = _phones.where((x) => x.kind == 'business').firstOrNull ?? _phones.firstOrNull;
      if (target != null) {
        target.from = hours.$1;
        target.to = hours.$2;
        filled.add(_t('hours', 'టైమింగ్స్'));
      }
    }
    setState(() => _notice = filled.isEmpty
        ? _t('Nothing new found — type it in the boxes below.', 'కొత్తగా ఏమీ దొరకలేదు — కింద బాక్సుల్లో రాయండి.')
        : _t('Filled: ${filled.join(', ')} — check and save.', 'నింపాం: ${filled.join(', ')} — సరిచూసి సేవ్ చేయండి.'));
  }

  /// "8 to 10", "8 AM - 10 PM", "ఉదయం 8 నుండి రాత్రి 10" -> ("08:00", "22:00").
  static (String, String)? _hoursIn(String text) {
    final m = RegExp(r'(ఉదయం|morning|సాయంత్రం|రాత్రి|evening|night)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*'
            r'(?:to|-|–|నుండి|నుంచి|till|until)\s*(ఉదయం|morning|సాయంత్రం|రాత్రి|evening|night)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?',
            caseSensitive: false)
        .firstMatch(text);
    if (m == null) return null;
    int hour(String? word, String h, String? suffix, {required bool end}) {
      var v = int.parse(h);
      final s = (suffix ?? '').toLowerCase();
      final w = (word ?? '').toLowerCase();
      final pm = s.startsWith('p') || ['సాయంత్రం', 'రాత్రి', 'evening', 'night'].contains(w);
      final am = s.startsWith('a') || ['ఉదయం', 'morning'].contains(w);
      if (pm && v < 12) v += 12;
      if (!pm && !am && end && v <= 11) v += 12; // "8 to 10" at a shop = 8 in the morning to 10 at night
      return v.clamp(0, 23);
    }

    final start = hour(m[1], m[2]!, m[4], end: false);
    final end = hour(m[5], m[6]!, m[8], end: true);
    String fmt(int h, String? mm) => '${h.toString().padLeft(2, '0')}:${(mm ?? '00').padLeft(2, '0')}';
    return (fmt(start, m[3]), fmt(end, m[7]));
  }

  // ------------------------------------------------------------ save
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$');
    final email = _email.text.trim();
    final businessEmail = _businessEmail.text.trim();
    String? problem;
    if (email.isNotEmpty && !emailRe.hasMatch(email)) problem = _t('Enter a valid e-mail address.', 'సరైన ఈ-మెయిల్ ఇవ్వండి.');
    if (businessEmail.isNotEmpty && !emailRe.hasMatch(businessEmail)) {
      problem = _t('Enter a valid business e-mail.', 'సరైన వ్యాపార ఈ-మెయిల్ ఇవ్వండి.');
    }
    for (final ph in _phones) {
      final d = ph.number.text.replaceAll(RegExp(r'\D'), '');
      if (!ph.locked && !ph.sameAsPersonal && d.isNotEmpty && (d.length != 10 || !'6789'.contains(d[0]))) {
        problem = _t('A phone number must be 10 digits.', 'ఫోన్ నంబర్ 10 అంకెలు ఉండాలి.');
      }
    }
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    final roles = [for (final r in ref.read(askodoxRoleProvider).owned) r.name]..sort();
    final ok = await ref.read(askodoxUserProfileProvider.notifier).save({
      'name': _name.text.trim(),
      'last_name': _lastName.text.trim(),
      'email': email,
      'links': [
        for (final e in _links.entries)
          if (e.value.text.trim().isNotEmpty) {'kind': e.key, 'url': e.value.text.trim()},
      ],
      'phones': [
        for (final ph in _phones)
          if (ph.locked || ph.sameAsPersonal || ph.number.text.trim().isNotEmpty)
            {
              'kind': ph.kind,
              'number': ph.sameAsPersonal ? '' : ph.number.text.replaceAll(RegExp(r'\D'), ''),
              'same_as_personal': ph.sameAsPersonal,
              'from': ph.from,
              'to': ph.to,
            },
      ],
      'addresses': [
        for (final a in _addresses)
          if (a.text.text.trim().isNotEmpty) {'kind': a.kind, 'text': a.text.text.trim()},
      ],
      'roles': roles,
      if (_heldRoleKeys.isNotEmpty)
        'role_details': {
          for (final role in _heldRoleKeys) role: {for (final f in _fieldsFor(role).entries) f.key: f.value.text.trim()},
        },
      if (_sells) ...{
        'business_name': _shop.text.trim(),
        'business_category': _category.text.trim(),
        'business_subcategory': _subcategory.text.trim(),
        'business_email': businessEmail,
        if (_gstin.text.trim().isNotEmpty) 'gstin': _gstin.text.trim(),
      },
    });
    if (mounted) Navigator.pop(context, ok);
  }

  // ------------------------------------------------------------ pieces
  Widget _timeButton(String label, String value, ValueChanged<String> set, Key key) => OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.schedule_rounded, size: 16),
        label: Text(value.isEmpty ? label : value),
        onPressed: () async {
          final parts = value.split(':');
          final picked = await showTimePicker(
            context: context,
            initialTime: value.isEmpty
                ? const TimeOfDay(hour: 9, minute: 0)
                : TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.last) ?? 0),
          );
          if (picked != null) {
            setState(() => set('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
          }
        },
      );

  String _phoneKindLabel(String kind) => switch (kind) {
        'personal' => _t('Personal number', 'వ్యక్తిగత నంబర్'),
        'business' => _t('Business number', 'వ్యాపార నంబర్'),
        'whatsapp' => 'WhatsApp',
        'home' => _t('Home number', 'ఇంటి నంబర్'),
        _ => _t('Other number', 'ఇతర నంబర్'),
      };

  String _addressKindLabel(String kind) => switch (kind) {
        'home' => _t('Home', 'ఇల్లు'),
        'business' => _t('Shop / business', 'షాప్ / వ్యాపారం'),
        _ => _t('Other', 'ఇతర'),
      };

  Widget _item({required Key key, required List<Widget> children}) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE4E9F2)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _phonesBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, ph) in _phones.indexed)
        _item(key: ValueKey('askodoxEditPhone-$i'), children: [
          Row(children: [
            Icon(ph.kind == 'whatsapp' ? Icons.chat_outlined : Icons.call_outlined, size: 18, color: const Color(0xFF0E7A45)),
            const SizedBox(width: 6),
            Expanded(
              child: ph.locked
                  ? Text('${_phoneKindLabel(ph.kind)} · ${_t('verified by OTP', 'OTP తో ధృవీకరించబడింది')}',
                      style: const TextStyle(fontWeight: FontWeight.w800))
                  : DropdownButton<String>(
                      key: ValueKey('askodoxEditPhoneKind-$i'),
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      value: ph.kind,
                      items: [
                        for (final k in const ['business', 'whatsapp', 'home', 'other'])
                          DropdownMenuItem(value: k, child: Text(_phoneKindLabel(k))),
                      ],
                      onChanged: (k) => setState(() => ph.kind = k ?? ph.kind),
                    ),
            ),
            if (!ph.locked)
              IconButton(
                key: ValueKey('askodoxEditPhoneDelete-$i'),
                tooltip: _t('Delete', 'తొలగించు'),
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)),
                onPressed: () => setState(() => _phones.removeAt(i)),
              ),
          ]),
          if (ph.locked)
            Text('+91 ${ph.number.text}', style: const TextStyle(fontSize: 15))
          else if (ph.kind == 'whatsapp' && _mobileDigits.isNotEmpty)
            SwitchListTile(
              key: ValueKey('askodoxEditPhoneSame-$i'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: ph.sameAsPersonal,
              onChanged: (v) => setState(() => ph.sameAsPersonal = v),
              title: Text(_t('Same as my personal number', 'నా వ్యక్తిగత నంబర్‌నే వాడండి')),
            ),
          if (!ph.locked && !ph.sameAsPersonal)
            TextField(
              key: ValueKey('askodoxEditPhoneNumber-$i'),
              controller: ph.number,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  isDense: true, labelText: _t('Number', 'నంబర్'), hintText: _t('e.g. 98480 22338', 'ఉదా: 98480 22338')),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_t('Reachable', 'అందుబాటు'), style: const TextStyle(fontSize: 12.5, color: Color(0xFF475467))),
            _timeButton(_t('from', 'నుండి'), ph.from, (v) => ph.from = v, ValueKey('askodoxEditPhoneFrom-$i')),
            _timeButton(_t('to', 'వరకు'), ph.to, (v) => ph.to = v, ValueKey('askodoxEditPhoneTo-$i')),
          ]),
        ]),
      OutlinedButton.icon(
          key: const Key('askodoxEditPhoneAdd'),
          icon: const Icon(Icons.add_rounded),
          label: Text(_t('Add a number', 'నంబర్ జోడించు')),
          onPressed: _phones.length >= 7
              ? null
              : () => setState(() => _phones.add(_Phone(
                  _phones.any((x) => x.kind == 'business') || !_sells ? 'whatsapp' : 'business', '',
                  sameAsPersonal: _sells && _phones.any((x) => x.kind == 'business')))),
        ),
    ]);
  }

  Widget _addressesBody() {
    // The first home / shop address keeps the keys guides and tests point at.
    final keys = <Key>[];
    var homeKeyUsed = false;
    var shopKeyUsed = false;
    for (final (i, a) in _addresses.indexed) {
      if (a.kind == 'home' && !homeKeyUsed) {
        homeKeyUsed = true;
        keys.add(const Key('askodoxEditAddress'));
      } else if (a.kind == 'business' && !shopKeyUsed) {
        shopKeyUsed = true;
        keys.add(const Key('askodoxEditShopAddress'));
      } else {
        keys.add(ValueKey('askodoxEditAddressText-$i'));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, a) in _addresses.indexed)
        _item(key: ValueKey('askodoxEditAddressItem-$i'), children: [
          Row(children: [
            const Icon(Icons.place_outlined, size: 18, color: Color(0xFF9A3D00)),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButton<String>(
                key: ValueKey('askodoxEditAddressKind-$i'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                value: a.kind,
                items: [
                  for (final k in const ['home', 'business', 'other']) DropdownMenuItem(value: k, child: Text(_addressKindLabel(k))),
                ],
                onChanged: (k) => setState(() => a.kind = k ?? a.kind),
              ),
            ),
            IconButton(
              key: ValueKey('askodoxEditAddressDelete-$i'),
              tooltip: _t('Delete', 'తొలగించు'),
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)),
              onPressed: () => setState(() => _addresses.removeAt(i)),
            ),
          ]),
          AskodoxGuidedField(
              key: ObjectKey(a),
              fieldKey: keys[i],
              controller: a.text,
              label: _t('Address (town, area)', 'చిరునామా (ఊరు, ప్రాంతం)'),
              guide: a.kind == 'business' ? AskodoxFieldGuides.shopAddress : AskodoxFieldGuides.town),
        ]),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          key: const Key('askodoxEditAddressAdd'),
          icon: const Icon(Icons.add_rounded),
          label: Text(_t('Add an address', 'చిరునామా జోడించు')),
          onPressed: _addresses.length >= 7
              ? null
              : () => setState(() => _addresses.add(_Address(
                  _addresses.any((a) => a.kind == 'business') || !_sells ? 'other' : 'business', ''))),
        ),
        if ((widget.currentPlace ?? '').trim().isNotEmpty)
          TextButton.icon(
            key: const Key('askodoxEditAddressHere'),
            icon: const Icon(Icons.my_location_rounded),
            label: Text(_t('Use where I am now', 'ఇప్పుడున్న చోటు వాడు')),
            onPressed: () => setState(() {
              final empty = _addresses.where((a) => a.text.text.trim().isEmpty).firstOrNull;
              if (empty != null) {
                empty.text.text = widget.currentPlace!.trim();
              } else {
                _addresses.add(_Address('other', widget.currentPlace!.trim()));
              }
            }),
          ),
      ]),
    ]);
  }

  Widget _linksBody() => Column(children: [
        for (final e in _links.entries)
          TextField(
            key: ValueKey('askodoxEditLink-${e.key}'),
            controller: e.value,
            decoration: InputDecoration(
              isDense: true,
              labelText: switch (e.key) {
                'website' => _t('Website', 'వెబ్‌సైట్'),
                'facebook' => 'Facebook',
                'youtube' => 'YouTube',
                'instagram' => 'Instagram',
                'whatsapp' => 'WhatsApp',
                _ => _t('Any other page', 'ఇంకేదైనా పేజీ'),
              },
              hintText: switch (e.key) {
                'whatsapp' => 'https://wa.me/919848022338',
                'facebook' => 'https://facebook.com/yourshop',
                'youtube' => 'https://youtube.com/@yourshop',
                'instagram' => 'https://instagram.com/yourshop',
                _ => 'https://…',
              },
            ),
          ),
      ]);

  Widget _businessBody() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AskodoxGuidedField(fieldKey: const Key('askodoxEditShop'), controller: _shop,
            label: _t('Business / shop name', 'వ్యాపారం / షాప్ పేరు'), guide: AskodoxFieldGuides.shopName),
        AskodoxGuidedField(fieldKey: const Key('askodoxEditCategory'), controller: _category,
            label: _t('Category / service', 'విభాగం / సర్వీస్'), guide: AskodoxFieldGuides.category),
        TextField(
          key: const Key('askodoxEditSubcategory'),
          controller: _subcategory,
          decoration: InputDecoration(
              labelText: _t('Sub-category (optional)', 'ఉప-విభాగం (ఐచ్ఛికం)'),
              hintText: _t('e.g. pulses & oils', 'ఉదా: పప్పులు & నూనెలు')),
        ),
        AskodoxGuidedField(fieldKey: const Key('askodoxEditGstin'), controller: _gstin,
            label: _t('GSTIN (if you have one)', 'GSTIN (ఉంటే)'), guide: AskodoxFieldGuides.gstin),
        TextField(
          key: const Key('askodoxEditBusinessEmail'),
          controller: _businessEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
              labelText: _t('Business e-mail (optional)', 'వ్యాపార ఈమెయిల్ (ఐచ్ఛికం)'), hintText: 'shop@gmail.com'),
        ),
        const SizedBox(height: 6),
        Text(
            _t('The shop number, address and hours come from the Numbers and Addresses boxes — no need to type them again.',
                'షాప్ నంబర్, చిరునామా, టైమింగ్స్ "నంబర్లు", "చిరునామాలు" బాక్సుల నుండే — మళ్ళీ రాయక్కర్లేదు.'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
      ]);

  Widget _roleBody(String role) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(askodoxFieldLabel(role), key: ValueKey('askodoxEditRole-$role'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF475467))),
        for (final f in _fieldsFor(role).entries)
          TextField(
            key: ValueKey('askodoxEditRole-$role-${f.key}'),
            controller: f.value,
            decoration: InputDecoration(
              labelText: '${askodoxFieldLabel(f.key)}${(_roleRequired[role] ?? const []).contains(f.key) ? ' *' : ''}',
            ),
          ),
      ]);

  Widget _rolesCard() {
    final roles = ref.watch(askodoxRoleProvider);
    final held = [for (final r in AskodoxUserRole.values) if (roles.owned.contains(r)) r];
    return Container(
      key: _keys.putIfAbsent('roles', GlobalKey.new),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_t('What do I do? (all roles, one place)', 'నేను ఏం చేస్తాను? (అన్ని పాత్రలు ఒక్కచోటే)'),
            key: const Key('askodoxEditRoles'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final role in {...askodoxProfileRoles, roles.active})
            FilterChip(
              key: ValueKey('profileRole-${role.name}'),
              visualDensity: VisualDensity.compact,
              selected: roles.owned.contains(role),
              side: role == roles.active ? const BorderSide(color: Color(0xFF1769FF), width: 2) : null,
              avatar: role == roles.active ? const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF1769FF)) : null,
              label: Text(role == roles.active
                  ? '${askodoxUserRoleLabel(role, telugu: widget.telugu)} · ${_t('Active now', 'ఇప్పుడు యాక్టివ్')}'
                  : askodoxUserRoleLabel(role, telugu: widget.telugu)),
              onSelected: (value) {
                setState(() => ref.read(askodoxRoleProvider.notifier).toggleOwned(role, value));
                // Held roles are part of the one stored profile: saved at once.
                if (ref.read(authSessionProvider).user != null) {
                  final held = ref.read(askodoxRoleProvider).owned.map((r) => r.name).toList()..sort();
                  ref.read(askodoxUserProfileProvider.notifier).save({'roles': held});
                }
              },
            ),
        ]),
        if (held.length >= 2)
          Row(children: [
            Text(_t('Acting as', 'ఇప్పుడు ఈ పాత్రలో'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<AskodoxUserRole>(
                key: const Key('askodoxActiveRolePicker'),
                isExpanded: true,
                value: held.contains(roles.active) ? roles.active : held.first,
                items: [for (final r in held) DropdownMenuItem(value: r, child: Text(askodoxUserRoleLabel(r, telugu: widget.telugu)))],
                onChanged: (role) {
                  if (role == null || role == roles.active) return;
                  final before = roles.active;
                  ref.read(askodoxRoleProvider.notifier).setActive(role);
                  if (ref.read(authSessionProvider).user != null) {
                    ref.read(askodoxUserProfileProvider.notifier).save({'active_role': role.name});
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    key: const Key('askodoxActiveRoleChanged'),
                    content: Text(askodoxRoleChangedMessage(before, role, telugu: widget.telugu)),
                  ));
                },
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _section(({String id, IconData icon, String title, String status, bool done}) s, Widget body) {
    final open = _open == s.id;
    return Container(
      key: _keys.putIfAbsent(s.id, GlobalKey.new),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? const Color(0xFF1769FF) : const Color(0xFFE4E9F2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('askodoxEditSectionHead-${s.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _toggle(s.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(s.icon, color: const Color(0xFF1769FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(s.status,
                      style: TextStyle(
                          fontSize: 12, color: s.done ? const Color(0xFF0E7A45) : const Color(0xFFB54708), fontWeight: FontWeight.w700)),
                ]),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: body),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A walkthrough pointing at a field opens the box that holds it.
    final guide = ref.watch(askodoxGuideProvider);
    final target = guide == null || guide.done ? null : _guideTargets[guide.step.target];
    if (target != null && target != _open && (target != 'business' || _sells)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _open = target);
      });
    }
    ref.watch(askodoxRoleProvider); // held roles add / remove boxes
    final sections = _sections();
    final done = sections.where((s) => s.done).length;
    final bodies = <String, Widget Function()>{
      'personal': () => Column(children: [
            AskodoxGuidedField(fieldKey: const Key('askodoxEditName'), controller: _name,
                label: _t('First name *', 'పేరు *'), guide: AskodoxFieldGuides.name, onChanged: (_) => setState(() {})),
            TextField(
              key: const Key('askodoxEditLastName'),
              controller: _lastName,
              decoration: InputDecoration(labelText: _t('Surname', 'ఇంటిపేరు'), hintText: _t('e.g. Rao', 'ఉదా: రావు')),
            ),
            AskodoxGuidedField(fieldKey: const Key('askodoxEditEmail'), controller: _email,
                keyboardType: TextInputType.emailAddress,
                label: _t('E-mail (optional)', 'ఈ-మెయిల్ (ఐచ్ఛికం)'), guide: AskodoxFieldGuides.email),
          ]),
      'phones': _phonesBody,
      'addresses': _addressesBody,
      'links': _linksBody,
      'business': _businessBody,
      for (final role in _heldRoleKeys) 'role-$role': () => _roleBody(role),
    };
    final mine = sections.where((s) => !s.id.startsWith('role-') && s.id != 'business').toList();
    final roleBoxes = sections.where((s) => s.id.startsWith('role-') || s.id == 'business').toList();

    Widget mini(({String id, IconData icon, String title, String status, bool done}) s) => Material(
          color: _open == s.id ? const Color(0xFFEAF1FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('askodoxEditMini-${s.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => _toggle(s.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Icon(s.icon, size: 20, color: const Color(0xFF1769FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text(s.status, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: s.done ? const Color(0xFF0E7A45) : const Color(0xFFB54708))),
                  ]),
                ),
              ]),
            ),
          ),
        );

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_t('Edit profile', 'ప్రొఫైల్ మార్చండి'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_t('$done of ${sections.length} boxes done', '${sections.length} లో $done బాక్సులు పూర్తి'),
                key: const Key('askodoxEditProgress'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: sections.isEmpty ? 0 : done / sections.length, minHeight: 6,
                borderRadius: BorderRadius.circular(3)),
            if (_mobileDigits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF0E7A45)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_t('Your number is verified by OTP — filled in for you.', 'మీ నంబర్ OTP తో ధృవీకరించబడింది — ఆటోగా నింపాం.'),
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF0E7A45))),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            // Say or paste: e-mails, links, numbers, GST and hours go into the right boxes.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD0D9EA))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('askodoxEditPaste'),
                    controller: _paste,
                    onSubmitted: _fillFrom,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _t('Say or paste: e-mail, website, number, GST, hours',
                          'చెప్పండి / పేస్ట్: ఈమెయిల్, వెబ్‌సైట్, నంబర్, GST, టైమింగ్స్'),
                    ),
                  ),
                ),
                AskodoxQuestionMic(lang: widget.telugu ? 'te' : 'en', onText: (text) {
                  _paste.text = text;
                  _fillFrom(text);
                }),
                IconButton(
                  key: const Key('askodoxEditPasteGo'),
                  tooltip: _t('Fill the boxes', 'బాక్సులు నింపు'),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  onPressed: () => _fillFrom(_paste.text),
                ),
              ]),
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_notice!, key: const Key('askodoxEditNotice'), style: const TextStyle(color: Color(0xFF0E7A45))),
              ),
            const SizedBox(height: 12),
            Text(_t('My details', 'నా వివరాలు'), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF475467))),
            const SizedBox(height: 6),
            GridView.count(
              key: const Key('askodoxEditGrid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
              children: [for (final s in mine) mini(s)],
            ),
            for (final s in mine) _section(s, bodies[s.id]!()),
            const SizedBox(height: 16),
            _rolesCard(),
            if (roleBoxes.isNotEmpty) ...[
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [for (final s in roleBoxes) mini(s)],
              ),
              for (final s in roleBoxes) _section(s, bodies[s.id]!()),
            ],
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!, key: const Key('askodoxEditError'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
              ),
            FilledButton(
              key: const Key('askodoxEditSave'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _saving ? null : _save,
              child: Text(_t('Save', 'సేవ్ చేయండి'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ]),
        ),
      ),
    ]);
  }
}
