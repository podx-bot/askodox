import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';
import '../../services/media_picker.dart';

/// ASKODOX-native videos: record or pick a video, add a title / caption /
/// category / product, upload, and staff review it before anyone sees it.
/// The feed shows only published (ACTIVE) ASKODOX videos.
class NativeVideo {
  const NativeVideo({required this.id, required this.status, required this.title, this.caption = '',
      this.url = '', this.label = '', this.categories = const []});

  factory NativeVideo.fromJson(Map<String, Object?> j) {
    final data = (j['data'] as Map?) ?? j; // /api/merchant/videos rows wrap fields in "data"
    return NativeVideo(
      id: '${j['id'] ?? ''}',
      status: '${j['status'] ?? ''}',
      title: '${data['title'] ?? ''}',
      caption: '${data['caption'] ?? data['description'] ?? ''}',
      url: '${data['url'] ?? ''}',
      label: '${j['label'] ?? ''}',
      categories: [for (final c in (data['categories'] as List? ?? const [])) '$c'],
    );
  }

  final String id, status, title, caption, url, label;
  final List<String> categories;
}

/// What the owner may do next (the backend enforces the same rules).
List<String> askodoxVideoOwnerActions(String status) => switch (status) {
      'DRAFT' || 'REJECTED' => const ['submit', 'remove'],
      'ACTIVE' => const ['pause', 'remove'],
      'PAUSED' => const ['resume', 'remove'],
      _ => const ['remove'],
    };

String askodoxVideoStatusText(String status, bool te) => switch (status) {
      'DRAFT' => te ? 'డ్రాఫ్ట్' : 'Draft',
      'PENDING_REVIEW' => te ? 'రివ్యూలో ఉంది' : 'Waiting for review',
      'ACTIVE' => te ? 'పబ్లిష్ అయింది' : 'Published',
      'PAUSED' => te ? 'ఆపబడింది' : 'Paused',
      'REJECTED' => te ? 'ఆమోదించలేదు' : 'Not approved',
      _ => status,
    };

abstract class NativeVideoRepository {
  Future<String?> upload({required List<int> bytes, required String fileName, required String title,
      String caption, String category, String products, bool asBusiness, bool submit});
  Future<List<NativeVideo>> mine();
  Future<List<NativeVideo>> feed({String category = ''});
  Future<bool> act(String id, String action);
  Future<bool> report(String id, String reason);

  /// Native ASKODOX message to the video's business: an approved-FAQ reply
  /// or "waiting for the owner" -- never a guessed answer.
  Future<VideoMessageResult> message(String id, String text);
  Future<({List<Map<String, Object?>> inbox, List<Map<String, Object?>> sent})> messages();
  Future<bool> reply(String messageId, String text);

  /// Deep study of the real video file; then questions answered from it only.
  Future<Map<String, Object?>> study(String id, {String language = 'en'});
  Future<Map<String, Object?>> ask(String studyRef, String question, {String language = 'en'});
}

class VideoMessageResult {
  const VideoMessageResult({required this.status, this.reply, this.error});
  final String status;
  final String? reply;
  final String? error;
}

final nativeVideoRepositoryProvider = Provider<NativeVideoRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return ApiNativeVideoRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

class ApiNativeVideoRepository implements NativeVideoRepository {
  ApiNativeVideoRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions _auth([int seconds = 30]) =>
      ApiRequestOptions(timeout: Duration(seconds: seconds), authToken: authToken);

  List<NativeVideo> _list(ApiResult<Map<String, Object?>> r) => [
        if (r is ApiSuccess<Map<String, Object?>>)
          for (final v in (r.data['items'] as List? ?? const []))
            if (v is Map) NativeVideo.fromJson(Map<String, Object?>.from(v)),
      ];

  /// Null on success, otherwise the backend's reason.
  @override
  Future<String?> upload({required List<int> bytes, required String fileName, required String title,
      String caption = '', String category = '', String products = '', bool asBusiness = false,
      bool submit = true}) async {
    final query = Uri(queryParameters: {
      'title': title,
      if (caption.isNotEmpty) 'caption': caption,
      if (category.isNotEmpty) 'category': category,
      if (products.isNotEmpty) 'products': products,
      'as_business': asBusiness ? 'true' : 'false',
      'submit': submit ? 'true' : 'false',
    }).query;
    final result = await _client.upload('/api/videos/upload?$query',
        bytes: bytes, fileName: fileName, options: _auth(180));
    return switch (result) {
      ApiSuccess() => null,
      ApiError(:final failure) => failure.message ?? 'Upload failed',
    };
  }

