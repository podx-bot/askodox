import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pos/data/pos_repository.dart';

const _green = Color(0xFF0B7A4B);

/// The kinds of shop offered first (the server's own templates; "Other" = general). The kind decides which pages the
/// Seller side shows (a hotel gets tables + kitchen) and the ready catalogue.
const askodoxShopKinds = <(String, String, String, IconData)>[
  ('kirana', 'Kirana / general store', 'కిరాణా', Icons.storefront_rounded),
  ('restaurant', 'Hotel / restaurant', 'హోటల్ / టిఫిన్', Icons.restaurant_rounded),
  ('meat_fish', 'Meat / fish', 'మాంసం / చేపలు', Icons.set_meal_rounded),
  ('vegetables', 'Vegetables / fruits', 'కూరగాయలు / పండ్లు', Icons.eco_rounded),
  ('pharmacy', 'Medical shop', 'మెడికల్ షాప్', Icons.local_pharmacy_rounded),
  ('bakery', 'Bakery / sweets', 'బేకరీ / స్వీట్స్', Icons.bakery_dining_rounded),
  ('clothing', 'Clothes', 'బట్టల షాప్', Icons.checkroom_rounded),
  ('electronics', 'Mobiles / electronics', 'మొబైల్ / ఎలక్ట్రానిక్స్', Icons.phone_android_rounded),
  ('salon', 'Salon / beauty', 'సెలూన్ / బ్యూటీ', Icons.content_cut_rounded),
  ('repair', 'Repair / service', 'రిపేర్ / సర్వీస్', Icons.build_rounded),
  ('general', 'Other', 'ఇతర', Icons.more_horiz_rounded),
];

/// Seller side, first time (owner 2026-11-22): no shop yet -> one card: the shop's name, its state and its kind. The
/// QR / UPI and the payment sound come next as the shop's own pages. Nothing is created until "Start".
class AskodoxShopSetupCard extends ConsumerStatefulWidget {
  const AskodoxShopSetupCard({super.key, required this.onCreated});
  final Future<void> Function(String businessId) onCreated;

  @override
  ConsumerState<AskodoxShopSetupCard> createState() => _AskodoxShopSetupCardState();
}

class _AskodoxShopSetupCardState extends ConsumerState<AskodoxShopSetupCard> {
  final _name = TextEditingController();
  Map<String, String> _states = const {};
  String? _state;
  String _kind = 'kirana';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStates());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadStates() async {
    try {
      final meta = await ref.read(askodoxPosRepositoryProvider).meta();
      final states = {for (final e in askodoxPosMap(meta['states']).entries) e.key: '${e.value}'};
      if (mounted) setState(() => _states = states);
    } catch (_) {
      if (mounted) setState(() => _error = 'states');
    }
  }

  Future<void> _start(bool te) async {
    final name = _name.text.trim();
    if (name.isEmpty || _state == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(askodoxPosRepositoryProvider).createBusiness(
          {'name': name, 'state_code': _state, 'registration_type': 'unregistered', 'template': _kind});
      final id = '${r['id'] ?? ''}';
      if (id.isNotEmpty) await widget.onCreated(id);
    } catch (_) {
      if (mounted) setState(() => _error = 'create');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final states = _states.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final ready = _name.text.trim().isNotEmpty && _state != null && !_busy;
    return ListView(key: const Key('askodoxShopSetup'), padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.storefront_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(te ? 'మీ షాప్ మొదలుపెట్టండి' : 'Start your shop',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              Text(
                  te
                      ? 'షాప్ డబ్బు మీ సొంత డబ్బుతో కలవదు. బిల్లులు, బాకీలు, పేమెంట్ సౌండ్ అన్నీ షాప్ పేరు మీద.'
                      : 'Shop money never mixes with your own. Bills, dues and the payment sound stay under the shop.',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('askodoxShopSetupName'),
        controller: _name,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: te ? 'షాప్ పేరు' : 'Shop name',
            hintText: te ? 'ఉదా: శ్రీ లక్ష్మి కిరాణా' : 'e.g. Sri Lakshmi Kirana',
            border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        key: const Key('askodoxShopSetupState'),
        initialValue: _state,
        isExpanded: true,
        decoration: InputDecoration(labelText: te ? 'రాష్ట్రం' : 'State', border: const OutlineInputBorder()),
        items: [for (final e in states) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => setState(() => _state = v),
      ),
      const SizedBox(height: 14),
      Text(te ? 'ఏ రకం షాప్?' : 'What kind of shop?', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, en, tel, icon) in askodoxShopKinds)
          ChoiceChip(
            key: ValueKey('askodoxShopKind-$id'),
            selected: _kind == id,
            avatar: Icon(icon, size: 18),
            label: Text(te ? tel : en),
            onSelected: (_) => setState(() => _kind = id),
          ),
      ]),
      const SizedBox(height: 16),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              _error == 'states'
                  ? (te ? 'రాష్ట్రాల లిస్ట్ రాలేదు. ఇంటర్నెట్ చూసి మళ్ళీ తెరవండి.' : 'Could not load the states. Check the internet.')
                  : (te ? 'షాప్ సేవ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'The shop was not saved. Try again.'),
              style: const TextStyle(color: Color(0xFFB42318))),
        ),
      FilledButton.icon(
        key: const Key('askodoxShopSetupStart'),
        style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(50)),
        onPressed: ready ? () => _start(te) : null,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_rounded),
        label: Text(te ? 'మొదలుపెట్టు' : 'Start'),
      ),
      const SizedBox(height: 10),
      Text(
          te
              ? 'తర్వాత: మీ QR / UPI పెట్టండి, పేమెంట్ సౌండ్ ఆన్ చేయండి — రెండూ షాప్ పేజీల్లోనే ఉంటాయి. ASKODOX మీ డబ్బు ఎప్పుడూ పట్టుకోదు.'
              : 'Next: add your QR / UPI and turn on the payment sound -- both are among the shop pages. ASKODOX never holds your money.',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
    ]);
  }
}
