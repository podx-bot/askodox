import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/backend_providers.dart';
import '../../services/image_studio_service.dart';
import '../../services/media_picker.dart';
import '../location/application/location_controller.dart';
import '../money_home/money_home_store.dart';
import '../pos/presentation/pos_common.dart' show askodoxPosTe;
import 'notice_repository.dart';

/// "నోటిఫికేషన్ పంపండి" (owner 2026-11-24): subject -> AI designs the picture (or own photo) -> who gets it
/// (my shop's followers / people nearby / both) -> how many people + price -> Send. One screen, no long scroll.
class AskodoxNoticeCreateScreen extends ConsumerStatefulWidget {
  const AskodoxNoticeCreateScreen({super.key, this.shopId = ''});

  final String shopId;

  @override
  ConsumerState<AskodoxNoticeCreateScreen> createState() => _AskodoxNoticeCreateScreenState();
}

class _AskodoxNoticeCreateScreenState extends ConsumerState<AskodoxNoticeCreateScreen> {
  final _subject = TextEditingController();
  final _heading = TextEditingController();
  final _offer = TextEditingController();
  late String _audience = widget.shopId.isEmpty ? 'nearby' : 'followers';
  double _km = 3;
  Uint8List? _image;
  String _imageMime = '';
  bool _designing = false;
  bool _sending = false;
  AskodoxNoticeAnswer? _count;
  String _txn = 'ntc-${DateTime.now().microsecondsSinceEpoch}';
  Timer? _debounce;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCount());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subject.dispose();
    _heading.dispose();
    _offer.dispose();
    super.dispose();
  }

  Map<String, Object?>? get _shop {
    final shops = ref.read(askodoxMyShopsProvider).valueOrNull ?? const [];
    final owned = [for (final s in shops) if ('${s['role']}' == 'owner') s];
    if (owned.isEmpty) return null;
    for (final s in owned) {
      if ('${s['id']}' == widget.shopId) return s;
    }
    return owned.first;
  }

  (double?, double?) get _where {
    final place = ref.read(locationControllerProvider);
    return place.hasPlace ? (place.centre.latitude, place.centre.longitude) : (null, null);
  }

  Future<void> _refreshCount() async {
    final (lat, lon) = _where;
    final answer = await ref.read(askodoxNoticeRepositoryProvider).preview(
        audience: _audience, shopId: '${_shop?['id'] ?? ''}', km: _km, lat: lat, lon: lon);
    if (mounted) setState(() => _count = answer);
  }

  void _choose(String audience, [double? km]) {
    setState(() {
      _audience = audience;
      if (km != null) _km = km;
      _count = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refreshCount);
  }

  Future<void> _design() async {
    final subject = _subject.text.trim();
    if (subject.length < 3 || _designing) {
      _say(_te ? 'ముందు దేని గురించో రాయండి (ఉదా: దీపావళి ఆఫర్ బిర్యానీ 20% తగ్గింపు).' : 'First write the subject (e.g. Diwali offer, 20% off biryani).');
      return;
    }
    if (_heading.text.trim().isEmpty) _heading.text = askodoxNoticeHeading(subject);
    setState(() => _designing = true);
    final result = await ref.read(imageStudioServiceProvider).edit(
          prompt: askodoxNoticeDesignPrompt(subject: subject, shop: '${_shop?['name'] ?? ''}', heading: _heading.text),
          images: const [],
          language: _te ? 'te' : 'en',
          authToken: ref.read(authSessionProvider).tokenPlaceholder,
        );
    if (!mounted) return;
    setState(() {
      _designing = false;
      if (result.ok) {
        _image = result.bytes;
        _imageMime = 'image/png';
      }
    });
    if (!result.ok) {
      _say(switch (result.code) {
        'credits_low' => askodoxNoticeReason('AI_CREDITS_LOW', _te),
        'daily_limit' => _te ? 'ఈరోజు AI బొమ్మలు అయిపోయాయి. మీ ఫోటో పెట్టండి.' : "Today's AI pictures are used up. Add your own photo.",
        'sign_in' => askodoxNoticeReason('sign_in', _te),
        _ => _te ? 'బొమ్మ ఇప్పుడు రాలేదు. మళ్ళీ నొక్కండి లేదా మీ ఫోటో పెట్టండి.' : 'No picture this time. Try again or add your photo.',
      });
    }
  }

  Future<void> _photo() async {
    final picked = await ref.read(askodoxMediaPickerProvider).pick('photos');
    final photo = picked.where((p) => p.isImage).firstOrNull;
    if (photo == null || !mounted) return;
    setState(() {
      _image = photo.bytes;
      _imageMime = photo.mimeType;
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_heading.text.trim().isEmpty) _heading.text = askodoxNoticeHeading(_subject.text);
    if (_heading.text.trim().isEmpty) {
      _say(_te ? 'హెడ్డింగ్ రాయండి.' : 'Write a heading.');
      return;
    }
    setState(() => _sending = true);
    final (lat, lon) = _where;
    final answer = await ref.read(askodoxNoticeRepositoryProvider).send(
          title: _heading.text.trim(),
          body: _offer.text.trim().isEmpty ? _subject.text.trim() : _offer.text.trim(),
          audience: _audience,
          shopId: '${_shop?['id'] ?? ''}',
          km: _km,
          lat: lat,
          lon: lon,
          image: _image,
          imageMime: _imageMime,
          clientTxnId: _txn,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!answer.ok) {
      _say(askodoxNoticeReason(answer.code, _te));
      return;
    }
    final people = answer.data['people'] ?? 0;
    final cost = (answer.data['cost_paise'] as num?)?.toInt() ?? 0;
    _say(_te
        ? '✓ $people మందికి పంపుతున్నాం${cost > 0 ? ' · ${askodoxNoticeRupees(cost)}' : ''}. చేరనివాళ్ళ డబ్బు తిరిగి వస్తుంది.'
        : '✓ Sending to $people people${cost > 0 ? ' · ${askodoxNoticeRupees(cost)}' : ''}. Not delivered = money back.');
    setState(() {
      _txn = 'ntc-${DateTime.now().microsecondsSinceEpoch}';
      _subject.clear();
      _heading.clear();
      _offer.clear();
      _image = null;
    });
    ref.invalidate(_askodoxMyNoticesProvider);
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final te = _te;
    ref.watch(askodoxMyShopsProvider);
    final shop = _shop;
    final count = _count;
    final people = (count?.data['people'] as num?)?.toInt() ?? 0;
    final cost = (count?.data['cost_paise'] as num?)?.toInt() ?? 0;
    final charging = count?.data['charging'] == true;
    final chip = (String key, String label, bool on, VoidCallback tap) => ChoiceChip(
          key: Key('askodoxNoticeAudience-$key'),
          label: Text(label),
          selected: on,
          onSelected: (_) => tap(),
        );
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నోటిఫికేషన్ పంపండి' : 'Send a notification')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          TextField(
            key: const Key('askodoxNoticeSubject'),
            controller: _subject,
            minLines: 1,
            maxLines: 2,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: te ? 'దేని గురించి? (సబ్జెక్ట్)' : 'What is it about? (subject)',
              hintText: te ? 'ఉదా: సంక్రాంతి ఆఫర్ — చికెన్ కిలో ₹20 తగ్గింపు' : 'e.g. Sankranti offer — ₹20 off per kg chicken',
            ),
          ),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('askodoxNoticeDesign'),
                onPressed: _designing ? null : _design,
                icon: _designing
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(te ? 'AI డిజైన్' : 'AI design'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxNoticePhoto'),
                onPressed: _photo,
                icon: const Icon(Icons.photo_outlined),
                label: Text(te ? 'నా ఫోటో' : 'My photo'),
              ),
            ),
          ]),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!, key: const Key('askodoxNoticePicture'), height: 180, width: double.infinity,
                      fit: BoxFit.cover),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                      onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close_rounded)),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('askodoxNoticeHeading'),
            controller: _heading,
            maxLength: 60,
            decoration: InputDecoration(labelText: te ? 'హెడ్డింగ్' : 'Heading'),
          ),
          TextField(
            key: const Key('askodoxNoticeOffer'),
            controller: _offer,
            maxLength: 200,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: te ? 'ఆఫర్ / వివరాలు (లింక్‌లు, నంబర్లు వద్దు)' : 'Offer / details (no links or numbers)',
            ),
          ),
          Text(te ? 'ఎవరికి?' : 'Who gets it?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (shop != null)
              chip('followers', te ? 'నా షాప్ ఫాలోవర్స్' : 'My shop followers', _audience == 'followers',
                  () => _choose('followers')),
            for (final km in const [1.0, 3.0, 5.0, 10.0])
              chip('nearby-${km.toInt()}', te ? '${km.toInt()} కి.మీ లోపు' : 'Within ${km.toInt()} km',
                  _audience == 'nearby' && _km == km, () => _choose('nearby', km)),
            if (shop != null)
              chip('both', te ? 'రెండూ' : 'Both', _audience == 'both', () => _choose('both')),
          ]),
          const SizedBox(height: 8),
          Card(
            key: const Key('askodoxNoticeCount'),
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: Text(count == null
                  ? (te ? 'లెక్కపెడుతున్నాం…' : 'Counting…')
                  : !count.ok
                      ? askodoxNoticeReason(count.code, te)
                      : te
                          ? '$people మందికి చేరుతుంది'
                          : 'Reaches $people people'),
              subtitle: count == null || !count.ok
                  ? null
                  : Text(charging
                      ? (te
                          ? '${askodoxNoticeRupees((count.data['rate_paise'] as num?)?.toInt() ?? 0)} ఒక్కొక్కరికి = ${askodoxNoticeRupees(cost)} (AI Credits నుంచి). చేరనివాళ్ళ డబ్బు తిరిగి వస్తుంది.'
                          : '${askodoxNoticeRupees((count.data['rate_paise'] as num?)?.toInt() ?? 0)} each = ${askodoxNoticeRupees(cost)} from AI Credits. Not delivered = money back.')
                      : (te ? 'ఇప్పుడు ఉచితం (టెస్టింగ్).' : 'Free for now (testing).')),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('askodoxNoticeSend'),
            onPressed: _sending || count == null || !count.ok || people == 0 ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(te ? 'పంపండి' : 'Send'),
          ),
          const SizedBox(height: 6),
          Text(
            te
                ? 'అందుకునేవాళ్ళు సెట్టింగ్స్ → నోటిఫికేషన్స్‌లో "ఆఫర్లు" ఆపేయొచ్చు. ఒక్కరికి రోజుకి 3 కంటే ఎక్కువ, మీ నుంచి 1 కంటే ఎక్కువ రావు.'
                : 'People can turn "Offers" off in Settings → Notifications. Nobody gets more than 3 a day, or more than 1 from you.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 28),
          Text(te ? 'నేను పంపినవి' : 'Sent by me', style: Theme.of(context).textTheme.titleSmall),
          const _AskodoxMyNotices(),
        ],
      ),
    );
  }
}