  @override
  Future<List<NativeVideo>> mine() async =>
      _list(await _client.get<Map<String, Object?>>('/api/merchant/videos', options: _auth()));

  @override
  Future<List<NativeVideo>> feed({String category = ''}) async => _list(await _client.get<Map<String, Object?>>(
      '/api/videos/feed${category.isEmpty ? '' : '?category=${Uri.encodeQueryComponent(category)}'}'));

  @override
  Future<bool> act(String id, String action) async =>
      (await _client.post<Map<String, Object?>>('/api/videos/mine/$id/$action', options: _auth())) is ApiSuccess;

  @override
  Future<bool> report(String id, String reason) async => (await _client.post<Map<String, Object?>>(
      '/api/videos/$id/report', body: {'reason': reason}, options: _auth())) is ApiSuccess;

  @override
  Future<VideoMessageResult> message(String id, String text) async {
    final r = await _client.post<Map<String, Object?>>('/api/videos/$id/message', body: {'text': text}, options: _auth());
    return switch (r) {
      ApiSuccess(:final data) => VideoMessageResult(status: '${data['status'] ?? ''}', reply: data['reply'] as String?),
      ApiError(:final failure) => VideoMessageResult(status: 'ERROR', error: failure.message),
    };
  }

  @override
  Future<({List<Map<String, Object?>> inbox, List<Map<String, Object?>> sent})> messages() async {
    final r = await _client.get<Map<String, Object?>>('/api/videos/mine/messages', options: _auth());
    List<Map<String, Object?>> rows(Object? v) => [for (final m in (v as List? ?? const [])) if (m is Map) Map<String, Object?>.from(m)];
    return r is ApiSuccess<Map<String, Object?>>
        ? (inbox: rows(r.data['inbox']), sent: rows(r.data['sent']))
        : (inbox: const <Map<String, Object?>>[], sent: const <Map<String, Object?>>[]);
  }

  @override
  Future<bool> reply(String messageId, String text) async => (await _client.post<Map<String, Object?>>(
      '/api/videos/messages/$messageId/reply', body: {'text': text}, options: _auth())) is ApiSuccess;

  @override
  Future<Map<String, Object?>> study(String id, {String language = 'en'}) async {
    final r = await _client.post<Map<String, Object?>>('/api/videos/native/$id/study',
        body: {'language': language}, options: _auth(120));
    return r is ApiSuccess<Map<String, Object?>> ? r.data : const {'status': 'unavailable'};
  }

  @override
  Future<Map<String, Object?>> ask(String studyRef, String question, {String language = 'en'}) async {
    final r = await _client.post<Map<String, Object?>>('/api/videos/$studyRef/ask',
        body: {'question': question, 'language': language}, options: _auth(60));
    return r is ApiSuccess<Map<String, Object?>> ? r.data : const {'found': false};
  }
}

class NativeVideoScreen extends ConsumerStatefulWidget {
  const NativeVideoScreen({super.key});

  @override
  ConsumerState<NativeVideoScreen> createState() => _NativeVideoScreenState();
}

