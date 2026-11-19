import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../../home/presentation/question_mic.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart' show askodoxPaise;
import '../../location/application/location_controller.dart' show locationControllerProvider;
import 'pos_common.dart';

/// ASKODOX Shopping (owner 2026-11-18): only businesses on ASKODOX -- found by their name or by what their menu has --
/// and, for what was searched, the affiliate store items. No Google / web / videos here (that stays in the main chat).
/// A shop opens its own menu to order inside ASKODOX.
class AskodoxShoppingScreen extends ConsumerStatefulWidget {
  const AskodoxShoppingScreen({super.key});

  @override
  ConsumerState<AskodoxShoppingScreen> createState() => _AskodoxShoppingScreenState();
}

class _AskodoxShoppingScreenState extends ConsumerState<AskodoxShoppingScreen> {
  final _box = TextEditingController();
  Timer? _debounce;
  AskodoxJson? _data;
  bool _loading = false;
  String? _error;
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _box.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final mine = ++_ask;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final place = ref.read(locationControllerProvider).defaultLocation?.point;
      final out = await ref.read(askodoxPosRepositoryProvider).shopping(q.trim(),
          lat: place != null && place.isValid ? place.latitude : null, lng: place != null && place.isValid ? place.longitude : null);
      if (mounted && mine == _ask) setState(() => _data = out);
    } on AskodoxPosException catch (e) {
      if (mounted && mine == _ask) setState(() => _error = e.message(askodoxPosTe(context)));
    } catch (_) {
      if (mounted && mine == _ask) setState(() => _error = askodoxPosTe(context) ? 'ఇప్పుడు వెతకలేకపోయాం. మళ్లీ ప్రయత్నించండి.' : 'Could not search now. Try again.');
    } finally {
      if (mounted && mine == _ask) setState(() => _loading = false);
    }
  }

  void _typed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _open(String? url) async {
    final uri = Uri.tryParse(url ?? '');
    if (uri != null && uri.hasScheme) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _shop(AskodoxJson s, bool te) {
    final items = askodoxPosList(s['items']);
    final address = '${s['address'] ?? ''}'.trim();
    return Card(
      key: ValueKey('askodoxShoppingShop-${s['id']}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/order-desk?code=${Uri.encodeQueryComponent('${s['code']}')}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(radius: 18, backgroundColor: Color(0xFFEDE7FB), child: Icon(Icons.storefront, color: Color(0xFF5B2A9E))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  if (address.isNotEmpty || s['distance_km'] is num)
                    Text(
                        [
                          if (s['distance_km'] is num) te ? '${s['distance_km']} కి.మీ' : '${s['distance_km']} km',
                          if (address.isNotEmpty) address,
                        ].join(' · '),
                        key: ValueKey('askodoxShoppingDistance-${s['id']}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                ]),
              ),
              Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(s['open'] == false ? (te ? 'మూసి ఉంది' : 'Closed') : (te ? 'ASKODOX లో' : 'On ASKODOX'))),
            ]),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 46),
                child: Text('• ${i['name']}  ${askodoxPaise(askodoxPosInt(i['price_paise']))}', style: const TextStyle(fontSize: 13.5)),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(te ? 'మెనూ చూసి ఆర్డర్ చేయండి ›' : 'See menu & order ›',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E3FA0))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _item(AskodoxJson i, bool te) {
    final price = i['price'];
    final disclosure = '${i['disclosure'] ?? ''}'.trim();
    return Card(
      key: ValueKey('askodoxShoppingItem-${i['id']}'),
      child: ListTile(
        leading: i['image_url'] is String
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network('${i['image_url']}', width: 52, height: 52, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_outlined)))
            : const Icon(Icons.shopping_bag_outlined),
        title: Text('${i['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (price is num) '₹${price % 1 == 0 ? price.toInt() : price}',
          if ('${i['source_name'] ?? ''}'.isNotEmpty) '${i['source_name']}',
          if (disclosure.isNotEmpty) disclosure,
        ].join(' · ')),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _open('${i['destination_url'] ?? i['web_fallback_url'] ?? ''}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final shops = askodoxPosList(_data?['shops']);
    final items = askodoxPosList(_data?['items']);
    final q = '${_data?['query'] ?? ''}'.trim();
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ASKODOX షాపింగ్' : 'ASKODOX Shopping')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: [
        Text(
            te
                ? 'ASKODOX లో ఉన్న షాపులు, హోటళ్ళు మాత్రమే. ఏం కావాలో చెప్పండి లేదా టైప్ చేయండి — ఆర్డర్ ఇక్కడే.'
                : 'Only shops and hotels on ASKODOX. Say or type what you want — order right here.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
        const SizedBox(height: 8),
        TextField(
          key: const Key('askodoxShoppingBox'),
          controller: _box,
          textInputAction: TextInputAction.search,
          onChanged: _typed,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: te ? 'ఉదా: బిర్యానీ, చికెన్, షాప్ పేరు' : 'e.g. biryani, chicken, a shop name',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: AskodoxQuestionMic(
                lang: te ? 'te' : 'en',
                onText: (words) {
                  _box.text = words;
                  unawaited(_search(words));
                }),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        // Owner 2026-11-19: shop-side shortcuts live HERE only (no copies in Tools / Profile).
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ActionChip(
            key: const Key('askodoxShoppingOrderCode'),
            avatar: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(te ? 'షాప్ కోడ్ / QR తో ఆర్డర్' : 'Order with shop code / QR'),
            onPressed: () => context.push('/order-desk/enter'),
          ),
          ActionChip(
            key: const Key('askodoxShoppingFollowing'),
            avatar: const Icon(Icons.storefront_outlined, size: 18),
            label: Text(te ? 'నేను ఫాలో చేసే షాప్‌లు' : 'Shops I follow'),
            onPressed: () => context.push('/me/following'),
          ),
        ]),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 10),
        if (shops.isNotEmpty) ...[
          Text(q.isEmpty ? (te ? 'ASKODOX లో షాపులు' : 'Shops on ASKODOX') : (te ? 'ASKODOX షాపులు' : 'ASKODOX shops'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final s in shops) _shop(s, te),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(te ? 'ఆన్‌లైన్ స్టోర్‌లలో' : 'In online stores', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final i in items) _item(i, te),
        ],
        if (!_loading && _data != null && shops.isEmpty && items.isEmpty)
          Padding(
            key: const Key('askodoxShoppingEmpty'),
            padding: const EdgeInsets.only(top: 16),
            child: Column(children: [
              Text(
                  q.isEmpty
                      ? (te ? 'ఇంకా ASKODOX లో షాపులు లేవు.' : 'No shops on ASKODOX yet.')
                      : (te ? '"$q" ASKODOX లో ఇంకా లేదు.' : '"$q" is not on ASKODOX yet.'),
                  textAlign: TextAlign.center),
              if (q.isNotEmpty)
                TextButton.icon(
                  key: const Key('askodoxShoppingAskOutside'),
                  onPressed: () {
                    context.go('/');
                    ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(q);
                  },
                  icon: const Icon(Icons.travel_explore),
                  label: Text(te ? 'బయట (అన్నిచోట్ల) వెతకాలా?' : 'Search everywhere instead?'),
                ),
            ]),
          ),
      ]),
    );
  }
}