final _askodoxMyNoticesProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>(
    (ref) => ref.watch(askodoxNoticeRepositoryProvider).mine());

class _AskodoxMyNotices extends ConsumerWidget {
  const _AskodoxMyNotices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final rows = ref.watch(_askodoxMyNoticesProvider).valueOrNull ?? const [];
    if (rows.isEmpty) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(te ? 'ఇంకా ఏమీ పంపలేదు.' : 'Nothing sent yet.'));
    }
    return Column(children: [
      for (final r in rows)
        ListTile(
          key: Key('askodoxNoticeMine-${r['id']}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(te
              ? '${r['reached']} మందికి చేరింది · ${r['opened']} మంది తెరిచారు · ${askodoxNoticeRupees((r['cost_paise'] as num?)?.toInt() ?? 0)}'
              : 'Reached ${r['reached']} · opened ${r['opened']} · ${askodoxNoticeRupees((r['cost_paise'] as num?)?.toInt() ?? 0)}'),
        ),
    ]);
  }
}

/// What a receiver sees when they tap the notification (`/notice/:id`).
class AskodoxNoticeViewScreen extends ConsumerWidget {
  const AskodoxNoticeViewScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final answer = ref.watch(_askodoxNoticeProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఆఫర్' : 'Offer')),
      body: answer.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(askodoxNoticeReason('failed', te))),
        data: (a) {
          if (!a.ok) return Center(child: Text(askodoxNoticeReason(a.code, te)));
          final d = a.data;
          Uint8List? picture;
          try {
            final raw = '${d['image_base64'] ?? ''}';
            if (raw.isNotEmpty) picture = base64Decode(raw);
          } on FormatException {
            picture = null;
          }
          final shopId = '${d['business_id'] ?? ''}';
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (picture != null)
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(picture, key: const Key('askodoxNoticeViewPicture'), fit: BoxFit.cover)),
            const SizedBox(height: 12),
            Text('${d['title']}', style: Theme.of(context).textTheme.headlineSmall),
            if ('${d['from_shop'] ?? ''}'.isNotEmpty)
              Text('${d['from_shop']}', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('${d['body']}'),
            const SizedBox(height: 16),
            if (shopId.isNotEmpty)
              FilledButton.icon(
                key: const Key('askodoxNoticeOpenShop'),
                onPressed: () => context.push('/shops/$shopId'),
                icon: const Icon(Icons.storefront_rounded),
                label: Text(te ? 'షాప్ చూడండి' : 'See the shop'),
              ),
            TextButton(
              key: const Key('askodoxNoticeTurnOff'),
              onPressed: () => context.push('/settings/notifications'),
              child: Text(te ? 'ఇలాంటివి వద్దా? ఆపేయండి' : "Don't want these? Turn them off"),
            ),
          ]);
        },
      ),
    );
  }
}

final _askodoxNoticeProvider = FutureProvider.autoDispose.family<AskodoxNoticeAnswer, String>(
    (ref, id) => ref.watch(askodoxNoticeRepositoryProvider).open(id));
