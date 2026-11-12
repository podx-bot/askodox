import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Payment sound alerts without the POS (Phase 1, owner 2026-11-10): the owner names the shop,
/// adds staff by mobile number + role (manager / cashier / attendant ...), and chooses which roles
/// hear the payment sound; each person then switches the sound on on their own phone.
/// Everything is the existing POS payment-alert system (`pos_payment_alerts.py`): this screen only
/// gives it a Phase 1 door. ASKODOX never holds the money.
const askodoxPaymentAlertStaffRoles = ['manager', 'cashier', 'attendant'];

String askodoxStaffRoleLabel(String role, bool te) => switch (role) {
      'owner' => te ? 'యజమాని' : 'Owner',
      'manager' => te ? 'మేనేజర్' : 'Manager',
      'cashier' => te ? 'క్యాషియర్' : 'Cashier',
      'attendant' => te ? 'అటెండెంట్' : 'Attendant',
      'accountant' => te ? 'అకౌంటెంట్' : 'Accountant',
      'waiter' => te ? 'వెయిటర్' : 'Waiter',
      'kitchen' => te ? 'వంటగది' : 'Kitchen',
      _ => role,
    };

class AskodoxMyPaymentAlertsScreen extends ConsumerStatefulWidget {
  const AskodoxMyPaymentAlertsScreen({super.key});

  @override
  ConsumerState<AskodoxMyPaymentAlertsScreen> createState() => _AskodoxMyPaymentAlertsScreenState();
}

class _AskodoxMyPaymentAlertsScreenState extends ConsumerState<AskodoxMyPaymentAlertsScreen> {
  List<AskodoxJson>? _shops;
  final _members = <String, List<AskodoxJson>>{};
  Map<String, String> _states = const {};
  AskodoxPosException? _error;
  String? _message;
  bool _busy = false;

