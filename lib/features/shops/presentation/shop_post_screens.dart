import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../../../core/share/askodox_image_share.dart';
import '../../../services/image_studio_service.dart';
import '../../pos/data/pos_repository.dart';
import 'my_business_screens.dart' show askodoxBoxMic;

/// What the AI designer is asked for a shop's daily post: the subject is the owner's own words; the picture carries a
/// short greeting / offer line for the occasion in the owner's language; never phone numbers, links or real faces.
String askodoxShopPostDesignPrompt({required String subject, required String shop, required bool te}) {
  final from = shop.trim().isEmpty ? 'a local shop' : '"${shop.trim()}"';
  final lang = te ? 'Telugu' : 'English';
  return 'Design a warm, festive square social-media post picture for $from about: ${subject.trim()}. '
      'Write one short greeting or offer line for this occasion in $lang, in large clear letters. '
      'Leave the bottom 12% plain (a brand bar is added there). No phone numbers, no website links, no QR codes, '
      "no real people's faces.";
}

bool _shopTe(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

/// The picture every follower sees: the warm card, the caption, and the ASKODOX brand bar burned in.
/// It is drawn here (Telugu text, same look everywhere) and captured as a PNG, so the brand travels with it.
class AskodoxBrandedPostCard extends StatelessWidget {
  const AskodoxBrandedPostCard({super.key, required this.shopName, required this.caption, this.picture});
  final String shopName;
  final String caption;

  /// The AI-designed picture (owner 2026-11-24: the box is a SUBJECT; AI draws the picture + greeting line).
  /// With a picture the caption is not drawn again (the picture carries the words); the brand bar stays.
  final Uint8List? picture;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDE68A), Color(0xFFFB923C)]),
        ),
        child: Column(
          children: [
            Expanded(
              child: picture != null
                  ? Image.memory(picture!, key: const Key('askodoxShopPostPicture'), width: double.infinity,
                      fit: BoxFit.cover)
                  : Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(caption,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF7C2D12))),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Created by $shopName · ASKODOX',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The owner's composer: write the line, see the picture, post it (one per shop per day).
class AskodoxShopPostScreen extends ConsumerStatefulWidget {
  const AskodoxShopPostScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopPostScreen> createState() => _AskodoxShopPostScreenState();
}

class _AskodoxShopPostScreenState extends ConsumerState<AskodoxShopPostScreen> {
  final _cardKey = GlobalKey();
  final _caption = TextEditingController();
  String _shopName = '';
  Uint8List? _picture;
  bool _designing = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadShop() async {
    try {
      final shop = await ref.read(askodoxPosRepositoryProvider).shopState(widget.businessId);
      if (mounted) setState(() => _shopName = '${shop['name']}');
    } catch (_) {}
  }

  Future<Uint8List> _capturePng() async {
    final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // A photo inside the card makes a big PNG: a lower ratio keeps it under the 2 MB post limit.
    final image = await boundary.toImage(pixelRatio: _picture == null ? 2 : 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// AI draws the post from the subject: a picture that fits the occasion with a short greeting / offer line in
  /// the person's language (the shop name + ASKODOX bar is added by the card itself).
  Future<void> _design() async {
    final te = _shopTe(context);
    final subject = _caption.text.trim();
    if (subject.length < 3 || _designing) return;
    setState(() {
      _designing = true;
      _message = null;
    });
    final result = await ref.read(imageStudioServiceProvider).edit(
          prompt: askodoxShopPostDesignPrompt(subject: subject, shop: _shopName, te: te),
          images: const [],
          language: te ? 'te' : 'en',
          authToken: ref.read(authSessionProvider).tokenPlaceholder,
        );
    if (!mounted) return;
    setState(() {
      _designing = false;
      if (result.ok) {
        _picture = result.bytes;
      } else {
        _message = te
            ? 'AI బొమ్మ ఇప్పుడు రాలేదు (${result.code}). మళ్ళీ నొక్కండి — లేకపోతే రంగుల కార్డ్‌తోనే పోస్ట్ చేయొచ్చు.'
            : 'No AI picture this time (${result.code}). Try again — or post with the colour card.';
      }
    });
  }

  Future<void> _post() async {
    final te = _shopTe(context);
    final text = _caption.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final png = await _capturePng();
      await ref.read(askodoxPosRepositoryProvider).createShopPost(widget.businessId, text, base64Encode(png));
      if (mounted) {
        setState(() => _message = te ? 'పోస్ట్ అయింది. ఫాలోవర్లకు కనిపిస్తుంది.' : 'Posted. Followers will see it.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = te
            ? 'ఈ రోజు ఇప్పటికే పోస్ట్ అయింది, లేదా ఇప్పుడు పంపలేకపోయాం.'
            : 'Already posted today, or could not send now.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _shopTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఈ రోజు పోస్ట్' : "Today's post")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: AskodoxBrandedPostCard(
                shopName: _shopName.isEmpty ? 'ASKODOX' : _shopName,
                caption: _caption.text.trim().isEmpty ? (te ? 'మీ సందేశం ఇక్కడ' : 'Your message here') : _caption.text.trim(),
                picture: _picture),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            maxLength: 300,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: te ? 'దేని గురించి? (సబ్జెక్ట్ — ఉదా: దీపావళి శుభాకాంక్షలు + 10% ఆఫర్)' : 'What about? (subject — e.g. Diwali wishes + 10% off)',
                border: const OutlineInputBorder(),
                suffixIcon: askodoxBoxMic(context, _caption, changed: () => setState(() {}))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxShopPostDesign'),
                onPressed: _designing || _caption.text.trim().length < 3 ? null : _design,
                icon: _designing
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_picture == null ? (te ? 'AI డిజైన్' : 'AI design') : (te ? 'ఇంకో డిజైన్' : 'Another design')),
              ),
            ),
            if (_picture != null) ...[
              const SizedBox(width: 8),
              IconButton(
                  key: const Key('askodoxShopPostPlain'),
                  tooltip: te ? 'రంగుల కార్డ్' : 'Colour card',
                  onPressed: () => setState(() => _picture = null),
                  icon: const Icon(Icons.format_color_fill_rounded)),
            ],
          ]),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || _caption.text.trim().isEmpty ? null : _post,
            child: Text(te ? 'ఫాలోవర్లకు పోస్ట్ చేయండి' : 'Post to followers'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!),
          ],
          const SizedBox(height: 10),
          Text(te
              ? 'రోజుకు ఒక్కటే పోస్ట్. ఫాలోవర్లు మాత్రమే చూస్తారు.'
              : 'One post a day. Only followers see it.'),
        ],
      ),
    );
  }
}

