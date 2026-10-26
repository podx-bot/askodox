import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../../../shared/widgets/askodox_tile_grid.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';
import 'pos_payment_alerts_screen.dart';

const askodoxPosTemplates = <String, (String, String)>{
  'general': ('General shop', 'సాధారణ షాపు'),
  'kirana': ('Kirana / grocery', 'కిరాణా'),
  'supermarket': ('Supermarket', 'సూపర్ మార్కెట్'),
  'meat_fish': ('Meat / chicken / fish', 'మాంసం / చికెన్ / చేపలు'),
  'restaurant': ('Restaurant / hotel', 'రెస్టారెంట్ / హోటల్'),
  'pharmacy': ('Pharmacy', 'మెడికల్ షాపు'),
  'salon': ('Salon / spa', 'సెలూన్'),
  'repair': ('Repair / service centre', 'రిపేర్ షాపు'),
  'wholesale': ('Wholesale / distributor', 'హోల్‌సేల్'),
  'clothing': ('Clothing / footwear', 'బట్టలు / చెప్పులు'),
  'electronics': ('Mobile / electronics', 'మొబైల్ / ఎలక్ట్రానిక్స్'),
  'jewellery': ('Jewellery', 'నగలు'),
  'bakery': ('Bakery / sweets', 'బేకరీ / స్వీట్స్'),
  'vegetables': ('Vegetables / fruits', 'కూరగాయలు / పండ్లు'),
  'hardware': ('Hardware / building material', 'హార్డ్‌వేర్'),
  'stationery': ('Stationery / books', 'స్టేషనరీ'),
};

/// Business types that work with tables + kitchen tickets (configuration, not separate code).
const askodoxPosTableTemplates = {'restaurant', 'bakery'};

final _businessesProvider = FutureProvider.autoDispose<List<AskodoxJson>>(
    (ref) => ref.watch(askodoxPosRepositoryProvider).businesses());

/// POS entry (from Profile / My Business tools): the user's shops, or set one up.
class AskodoxPosHomeScreen extends ConsumerWidget {
  const AskodoxPosHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final signedIn = ref.watch(authSessionProvider).user != null;
    final data = ref.watch(_businessesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ బిల్లింగ్ (POS)' : 'Shop billing (POS)')),
      body: !signedIn
          ? Center(child: Text(te ? 'బిల్లింగ్ కోసం సైన్ ఇన్ చేయండి.' : 'Sign in to use billing.'))
          : data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AskodoxPosError(error: e, onRetry: () => ref.invalidate(_businessesProvider)),
              data: (list) => list.isEmpty
                  ? AskodoxPosSetupForm(onCreated: (id) {
                      ref.invalidate(_businessesProvider);
                      context.push('/pos/$id');
                    })
                  : ListView(key: const Key('askodoxPosBusinesses'), padding: const EdgeInsets.all(12), children: [
                      for (final b in list)
                        Card(
                          child: ListTile(
                            key: ValueKey('askodoxPosBusiness-${b['id']}'),
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text('${b['name']}'),
                            subtitle: Text('${askodoxPosTemplates[b['template']]?.$1 ?? b['template']} · ${b['role']}'),
                            onTap: () => context.push('/pos/${b['id']}'),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                                appBar: AppBar(title: Text(te ? 'కొత్త షాపు' : 'New shop')),
                                body: AskodoxPosSetupForm(onCreated: (id) {
                                  ref.invalidate(_businessesProvider);
                                  Navigator.of(context).pop();
                                })))),
                        icon: const Icon(Icons.add),
                        label: Text(te ? 'ఇంకో షాపు జోడించండి' : 'Add another shop'),
                      ),
                    ]),
            ),
    );
  }
}

class AskodoxPosSetupForm extends ConsumerStatefulWidget {
  const AskodoxPosSetupForm({super.key, required this.onCreated});
  final ValueChanged<String> onCreated;

  @override
  ConsumerState<AskodoxPosSetupForm> createState() => _AskodoxPosSetupFormState();
}

