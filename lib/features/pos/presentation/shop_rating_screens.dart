import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/backend_providers.dart';
import '../../../shared/widgets/navigator_section.dart' show AskodoxNavSection;
import '../../../services/media_picker.dart';
import '../data/pos_repository.dart';
import '../domain/order_steps.dart' show askodoxClockWords;
import 'pos_common.dart';

/// Ratings, reviews and the shop page (owner 2026-11-17).
/// - After an order ends: stars for the shop + each item (no writing), asked once (+ once more the next day).
/// - The shop page (like Google): photos, follow / menu / directions / call, rating summary, item ratings, reviews.
/// - Reviews are for the SHOP only (words + up to 3 photos); the owner can reply; anyone can report.

const _amber = Color(0xFFF59E0B);

/// Five stars; [onTap] makes them tappable (null = read-only).
class AskodoxStars extends StatelessWidget {
  const AskodoxStars({super.key, required this.value, this.size = 26, this.onTap, this.keyPrefix = ''});
  final num value;
  final double size;
  final ValueChanged<int>? onTap;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          onTap == null
              ? Icon(i <= value.round() ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: _amber)
              : InkResponse(
                  key: keyPrefix.isEmpty ? null : Key('$keyPrefix-$i'),
                  radius: size * 0.8,
                  onTap: () => onTap!(i),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: _amber),
                  ),
                ),
      ]);
}

/// "★4.5 (312)" in one line.
Widget askodoxRatingLine(Object? rating, {double size = 13}) {
  final r = rating is Map ? rating : const {};
  final avg = r['average'];
  final n = r['count'];
  if (avg is! num || n is! num || n == 0) return const SizedBox.shrink();
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.star_rounded, size: size + 2, color: _amber),
    Text(' ${avg.toStringAsFixed(1)} ($n)', style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
  ]);
}

/// Opens the rating sheet for a finished order when there is something to rate. Returns true when stars were saved.
Future<bool> askodoxAskRating(BuildContext context, WidgetRef ref, String orderId) async {
  AskodoxJson ask = const {};
  try {
    ask = askodoxPosMap((await ref.read(askodoxPosRepositoryProvider).rateAsk(orderId))['ask']);
  } catch (_) {
    return false;
  }
  if (ask.isEmpty || !context.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AskodoxRateSheet(orderId: orderId, ask: ask),
  );
  return saved == true;
}

class AskodoxRateSheet extends ConsumerStatefulWidget {
  const AskodoxRateSheet({super.key, required this.orderId, required this.ask});
  final String orderId;
  final AskodoxJson ask;

  @override
  ConsumerState<AskodoxRateSheet> createState() => _AskodoxRateSheetState();
}

class _AskodoxRateSheetState extends ConsumerState<AskodoxRateSheet> {
  int _shop = 0;
  final _items = <String, int>{};
  bool _busy = false;