/// Pictures from the shops you follow. Share sends the picture (with the brand in it) and the caption.
class AskodoxShopFeedScreen extends ConsumerStatefulWidget {
  const AskodoxShopFeedScreen({super.key});

  @override
  ConsumerState<AskodoxShopFeedScreen> createState() => _AskodoxShopFeedScreenState();
}

class _AskodoxShopFeedScreenState extends ConsumerState<AskodoxShopFeedScreen> {
  late final Future<List<AskodoxJson>> _feed = ref.read(askodoxPosRepositoryProvider).myFeed();

  @override
  Widget build(BuildContext context) {
    final te = _shopTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ అప్‌డేట్స్' : 'Shop updates')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _feed,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text(te ? 'ఇప్పుడు లోడ్ కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not load right now. Try again.'));
          }
          final posts = snapshot.data ?? const <AskodoxJson>[];
          if (posts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(te
                    ? 'ఇంకా అప్‌డేట్స్ లేవు. షాప్‌ను ఫాలో చేయండి.'
                    : 'No updates yet. Follow a shop to see its posts.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final post = posts[index];
              final bytes = base64Decode('${post['image_base64'] ?? ''}');
              final caption = '${post['caption']}';
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.memory(bytes, fit: BoxFit.cover),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(child: Text(caption)),
                          IconButton(
                            tooltip: te ? 'షేర్' : 'Share',
                            icon: const Icon(Icons.share_outlined),
                            onPressed: () => askodoxShareImage(bytes,
                                name: 'askodox-${post['business_id']}',
                                text: '$caption\n${post['credit']}'),
                          ),
                          TextButton(
                            onPressed: () => context.push('/shops/${post['business_id']}'),
                            child: Text(te ? 'షాప్' : 'Shop'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