  final _name = TextEditingController();
  String? _state;
  final _phone = TextEditingController();
  final _label = TextEditingController();
  String _role = 'cashier';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final shops = await repo.businesses();
      final members = <String, List<AskodoxJson>>{};
      for (final s in shops) {
        if ('${s['role']}' == 'owner') {
          try {
            members['${s['id']}'] = await repo.members('${s['id']}');
          } on AskodoxPosException {
            // The list is optional; the shop row still shows.
          }
        }
      }
      var states = _states;
      if (shops.isEmpty && states.isEmpty) {
        try {
          final meta = await repo.meta();
          states = {for (final e in askodoxPosMap(meta['states']).entries) e.key: '${e.value}'};
        } on AskodoxPosException {
          // Without the list the form asks to try again.
        }
      }
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _members
          ..clear()
          ..addAll(members);
        _states = states;
        _error = null;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function(AskodoxPosRepository repo) action, {String? done}) async {
    final te = askodoxPosTe(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(ref.read(askodoxPosRepositoryProvider));
      await _load();
      if (mounted && done != null) setState(() => _message = done);
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run((repo) async {
        await repo.createBusiness({
          'name': _name.text.trim(),
          'template': 'general',
          'registration_type': 'unregistered',
          if (_state != null) 'state_code': _state,
        });
        _name.clear();
      });

  Future<void> _addStaff(String shopId, bool te) => _run((repo) async {
        await repo.setMember(shopId, _phone.text.trim(), _role, label: _label.text);
        _phone.clear();
        _label.clear();
      }, done: te ? 'జోడించాం. వాళ్ళు తమ ఫోన్‌లో ASKODOX తెరిచి ఇదే పేజీలో సౌండ్ ఆన్ చేసుకోవాలి.' : 'Added. They open ASKODOX on their phone and switch the sound on from this same page.');

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final shops = _shops;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'పేమెంట్ సౌండ్ అలర్ట్' : 'Payment sound alerts')),
      body: shops == null
          ? (_error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : ListView(key: const Key('askodoxMyPaymentAlerts'), padding: const EdgeInsets.all(12), children: [
              Text(
                  te
                      ? 'డబ్బు మీ అకౌంట్‌లో పడగానే ఫోన్ గట్టిగా చెబుతుంది. మీరు ఎంచుకున్న సిబ్బంది ఫోన్‌లలో కూడా వినిపిస్తుంది. ASKODOX డబ్బు పట్టుకోదు.'
                      : 'The phone speaks when money reaches your account. The staff you choose hear it on their phones too. ASKODOX never holds money.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_message!, key: const Key('askodoxMyPaymentAlertsMessage'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              if (shops.isEmpty) _setup(te),
              for (final shop in shops) _shop(shop, te),
            ]),
    );
  }

  Widget _setup(bool te) => Card(
        key: const Key('askodoxMyPaymentAlertsSetup'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'మీ షాప్ / వ్యాపారం పేరు' : 'Your shop / business name', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            TextField(
              key: const Key('askodoxMyPaymentAlertsName'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(hintText: te ? 'ఉదా. లక్ష్మి కిరాణా' : 'e.g. Lakshmi Kirana'),
              onChanged: (_) => setState(() {}),
            ),
            DropdownButtonFormField<String>(
              key: const Key('askodoxMyPaymentAlertsState'),
              isExpanded: true,
              initialValue: _state,
              decoration: InputDecoration(labelText: te ? 'రాష్ట్రం' : 'State'),
              items: [for (final e in _states.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _state = v),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('askodoxMyPaymentAlertsCreate'),
              onPressed: _busy || _name.text.trim().isEmpty || _state == null ? null : _create,
              child: Text(te ? 'మొదలుపెట్టు' : 'Start'),
            ),
          ]),
        ),
      );

  Widget _shop(AskodoxJson shop, bool te) {
    final id = '${shop['id']}';
    final owner = '${shop['role']}' == 'owner';
    final staff = (_members[id] ?? const <AskodoxJson>[]).where((m) => m['active'] == true && '${m['role']}' != 'owner').toList();
    return Card(
      key: ValueKey('askodoxMyPaymentAlertsShop-$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${shop['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          Text('${te ? 'మీ పాత్ర' : 'Your role'}: ${askodoxStaffRoleLabel('${shop['role']}', te)}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: ValueKey('askodoxMyPaymentAlertsOpen-$id'),
            onPressed: () => context.push('/me/payment-alerts/$id'),
            icon: const Icon(Icons.volume_up_rounded),
            label: Text(owner
                ? (te ? 'సౌండ్ ఆన్ / ఎవరికి వినిపించాలి' : 'Sound on / who hears it')
                : (te ? 'ఈ ఫోన్‌లో సౌండ్ ఆన్ చేయి' : 'Switch the sound on on this phone')),
          ),
          if (owner) ...[
            const Divider(height: 24),
            Text(te ? 'సిబ్బంది' : 'Staff', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (staff.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(te ? 'ఇంకా ఎవరినీ జోడించలేదు.' : 'Nobody added yet.', style: const TextStyle(fontSize: 12.5)),
              ),
            for (final m in staff)
              ListTile(
                key: ValueKey('askodoxMyPaymentAlertsStaff-$id-${m['phone_last4']}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: Text('${m['label'] ?? ''}'.isEmpty ? '••••••${m['phone_last4']}' : '${m['label']} · ••••••${m['phone_last4']}'),
                subtitle: Text(askodoxStaffRoleLabel('${m['role']}', te)),
              ),
            const SizedBox(height: 6),
            TextField(
              key: ValueKey('askodoxMyPaymentAlertsLabel-$id'),
              controller: _label,
              maxLength: 40,
              decoration: InputDecoration(
                  counterText: '',
                  labelText: te ? 'పేరు (మీకు నచ్చినది, ఉదా. భార్య / స్టాఫ్ 1)' : 'Name (any, e.g. Wife / Staff 1)',
                  helperText: te ? 'పేమెంట్ వచ్చినప్పుడు ఈ పేరు చెబుతుంది.' : 'This name is spoken with their payments.'),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: ValueKey('askodoxMyPaymentAlertsPhone-$id'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(counterText: '', labelText: te ? 'సిబ్బంది మొబైల్ నంబర్' : 'Staff mobile number'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('askodoxMyPaymentAlertsRole-$id'),
                  isExpanded: true,
                  initialValue: _role,
                  items: [
                    for (final r in askodoxPaymentAlertStaffRoles)
                      DropdownMenuItem(value: r, child: Text(askodoxStaffRoleLabel(r, te))),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: ValueKey('askodoxMyPaymentAlertsAdd-$id'),
              onPressed: _busy || _phone.text.trim().length != 10 ? null : () => _addStaff(id, te),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(te ? 'సిబ్బందిని జోడించు' : 'Add staff'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  te
                      ? 'తర్వాత పైన "ఎవరికి వినిపించాలి" లో ఆ పాత్రను టిక్ చేయండి (అటెండెంట్ ముందుగా ఆఫ్‌లో ఉంటుంది).'
                      : 'Then tick that role under "who hears it" above (attendant starts off).',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
            ),
          ],
        ]),
      ),
    );
  }
}