  Future<void> _send({bool later = false}) async {
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).rate(widget.orderId,
          shop: _shop > 0 ? _shop : null, items: Map.of(_items), later: later);
      if (mounted) Navigator.pop(context, !later);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final name = '${widget.ask['name'] ?? ''}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              name.isEmpty ? (te ? 'ఎలా ఉంది?' : 'How was it?') : (te ? 'ఎలా ఉంది, $name గారు?' : 'How was it, $name?'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          Text(
              te
                  ? 'మీ రేటింగ్ ఇతరులకు సరైనది ఎంచుకోవడానికి సహాయం చేస్తుంది. నక్షత్రాలు మాత్రమే — రాయాల్సిన పని లేదు.'
                  : 'Your stars help others choose. Stars only — nothing to write.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8EB), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('${widget.ask['shop'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              AskodoxStars(value: _shop, size: 36, keyPrefix: 'askodoxRateShop', onTap: (v) => setState(() => _shop = v)),
            ]),
          ),
          if (askodoxPosList(widget.ask['items']).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(te ? 'మీరు తీసుకున్న ఐటమ్స్' : 'What you had', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF5B6475))),
            for (final it in askodoxPosList(widget.ask['items']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  AskodoxStars(
                      value: _items['${it['product_id']}'] ?? 0,
                      size: 26,
                      keyPrefix: 'askodoxRateItem-${it['product_id']}',
                      onTap: (v) => setState(() => _items['${it['product_id']}'] = v)),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  key: const Key('askodoxRateLater'),
                  onPressed: _busy ? null : () => _send(later: true),
                  child: Text(te ? 'తర్వాత' : 'Later')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                  key: const Key('askodoxRateSend'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy || (_shop == 0 && _items.isEmpty) ? null : _send,
                  child: Text(te ? 'రేటింగ్ ఇవ్వు' : 'Send rating')),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ======================================================================== the shop page

class AskodoxShopPageScreen extends ConsumerStatefulWidget {
  const AskodoxShopPageScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopPageScreen> createState() => _AskodoxShopPageScreenState();
}

class _AskodoxShopPageScreenState extends ConsumerState<AskodoxShopPageScreen> {
  AskodoxJson? _page;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(askodoxPosRepositoryProvider).shopPage(widget.businessId);
      if (mounted) {
        setState(() {
          _page = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _photoUrl(String kind, String id) {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final path = '/api/pos/shops/${widget.businessId}/photo/$kind/$id';
    return base == null ? path : base.resolve(path).toString();
  }

  Future<void> _follow(bool following) async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      following ? await repo.unfollowShop(widget.businessId) : await repo.followShop(widget.businessId);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  String _category(AskodoxJson prof, bool te) {
    final labels = askodoxPosMap(prof['labels']);
    String pick(String key) => '${askodoxPosMap(labels[key])[te ? 'te' : 'en'] ?? ''}';
    return [pick('category'), pick('subcategory')].where((x) => x.isNotEmpty).join(' · ');
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url.startsWith('http') || url.contains(':') ? url : 'https://$url');
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final p = _page;
    if (_error != null) return Scaffold(appBar: AppBar(), body: AskodoxPosError(error: _error!, onRetry: _load));
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final b = askodoxPosMap(p['business']);
    final prof = askodoxPosMap(p['profile']);
    final rating = askodoxPosMap(p['rating']);
    final following = p['following'] == true;
    final photos = askodoxPosList(p['photos']);
    final dist = askodoxPosMap(rating['by_stars']);
    final total = askodoxPosInt(rating['count']);
    Widget action(String key, IconData icon, String label, VoidCallback onTap, int c) {
      final (bg, fg) = AskodoxNavSection.palette[c % AskodoxNavSection.palette.length];
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: Key(key),
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 60,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(height: 3),
                  Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    final socials = [
      for (final s in const [('instagram', 'Instagram'), ('facebook', 'Facebook'), ('youtube', 'YouTube'), ('website', 'Website')])
        if ('${prof[s.$1] ?? ''}'.trim().isNotEmpty) (s.$1, s.$2, '${prof[s.$1]}'.trim()),
    ];
    return Scaffold(
      key: const Key('askodoxShopPage'),
      appBar: AppBar(title: Text('${b['name'] ?? ''}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
          if (photos.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final ph in photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_photoUrl('${ph['kind']}', '${ph['id']}'),
                          width: 140,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 140, color: const Color(0xFFE5E7EB))),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          Text('${b['name'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            askodoxRatingLine(rating, size: 13.5),
            if (_category(prof, te).isNotEmpty) Text('· ${_category(prof, te)}'),
            Text('· ${p['followers'] ?? 0} ${te ? 'మంది ఫాలో' : 'followers'}'),
          ]),
          if ('${b['address'] ?? ''}'.isNotEmpty) Text('${b['address']}', style: const TextStyle(color: Color(0xFF5B6475))),
          if ('${prof['hours'] ?? ''}'.isNotEmpty)
            Text('${te ? 'సమయం' : 'Hours'}: ${prof['hours']}', style: const TextStyle(color: Color(0xFF17784C), fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            if (p['is_owner'] == true)
              action('askodoxShopPost', Icons.edit_outlined, te ? 'పోస్ట్' : 'Post', () => context.push('/shops/${widget.businessId}/post'), 0)
            else
              action('askodoxShopFollow', following ? Icons.check : Icons.add,
                  following ? (te ? 'ఫాలో ✓' : 'Following') : (te ? 'ఫాలో' : 'Follow'), () => _follow(following), 0),
            action('askodoxShopMenu', Icons.restaurant_menu, te ? 'మెనూ' : 'Menu',
                () => context.push('/order-desk?code=${Uri.encodeQueryComponent('${p['code']}')}'), 1),
            action('askodoxShopDirections', Icons.directions_outlined, te ? 'దారి' : 'Directions', () {
              final lat = '${prof['lat'] ?? ''}', lng = '${prof['lng'] ?? ''}';
              unawaited(_open(lat.isNotEmpty && lng.isNotEmpty
                  ? 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
                  : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent('${b['name']} ${b['address']}')}'));
            }, 2),
            if ('${b['phone'] ?? ''}'.isNotEmpty)
              action('askodoxShopCall', Icons.call_outlined, te ? 'కాల్' : 'Call', () => unawaited(_open('tel:${b['phone']}')), 3),
          ]),
          if (p['is_owner'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(te ? 'ఇది మీ షాప్ — కస్టమర్లకు ఇలాగే కనిపిస్తుంది.' : 'This is your shop — customers see it like this.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E3FA0))),
            ),
          if ('${prof['description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${prof['description']}'),
          ],
          if (socials.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(te ? 'ఇతర చోట్ల (అక్కడ మీరే ఫాలో నొక్కాలి)' : 'Elsewhere (tap Follow there yourself)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
            Wrap(spacing: 6, children: [
              for (final s in socials)
                ActionChip(key: Key('askodoxShopSocial-${s.$1}'), label: Text('${s.$2} ↗'), onPressed: () => _open(s.$3)),
            ]),
          ],
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Column(children: [
                    Text(rating['average'] is num ? (rating['average'] as num).toStringAsFixed(1) : '—',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                    AskodoxStars(value: rating['average'] is num ? rating['average'] as num : 0, size: 14),
                    Text('$total ${te ? 'రేటింగ్స్' : 'ratings'}', style: const TextStyle(fontSize: 11.5)),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(children: [
                      for (final n in const ['5', '4', '3', '2', '1'])
                        Row(children: [
                          SizedBox(width: 12, child: Text(n, style: const TextStyle(fontSize: 11.5))),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : askodoxPosInt(dist[n]) / total,
                              minHeight: 7,
                              color: _amber,
                              backgroundColor: const Color(0xFFEEF0F3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ]),
                    ]),
                  ),
                ]),
                if (askodoxPosList(p['item_ratings']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final r in askodoxPosList(p['item_ratings']))
                      Chip(label: Text('${r['name']} ★${(r['average'] as num).toStringAsFixed(1)}'), visualDensity: VisualDensity.compact),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: Text('${te ? 'రివ్యూలు' : 'Reviews'} (${askodoxPosList(p['reviews']).length})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  if (p['can_review'] == true)
                    FilledButton(
                      key: const Key('askodoxShopWriteReview'),
                      onPressed: () async {
                        final mine = askodoxPosList(p['reviews']).where((r) => r['mine'] == true).firstOrNull;
                        final saved = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => AskodoxReviewSheet(businessId: widget.businessId, mine: mine),
                        );
                        if (saved == true) await _load();
                      },
                      child: Text(te ? 'రివ్యూ రాయి' : 'Write a review'),
                    ),
                ]),
                for (final r in askodoxPosList(p['reviews'])) _review(r, te),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _replyTo(AskodoxJson r, bool te) async {
    final c = TextEditingController(text: '${r['reply'] ?? ''}');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'రివ్యూకి జవాబు' : 'Reply to the review'),
        content: TextField(controller: c, maxLines: 3, maxLength: 400, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(te ? 'పంపు' : 'Send')),
        ],
      ),
    );
    c.dispose();
    if (text == null) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).replyReview(widget.businessId, '${r['id']}', text);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Widget _review(AskodoxJson r, bool te) => Padding(
        key: Key('askodoxReview-${r['id']}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, child: Text('${r['name']}'.isEmpty ? '?' : '${r['name']}'.characters.first)),
            const SizedBox(width: 8),
            Expanded(child: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(askodoxClockWords(r['at'], te), style: const TextStyle(fontSize: 11, color: Color(0xFF5B6475))),
            if (r['mine'] != true)
              IconButton(
                tooltip: te ? 'రిపోర్ట్' : 'Report',
                icon: const Icon(Icons.flag_outlined, size: 18),
                onPressed: () async {
                  await ref.read(askodoxPosRepositoryProvider).reportReview('${r['id']}');
                  if (mounted) askodoxPosSnack(context, te ? 'రిపోర్ట్ చేశాం. ధన్యవాదాలు.' : 'Reported. Thank you.');
                },
              ),
          ]),
          Padding(padding: const EdgeInsets.only(left: 36), child: AskodoxStars(value: askodoxPosInt(r['stars']), size: 14)),
          if ('${r['text'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 36, top: 2), child: Text('${r['text']}')),
          if ((r['photos'] as List? ?? const []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 6),
              child: Wrap(spacing: 6, children: [
                for (final id in (r['photos'] as List? ?? const []))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_photoUrl('review', '$id'), width: 64, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 64, height: 52, color: const Color(0xFFE5E7EB))),
                  ),
              ]),
            ),
          if (_page?['is_owner'] == true)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: TextButton.icon(
                key: Key('askodoxReviewReply-${r['id']}'),
                icon: const Icon(Icons.reply, size: 18),
                label: Text('${r['reply'] ?? ''}'.isEmpty ? (te ? 'జవాబు ఇవ్వు' : 'Reply') : (te ? 'జవాబు మార్చు' : 'Edit reply')),
                onPressed: () => _replyTo(r, te),
              ),
            ),
          if ('${r['reply'] ?? ''}'.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 36, top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(8)),
              child: Text('${te ? 'షాప్ జవాబు' : 'Shop reply'}: ${r['reply']}', style: const TextStyle(fontSize: 12.5)),
            ),
        ]),
      );
}

/// Write / change / delete my review of a shop: stars, words, up to 3 photos.
class AskodoxReviewSheet extends ConsumerStatefulWidget {
  const AskodoxReviewSheet({super.key, required this.businessId, this.mine});
  final String businessId;
  final AskodoxJson? mine;

  @override
  ConsumerState<AskodoxReviewSheet> createState() => _AskodoxReviewSheetState();
}

class _AskodoxReviewSheetState extends ConsumerState<AskodoxReviewSheet> {
  late int _stars = askodoxPosInt(widget.mine?['stars']);
  late final _text = TextEditingController(text: '${widget.mine?['text'] ?? ''}');
  final _photos = <AskodoxJson>[];
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final te = askodoxPosTe(context);
    final picked = (await ref.read(askodoxMediaPickerProvider).pick('photos')).where((a) => a.isImage).toList();
    for (final a in picked.take(3 - _photos.length)) {
      if (a.bytes.length > 400000) {
        if (mounted) askodoxPosSnack(context, te ? 'ఫోటో 400 KB కంటే చిన్నది కావాలి.' : 'Photos must be under 400 KB.');
        continue;
      }
      _photos.add({'data': base64Encode(a.bytes), 'mime': a.mimeType});
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).writeReview(widget.businessId, _stars, _text.text.trim(), _photos);
      if (mounted) Navigator.pop(context, true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'షాప్ గురించి రివ్యూ' : 'Review this shop', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Center(child: AskodoxStars(value: _stars, size: 36, keyPrefix: 'askodoxReviewStar', onTap: (v) => setState(() => _stars = v))),
          const SizedBox(height: 8),
          TextField(
            key: const Key('askodoxReviewText'),
            controller: _text,
            maxLines: 4,
            maxLength: 800,
            decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: te ? 'రుచి, శుభ్రత, సర్వీస్ ఎలా ఉంది?' : 'How were the taste, cleanliness and service?'),
          ),
          Row(children: [
            OutlinedButton.icon(
                onPressed: _photos.length >= 3 ? null : _addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text('${te ? 'ఫోటో' : 'Photo'} (${_photos.length}/3)')),
            const Spacer(),
            if (widget.mine != null)
              TextButton(
                onPressed: () async {
                  await ref.read(askodoxPosRepositoryProvider).deleteReview(widget.businessId);
                  if (context.mounted) Navigator.pop(context, true);
                },
                child: Text(te ? 'తీసేయి' : 'Delete'),
              ),
          ]),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('askodoxReviewSave'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy || _stars == 0 ? null : _save,
            child: Text(te ? 'పోస్ట్ చేయి' : 'Post'),
          ),
        ]),
      ),
    );
  }
}