class _NativeVideoScreenState extends ConsumerState<NativeVideoScreen> {
  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String te) => _te ? te : en;
  final _title = TextEditingController();
  final _caption = TextEditingController();
  final _category = TextEditingController();
  final _products = TextEditingController();
  bool _asBusiness = true;
  bool _busy = false;
  List<int>? _bytes;
  String _fileName = '';
  List<NativeVideo> _mine = const [];
  List<NativeVideo> _feed = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _caption, _category, _products]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(nativeVideoRepositoryProvider);
    final signedIn = ref.read(authSessionProvider).user != null;
    final mine = signedIn ? await repo.mine() : const <NativeVideo>[];
    final feed = await repo.feed();
    if (mounted) {
      setState(() {
        _mine = mine;
        _feed = feed;
      });
    }
  }

  Future<void> _pick(String source) async {
    final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _bytes = picked.first.bytes;
      _fileName = picked.first.name;
    });
  }

  Future<void> _upload({required bool submit}) async {
    if (_bytes == null || _title.text.trim().isEmpty) {
      _say(t('Choose a video and give it a title.', 'వీడియో ఎంచుకుని టైటిల్ ఇవ్వండి.'));
      return;
    }
    setState(() => _busy = true);
    final error = await ref.read(nativeVideoRepositoryProvider).upload(
        bytes: _bytes!, fileName: _fileName.isEmpty ? 'video.mp4' : _fileName, title: _title.text.trim(),
        caption: _caption.text.trim(), category: _category.text.trim(), products: _products.text.trim(),
        asBusiness: _asBusiness, submit: submit);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _bytes = null;
        _title.clear();
        _caption.clear();
      }
    });
    _say(error ??
        (submit
            ? t('Uploaded. ASKODOX staff review it before it is published.', 'అప్‌లోడ్ అయింది. స్టాఫ్ రివ్యూ తర్వాత పబ్లిష్ అవుతుంది.')
            : t('Saved as a draft.', 'డ్రాఫ్ట్‌గా సేవ్ చేశాం.')));
    _load();
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _actionLabel(String action) => switch (action) {
        'submit' => t('Submit for review', 'రివ్యూకు పంపండి'),
        'pause' => t('Pause', 'ఆపండి'),
        'resume' => t('Resume (re-review)', 'మళ్లీ ప్రారంభించండి'),
        'remove' => t('Remove', 'తీసివేయండి'),
        _ => action,
      };

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authSessionProvider).user != null;
    return Scaffold(
      appBar: AppBar(title: Text(t('ASKODOX videos', 'ASKODOX వీడియోలు'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!signedIn)
            Card(
                child: ListTile(
                    title: Text(t('Sign in to publish your own videos.', 'మీ వీడియోలు పబ్లిష్ చేయడానికి సైన్ ఇన్ చేయండి.')),
                    trailing: TextButton(
                        onPressed: () => context.push('/onboarding?signin=1'), child: Text(t('Sign in', 'సైన్ ఇన్')))))
          else ...[
            Text(t('Publish a video', 'వీడియో పబ్లిష్ చేయండి'), style: Theme.of(context).textTheme.titleMedium),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('video-pick-gallery'),
                  onPressed: () => _pick('video'),
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(t('Choose video', 'వీడియో ఎంచుకోండి'))),
            ]),
            if (_bytes != null)
              Text('${_fileName.isEmpty ? 'video' : _fileName} · ${(_bytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB',
                  key: const ValueKey('video-picked')),
            TextField(key: const ValueKey('video-title'), controller: _title, maxLength: 140,
                decoration: InputDecoration(labelText: t('Title', 'టైటిల్'))),
            TextField(controller: _caption, maxLines: 3, decoration: InputDecoration(labelText: t('Caption', 'క్యాప్షన్'))),
            TextField(controller: _category, decoration: InputDecoration(labelText: t('Category (e.g. kitchen)', 'కేటగిరీ'))),
            TextField(controller: _products,
                decoration: InputDecoration(labelText: t('Products shown (comma separated)', 'చూపిన ప్రొడక్ట్స్'))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _asBusiness,
                onChanged: (v) => setState(() => _asBusiness = v),
                title: Text(t('This is my business\'s video', 'ఇది నా వ్యాపార వీడియో'))),
            Wrap(spacing: 8, children: [
              FilledButton(
                  key: const ValueKey('video-upload'),
                  onPressed: _busy ? null : () => _upload(submit: true),
                  child: Text(_busy ? t('Uploading…', 'అప్‌లోడ్ అవుతోంది…') : t('Upload for review', 'రివ్యూకు అప్‌లోడ్'))),
              OutlinedButton(onPressed: _busy ? null : () => _upload(submit: false), child: Text(t('Save draft', 'డ్రాఫ్ట్'))),
            ]),
            const Divider(height: 32),
            Row(children: [
              Expanded(child: Text(t('My videos', 'నా వీడియోలు'), style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                  key: const ValueKey('video-messages'),
                  onPressed: () => showModalBottomSheet<void>(
                      context: context, isScrollControlled: true, builder: (_) => _VideoInbox(te: _te)),
                  icon: const Icon(Icons.forum_outlined),
                  label: Text(t('Messages', 'సందేశాలు'))),
            ]),
            if (_mine.isEmpty) Text(t('No videos yet.', 'ఇంకా వీడియోలు లేవు.')),
            for (final v in _mine)
              Card(
                key: ValueKey('my-video-${v.id}'),
                child: ListTile(
                  title: Text(v.title),
                  subtitle: Text(askodoxVideoStatusText(v.status, _te)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) async {
                      await ref.read(nativeVideoRepositoryProvider).act(v.id, a);
                      _load();
                    },
                    itemBuilder: (_) => [
                      for (final a in askodoxVideoOwnerActions(v.status)) PopupMenuItem(value: a, child: Text(_actionLabel(a))),
                    ],
                  ),
                ),
              ),
          ],
          const Divider(height: 32),
          Text(t('Published on ASKODOX', 'ASKODOX లో పబ్లిష్ అయినవి'), style: Theme.of(context).textTheme.titleMedium),
          if (_feed.isEmpty) Text(t('No ASKODOX videos are published yet.', 'ఇంకా ASKODOX వీడియోలు పబ్లిష్ కాలేదు.')),
          for (final v in _feed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(v.title),
                subtitle: Text([v.label, v.caption].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: v.url.isEmpty
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NativeReelsScreen(videos: _feed, initialIndex: _feed.indexOf(v)))),
                trailing: signedIn
                    ? IconButton(
                        tooltip: t('Report', 'రిపోర్ట్'),
                        icon: const Icon(Icons.flag_outlined),
                        onPressed: () async {
                          final ok = await ref.read(nativeVideoRepositoryProvider).report(v.id, 'Reported from the app');
                          if (context.mounted) _say(ok ? t('Reported to staff.', 'స్టాఫ్‌కు రిపోర్ట్ చేశాం.') : t('Could not report.', 'రిపోర్ట్ కాలేదు.'));
                        })
                    : null,
              ),
            ),
        ]),
      ),
    );
  }
}