class _AskodoxPosSetupFormState extends ConsumerState<AskodoxPosSetupForm> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  final _prefix = TextEditingController(text: 'INV');
  String _template = 'general';
  String _registration = 'unregistered';
  String? _state;
  bool _above5cr = false;
  bool _busy = false;
  String? _error;
  Map<String, String> _states = const {};

  @override
  void initState() {
    super.initState();
    ref.read(askodoxPosRepositoryProvider).meta().then((m) {
      if (mounted) setState(() => _states = {for (final e in askodoxPosMap(m['states']).entries) e.key: '${e.value}'});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _gstin, _prefix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final te = askodoxPosTe(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref.read(askodoxPosRepositoryProvider).createBusiness({
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'template': _template,
        'registration_type': _registration,
        if (_registration != 'unregistered') 'gstin': _gstin.text.trim().toUpperCase(),
        if (_registration == 'unregistered' && _state != null) 'state_code': _state,
        'invoice_prefix': _prefix.text.trim().toUpperCase(),
        'turnover_above_5cr': _above5cr,
      });
      widget.onCreated('${created['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return ListView(key: const Key('askodoxPosSetup'), padding: const EdgeInsets.all(16), children: [
      Text(te ? 'మీ షాపు వివరాలు' : 'Your shop', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      AskodoxPosField(controller: _name, label: te ? 'షాపు పేరు' : 'Shop name', maxLength: 80),
      AskodoxPosField(controller: _address, label: te ? 'చిరునామా' : 'Address', maxLength: 240),
      DropdownButtonFormField<String>(
        key: const Key('askodoxPosTemplate'),
        initialValue: _template,
        isExpanded: true,
        decoration: InputDecoration(labelText: te ? 'వ్యాపార రకం' : 'Business type', border: const OutlineInputBorder(), isDense: true),
        items: [
          for (final e in askodoxPosTemplates.entries) DropdownMenuItem(value: e.key, child: Text(te ? e.value.$2 : e.value.$1)),
        ],
        onChanged: (v) => setState(() => _template = v ?? _template),
      ),
      const SizedBox(height: 10),
      Text(te ? 'GST నమోదు' : 'GST registration', style: const TextStyle(fontWeight: FontWeight.w700)),
      for (final (value, en, tel) in [
        ('unregistered', 'Not registered for GST', 'GST నమోదు లేదు'),
        ('regular', 'Regular GST (tax invoice)', 'రెగ్యులర్ GST (ట్యాక్స్ ఇన్‌వాయిస్)'),
        ('composition', 'Composition scheme (bill of supply, no GST collected)', 'కంపోజిషన్ (బిల్ ఆఫ్ సప్లై, GST వసూలు లేదు)'),
      ])
        ListTile(
          key: ValueKey('askodoxPosReg-$value'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(_registration == value ? Icons.radio_button_checked : Icons.radio_button_off),
          title: Text(te ? tel : en),
          onTap: () => setState(() => _registration = value),
        ),
      if (_registration != 'unregistered')
        AskodoxPosField(controller: _gstin, label: 'GSTIN', hint: '36ABCDE1234F1Z5', maxLength: 15)
      else
        DropdownButtonFormField<String>(
          key: const Key('askodoxPosState'),
          initialValue: _state,
          isExpanded: true,
          decoration: InputDecoration(labelText: te ? 'రాష్ట్రం' : 'State / UT', border: const OutlineInputBorder(), isDense: true),
          items: [for (final e in _states.entries) DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})'))],
          onChanged: (v) => setState(() => _state = v),
        ),
      const SizedBox(height: 10),
      AskodoxPosField(controller: _prefix, label: te ? 'బిల్లు నంబర్ ముందు అక్షరాలు (1-3)' : 'Bill number prefix (1-3 letters)', maxLength: 3),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _above5cr,
        onChanged: (v) => setState(() => _above5cr = v),
        title: Text(te ? 'గత సంవత్సరం టర్నోవర్ ₹5 కోట్లు దాటిందా?' : 'Last year\'s turnover above ₹5 crore?'),
        subtitle: Text(te ? '6-అంకెల HSN, ఈ-ఇన్‌వాయిస్ వర్తిస్తాయి (ఈ-ఇన్‌వాయిస్ ఇంకా లేదు).' : '6-digit HSN and e-invoicing apply (e-invoicing not built yet).'),
      ),
      if (_error != null) Text(_error!, key: const Key('askodoxPosSetupError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('askodoxPosCreate'),
        onPressed: _busy ? null : _create,
        child: Text(_busy ? (te ? 'సేవ్ అవుతోంది…' : 'Saving…') : (te ? 'షాపు ప్రారంభించండి' : 'Start billing')),
      ),
      const SizedBox(height: 8),
      Text(
        te
            ? 'HSN / GST రేటు మీ స్వంత వర్గీకరణ నుండి నమోదు చేయండి — ASKODOX ఊహించదు. నివేదికలు అకౌంటెంట్ సమీక్ష కోసం మాత్రమే.'
            : 'Enter HSN / GST rates from your own classification — ASKODOX never guesses them. Reports are for your accountant to review.',
        style: const TextStyle(fontSize: 12),
      ),
    ]);
  }
}

/// One shop's billing home: what this person's role may do.
class AskodoxPosDashboardScreen extends ConsumerStatefulWidget {
  const AskodoxPosDashboardScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosDashboardScreen> createState() => _AskodoxPosDashboardScreenState();
}

class _AskodoxPosDashboardScreenState extends ConsumerState<AskodoxPosDashboardScreen> {
  int _pending = 0;
  int _rejected = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _refreshQueue();
  }

  Future<void> _refreshQueue() async {
    final items = await ref.read(askodoxPosQueueProvider).pending();
    if (!mounted) return;
    setState(() {
      _pending = items.where((i) => i['status'] == 'pending').length;
      _rejected = items.where((i) => i['status'] == 'rejected').length;
    });
  }

  Future<void> _sync() async {
    final te = askodoxPosTe(context);
    setState(() => _syncing = true);
    final queue = ref.read(askodoxPosQueueProvider);
    final result = await queue.sync();
    try {
      await queue.ensureSeries(widget.businessId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _pending = result.pending;
      _rejected = result.rejected;
    });
    askodoxPosSnack(context, te ? '${result.sent} బిల్లులు పంపాం.' : '${result.sent} bills sent.');
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final data = ref.watch(askodoxPosBusinessProvider(widget.businessId));
    return Scaffold(
      appBar: AppBar(title: Text(data.valueOrNull?['name'] as String? ?? (te ? 'బిల్లింగ్' : 'Billing'))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AskodoxPosError(error: e, onRetry: () => ref.invalidate(askodoxPosBusinessProvider(widget.businessId))),
        data: (b) {
          final id = widget.businessId;
          final reg = '${b['registration_type']}';
          final tiles = <(String, IconData, String, String, String)>[
            if (askodoxPosCan(b, 'sell')) ('sale', Icons.point_of_sale, 'New bill', 'కొత్త బిల్లు', '/pos/$id/sale'),
            ('payalerts', Icons.volume_up_outlined, 'Payment alerts', 'పేమెంట్ అలర్ట్స్', '/pos/$id/payment-alerts'),
            if (askodoxPosCan(b, 'tables') && askodoxPosTableTemplates.contains(b['template']))
              ('tables', Icons.table_restaurant_outlined, 'Tables & KOT', 'టేబుల్స్ & KOT', '/pos/$id/tables'),
            if (askodoxPosCan(b, 'kitchen') && askodoxPosTableTemplates.contains(b['template']))
              ('kitchen', Icons.soup_kitchen_outlined, 'Kitchen screen', 'వంటగది స్క్రీన్', '/pos/$id/kitchen'),
            ('items', Icons.inventory_2_outlined, 'Items & stock', 'సరుకులు & స్టాక్', '/pos/$id/items'),
            if (askodoxPosCan(b, 'purchases'))
              ('suppliers', Icons.local_shipping_outlined, 'Suppliers & purchases', 'సప్లయర్లు & కొనుగోళ్లు', '/pos/$id/suppliers'),
            if (askodoxPosCan(b, 'stock')) ('stock', Icons.event_busy_outlined, 'Expiry & stock value', 'ఎక్స్‌పైరీ & స్టాక్ విలువ', '/pos/$id/stock-report'),
            ('customers', Icons.people_alt_outlined, 'Customers & credit', 'కస్టమర్లు & ఖాతా', '/pos/$id/customers'),
            ('bills', Icons.receipt_long_outlined, 'Bills', 'బిల్లులు', '/pos/$id/invoices'),
            ('day', Icons.calculate_outlined, 'Day close', 'రోజు ముగింపు', '/pos/$id/day'),
            if (askodoxPosCan(b, 'reports')) ('gst', Icons.summarize_outlined, 'GST summary', 'GST సారాంశం', '/pos/$id/gst'),
            if (askodoxPosCan(b, 'members')) ('staff', Icons.badge_outlined, 'Staff & roles', 'సిబ్బంది', '/pos/$id/staff'),
            ('printer', Icons.print_outlined, 'Printer', 'ప్రింటర్', '/pos/$id/printer'),
            if (askodoxPosCan(b, 'settings'))
              ('advance', Icons.savings_outlined, 'Shop advance', 'షాప్ అడ్వాన్స్', '/pos/$id/advance'),
            if (askodoxPosCan(b, 'sell'))
              ('selfshop', Icons.qr_code_2, 'Self-shopping', 'సెల్ఫ్ షాపింగ్', '/pos/$id/selfshop'),
          ];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(askodoxPosBusinessProvider(id));
              await _refreshQueue();
            },
            child: ListView(key: const Key('askodoxPosDashboard'), padding: const EdgeInsets.all(12), children: [
              Text(
                '${switch (reg) {
                  'regular' => te ? 'రెగ్యులర్ GST' : 'Regular GST',
                  'composition' => te ? 'కంపోజిషన్' : 'Composition',
                  _ => te ? 'GST నమోదు లేదు' : 'Not GST registered',
                }}${b['gstin'] == null ? '' : ' · ${b['gstin']}'} · ${te ? 'మీ పాత్ర' : 'your role'}: ${b['my_role']}',
                style: const TextStyle(fontSize: 12.5),
              ),
              if ('${askodoxPosMap(b['rules'])['einvoice_note'] ?? ''}'.isNotEmpty)
                Text('${askodoxPosMap(b['rules'])['einvoice_note']}', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
              if (_pending > 0 || _rejected > 0)
                Card(
                  key: const Key('askodoxPosQueue'),
                  color: const Color(0xFFFFF7ED),
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(te ? '$_pending బిల్లులు పంపాలి' : '$_pending bills waiting to send'),
                    subtitle: _rejected > 0
                        ? Text(te ? '$_rejected సర్వర్ తిరస్కరించింది — చూడండి' : '$_rejected rejected by the server — please check')
                        : null,
                    trailing: TextButton(onPressed: _syncing ? null : _sync, child: Text(te ? 'ఇప్పుడు పంపు' : 'Send now')),
                  ),
                ),
              AskodoxPosPaymentAlertStrip(businessId: id),
              const SizedBox(height: 8),
              AskodoxTileGrid(
                keyPrefix: 'askodoxPosTile',
                tiles: [
                  for (final (key, icon, en, tel, route) in tiles)
                    AskodoxTile(
                      id: key,
                      icon: icon,
                      title: te ? tel : en,
                      onTap: () async {
                        await context.push(route);
                        if (mounted) await _refreshQueue();
                      },
                    ),
                ],
              ),
            ]),
          );
        },
      ),
    );
  }
}
