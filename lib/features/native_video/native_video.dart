import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
            Text(t('My videos', 'నా వీడియోలు'), style: Theme.of(context).textTheme.titleMedium),
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
                onTap: v.url.isEmpty ? null : () => launchUrl(Uri.parse(v.url), mode: LaunchMode.externalApplication),
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