/// The playing surface of one reel. Injectable so tests (and devices
/// without a codec) never depend on a real player.
typedef AskodoxVideoSurface = Widget Function(BuildContext context, NativeVideo video, bool active);

final askodoxVideoSurfaceProvider = Provider<AskodoxVideoSurface>((ref) =>
    (context, video, active) => _NetworkVideo(key: ValueKey('reel-player-${video.id}'), url: video.url, active: active));

class _NetworkVideo extends StatefulWidget {
  const _NetworkVideo({super.key, required this.url, required this.active});
  final String url;
  final bool active;

  @override
  State<_NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<_NetworkVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      _failed = true;
      return;
    }
    _controller = VideoPlayerController.networkUrl(uri)
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        if (widget.active) _controller?.play();
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void didUpdateWidget(covariant _NetworkVideo old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    widget.active ? c.play() : c.pause();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) return const Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48));
    if (c == null || !c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
    );
  }
}

/// ASKODOX reels: published ASKODOX videos, one per screen, swipe up/down.
/// Ask the business (approved answers only), "What's in this video?"
/// (answered only from the analysed video), report.
class NativeReelsScreen extends ConsumerStatefulWidget {
  const NativeReelsScreen({super.key, required this.videos, this.initialIndex = 0});
  final List<NativeVideo> videos;
  final int initialIndex;

  @override
  ConsumerState<NativeReelsScreen> createState() => _NativeReelsScreenState();
}

