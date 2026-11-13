import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Payment sound alerts without the POS (Phase 1, owner 2026-11-10): the owner names the shop;
/// staff, who hears it, voice and history all live on the shop's ONE alert page
/// (`/me/payment-alerts/:id`, redesign 2026-11-13). With exactly one shop this page opens that
/// page directly, so there is no second "sound on / who hears it" step.
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
  Map<String, String> _states = const {};
  bool _forwarded = false;
  AskodoxPosException? _error;
  String? _message;
  bool _busy = false;

  final _name = TextEditingController();
  String? _state;

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
        _states = states;
        _error = null;
      });
      // One shop: its alert page IS the payment-alerts page (only on the first load, only in the app router).
      if (!_forwarded && shops.length == 1 && GoRouter.maybeOf(context) != null) {
        _forwarded = true;
        context.pushReplacement('/me/payment-alerts/${shops.first['id']}');
      }
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
                ? (te ? 'అలర్ట్స్, సిబ్బంది, హిస్టరీ' : 'Alerts, staff, history')
                : (te ? 'ఈ ఫోన్‌లో సౌండ్ ఆన్ చేయి' : 'Switch the sound on on this phone')),
          ),
        ]),
      ),
    );
  }
}