class _NativeReelsScreenState extends ConsumerState<NativeReelsScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex.clamp(0, widget.videos.length - 1));
  late int _current = widget.initialIndex.clamp(0, widget.videos.length - 1);

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String te) => _te ? te : en;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));

  Future<void> _ask(NativeVideo v) async {
    if (ref.read(authSessionProvider).user == null) {
      context.push('/onboarding?signin=1');
      return;
    }
    final text = await _prompt(t('Ask the business', 'వ్యాపారాన్ని అడగండి'));
    if (text == null || !mounted) return;
    final r = await ref.read(nativeVideoRepositoryProvider).message(v.id, text);
    if (!mounted) return;
    _say(switch (r.status) {
      'AUTO_ANSWERED' => '${t('Auto-reply', 'ఆటో-రిప్లై')}: ${r.reply ?? ''}',
      'WAITING_FOR_OWNER' => t('Sent. The business will reply in My videos → Messages.',
          'పంపాం. వ్యాపారి జవాబు నా వీడియోలు → సందేశాలు లో వస్తుంది.'),
      _ => r.error ?? t('Could not send.', 'పంపలేకపోయాం.'),
    });
  }

  Future<void> _study(NativeVideo v) async {
    final lang = _te ? 'te' : 'en';
    final repo = ref.read(nativeVideoRepositoryProvider);
    final s = await repo.study(v.id, language: lang);
    if (!mounted) return;
    if (s['status'] != 'ready') {
      _say('${s['message'] ?? t('This video could not be studied right now.', 'ఈ వీడియోను ఇప్పుడు చదవలేకపోయాం.')}');
      return;
    }
    final question = await _prompt(t('Ask about this video', 'ఈ వీడియో గురించి అడగండి'),
        hint: [for (final q in (s['suggested_questions'] as List? ?? const [])) '$q'].take(2).join(' · '));
    if (question == null || !mounted) return;
    final a = await repo.ask('${s['ref']}', question, language: lang);
    if (!mounted) return;
    _say(a['found'] == true
        ? '${a['answer']}'
        : '${a['answer'] ?? t('Not in this video.', 'ఈ వీడియోలో లేదు.')}');
  }

  Future<String?> _prompt(String title, {String hint = ''}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            key: const ValueKey('reel-prompt'),
            controller: controller,
            autofocus: true,
            maxLength: 500,
            decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'రద్దు'))),
          FilledButton(
              key: const ValueKey('reel-prompt-send'),
              onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()),
              child: Text(t('Send', 'పంపండి'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = ref.watch(askodoxVideoSurfaceProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white,
          title: Text(t('ASKODOX videos', 'ASKODOX వీడియోలు'))),
      body: PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: widget.videos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) {
          final v = widget.videos[i];
          return Stack(fit: StackFit.expand, children: [
            surface(context, v, i == _current),
            Positioned(
              left: 16,
              right: 80,
              bottom: 24,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (v.label.isNotEmpty)
                  Text(v.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(v.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                if (v.caption.isNotEmpty)
                  Text(v.caption, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
            Positioned(
              right: 8,
              bottom: 24,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    key: ValueKey('reel-ask-${v.id}'),
                    tooltip: t('Ask the business', 'వ్యాపారాన్ని అడగండి'),
                    color: Colors.white,
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => _ask(v)),
                IconButton(
                    key: ValueKey('reel-study-${v.id}'),
                    tooltip: t("What's in this video?", 'ఈ వీడియోలో ఏముంది?'),
                    color: Colors.white,
                    icon: const Icon(Icons.manage_search),
                    onPressed: () => _study(v)),
                IconButton(
                    tooltip: t('Report', 'రిపోర్ట్'),
                    color: Colors.white,
                    icon: const Icon(Icons.flag_outlined),
                    onPressed: () async {
                      final ok = await ref.read(nativeVideoRepositoryProvider).report(v.id, 'Reported from reels');
                      if (mounted) _say(ok ? t('Reported to staff.', 'స్టాఫ్‌కు రిపోర్ట్ చేశాం.') : t('Could not report.', 'రిపోర్ట్ కాలేదు.'));
                    }),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

/// Owner inbox for questions about my videos (+ what I asked others).
class _VideoInbox extends ConsumerStatefulWidget {
  const _VideoInbox({required this.te});
  final bool te;

  @override
  ConsumerState<_VideoInbox> createState() => _VideoInboxState();
}

class _VideoInboxState extends ConsumerState<_VideoInbox> {
  ({List<Map<String, Object?>> inbox, List<Map<String, Object?>> sent})? _data;
  String t(String en, String te) => widget.te ? te : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await ref.read(nativeVideoRepositoryProvider).messages();
    if (mounted) setState(() => _data = d);
  }

  Future<void> _reply(String id) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(t('Reply', 'జవాబు')),
              content: TextField(controller: controller, maxLength: 1000, autofocus: true),
              actions: [
                FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(t('Send', 'పంపండి'))),
              ],
            ));
    if (text == null || text.isEmpty) return;
    await ref.read(nativeVideoRepositoryProvider).reply(id, text);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: d == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text(t('Questions about my videos', 'నా వీడియోలపై ప్రశ్నలు'), style: Theme.of(context).textTheme.titleMedium),
                if (d.inbox.isEmpty) Text(t('No questions yet.', 'ఇంకా ప్రశ్నలు లేవు.')),
                for (final m in d.inbox)
                  ListTile(
                    title: Text('${m['text']}'),
                    subtitle: Text(m['reply'] == null ? t('Waiting for your reply', 'మీ జవాబు కోసం') : '${m['reply']}'),
                    trailing: m['status'] == 'WAITING_FOR_OWNER'
                        ? TextButton(onPressed: () => _reply('${m['id']}'), child: Text(t('Reply', 'జవాబు')))
                        : null,
                  ),
                const Divider(),
                Text(t('My questions', 'నా ప్రశ్నలు'), style: Theme.of(context).textTheme.titleMedium),
                for (final m in d.sent)
                  ListTile(
                      title: Text('${m['text']}'),
                      subtitle: Text(m['reply'] == null ? t('Waiting for the business', 'వ్యాపారి జవాబు కోసం') : '${m['reply']}')),
              ]),
      ),
    );
  }
}
