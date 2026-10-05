import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';
import '../home/application/conversation_archive.dart';
import 'native_video.dart';

/// Registered-video commerce on top of the backend's `/api/videos/...`
/// (video_commerce.py): owner details + review status, metadata suggested
/// only from what the video shows, linked listings, comments / questions with
/// AI replies under the seller's control, pre-orders, sharing through the
/// Android share sheet, and demand analytics.
class VideoCommerceRepository {
  VideoCommerceRepository(this._client, this._token);
  final ApiClient _client;
  final String? _token;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: _token);

  Map<String, Object?> _data(ApiResult<Map<String, Object?>> r) => r is ApiSuccess<Map<String, Object?>> ? r.data : {};
  List<Map<String, Object?>> _items(Map<String, Object?> d, [String key = 'items']) => [
        for (final i in (d[key] as List? ?? const []))
          if (i is Map) Map<String, Object?>.from(i),
      ];
  String? _error(ApiResult<Map<String, Object?>> r) =>
      r is ApiError<Map<String, Object?>> ? (r.failure.message ?? 'Could not complete that.') : null;

  Future<Map<String, Object?>> detail(String id) async =>
      _data(await _client.get<Map<String, Object?>>('/api/videos/native/$id', options: _auth));

  Future<Map<String, Object?>> suggest(String id) async => _data(await _client.post<Map<String, Object?>>(
      '/api/videos/native/$id/suggest',
      options: ApiRequestOptions(authToken: _token, timeout: const Duration(seconds: 120))));

  Future<({Map<String, Object?> data, String? error})> edit(String id, Map<String, Object?> fields) async {
    final r = await _client.patch<Map<String, Object?>>('/api/videos/mine/$id', body: fields, options: _auth);
    return (data: _data(r), error: _error(r));
  }

  Future<List<Map<String, Object?>>> comments(String id) async =>
      _items(_data(await _client.get<Map<String, Object?>>('/api/videos/$id/comments', options: _auth)));

  Future<({Map<String, Object?> data, String? error})> comment(String id, String text,
      {String kind = 'question', String language = 'en'}) async {
    final r = await _client.post<Map<String, Object?>>('/api/videos/$id/comments',
        body: {'text': text, 'kind': kind, 'language': language}, options: _auth);
    return (data: _data(r), error: _error(r));
  }

  Future<({Map<String, Object?> data, String? error})> preorder(String id,
      {double quantity = 1, String variant = '', String note = '', String listingId = ''}) async {
    final r = await _client.post<Map<String, Object?>>('/api/videos/$id/preorder',
        body: {'quantity': quantity, 'variant': variant, 'note': note, 'listing_id': listingId}, options: _auth);
    return (data: _data(r), error: _error(r));
  }

  Future<void> event(String id, String kind, {String area = ''}) async {
    await _client.post<Map<String, Object?>>('/api/videos/$id/event', body: {'kind': kind, 'area': area});
  }

  Future<Map<String, Object?>> share(String id) async =>
      _data(await _client.get<Map<String, Object?>>('/api/videos/$id/share'));

  Future<Map<String, Object?>> aiSettings() async =>
      _data(await _client.get<Map<String, Object?>>('/api/videos/ai-settings', options: _auth));

  Future<Map<String, Object?>> saveAiSettings(String mode, bool paused) async => _data(await _client
      .put<Map<String, Object?>>('/api/videos/ai-settings', body: {'mode': mode, 'paused': paused}, options: _auth));

  Future<Map<String, Object?>> inbox() async =>
      _data(await _client.get<Map<String, Object?>>('/api/videos/mine/inbox', options: _auth));

  Future<bool> reply(String commentId, String text) async => (await _client.post<Map<String, Object?>>(
      '/api/videos/comments/$commentId/reply', body: {'text': text}, options: _auth)) is ApiSuccess;

  Future<bool> approve(String commentId) async => (await _client.post<Map<String, Object?>>(
      '/api/videos/comments/$commentId/approve', options: _auth)) is ApiSuccess;

  Future<Map<String, Object?>> decide(String preorderId, bool accept) async => _data(await _client
      .post<Map<String, Object?>>('/api/videos/preorders/$preorderId/decide', body: {'accept': accept}, options: _auth));

  Future<Map<String, Object?>> analytics(String id) async =>
      _data(await _client.get<Map<String, Object?>>('/api/videos/mine/$id/analytics', options: _auth));
}

final videoCommerceRepositoryProvider = Provider<VideoCommerceRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return VideoCommerceRepository(ref.watch(apiClientProvider), session.user == null ? null : session.tokenPlaceholder);
});

/// The Android share sheet (the user chooses where; ASKODOX never posts).
typedef AskodoxShareText = Future<bool> Function(String text, {String subject});

final askodoxShareTextProvider = Provider<AskodoxShareText>((ref) => (text, {subject = ''}) async {
      try {
        return await const MethodChannel('com.askodox.app/device')
                .invokeMethod<bool>('shareText', {'text': text, 'subject': subject, 'title': 'Share'}) ??
            false;
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: text));
        return false;
      }
    });

/// Status words the seller sees. `processing` = ASKODOX is analysing the
/// video right now (client-side, while suggestions are being made).
String askodoxVideoLifecycleLabel(String status, bool te, {bool processing = false}) {
  if (processing) return te ? 'ప్రాసెస్ అవుతోంది' : 'Processing';
  return switch (status) {
    'DRAFT' => te ? 'డ్రాఫ్ట్' : 'Draft',
    'PENDING_REVIEW' => te ? 'రివ్యూ కోసం వేచి ఉంది' : 'Waiting for review',
    'ACTIVE' => te ? 'ఆమోదించారు · పబ్లిష్ అయింది' : 'Approved · Published',
    'PAUSED' => te ? 'ఆపబడింది' : 'Paused',
    'REJECTED' => te ? 'తిరస్కరించారు' : 'Rejected',
    _ => status,
  };
}

/// "Ask about this video" from anywhere: Main Chat opens with THIS video as
/// the context; questions are answered from its study / listing only.
void askodoxAskAboutVideoInChat(WidgetRef ref, BuildContext context, NativeVideo video) {
  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.aboutVideo('nv_${video.id}', video.title);
  context.go('/');
}

/// Owner view of ONE of my videos: status + where it appears, preview,
/// details suggested from the video (editable), listings, pre-orders,
/// sharing, questions and demand.
class MyVideoDetailScreen extends ConsumerStatefulWidget {
  const MyVideoDetailScreen({super.key, required this.video});
  final NativeVideo video;

  @override
  ConsumerState<MyVideoDetailScreen> createState() => _MyVideoDetailScreenState();
}

class _MyVideoDetailScreenState extends ConsumerState<MyVideoDetailScreen> {
  final _title = TextEditingController();
  final _caption = TextEditingController();
  final _category = TextEditingController();
  final _tags = TextEditingController();
  final _listings = TextEditingController();
  final _preDate = TextEditingController();
  final _prePrice = TextEditingController();
  Map<String, Object?> _detail = const {};
  Map<String, Object?> _stats = const {};
  List<Map<String, Object?>> _comments = const [];
  Map<String, Object?>? _suggested;
  bool _processing = false;
  bool _saving = false;
  bool _preorder = false;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String te) => _te ? te : en;
  String get _status => '${_detail['status'] ?? widget.video.status}';

  @override
  void initState() {
    super.initState();
    _title.text = widget.video.title;
    _caption.text = widget.video.caption;
    _category.text = widget.video.categories.join(', ');
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _caption, _category, _tags, _listings, _preDate, _prePrice]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(videoCommerceRepositoryProvider);
    final detail = await repo.detail(widget.video.id);
    final stats = await repo.analytics(widget.video.id);
    final comments = await repo.comments(widget.video.id);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _stats = stats;
      _comments = comments;
      final pre = (detail['preorder'] as Map?) ?? const {};
      _preorder = pre['enabled'] == true;
      _preDate.text = '${pre['available_date'] ?? ''}'.replaceAll('null', '');
      _prePrice.text = pre['expected_price'] == null ? '' : '${pre['expected_price']}';
      _tags.text = [for (final x in (detail['tags'] as List? ?? const [])) '$x'].join(', ');
      _listings.text = [for (final l in (detail['listings'] as List? ?? const [])) if (l is Map) '${l['id']}'].join(', ');
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _suggest() async {
    setState(() => _processing = true);
    final r = await ref.read(videoCommerceRepositoryProvider).suggest(widget.video.id);
    if (!mounted) return;
    setState(() => _processing = false);
    if (r['status'] != 'ready') {
      _say('${r['message'] ?? t('The video could not be analysed; fill the details yourself.', 'వీడియో విశ్లేషణ కాలేదు; వివరాలు మీరే నింపండి.')}');
      return;
    }
    final s = Map<String, Object?>.from((r['suggestions'] as Map?) ?? const {});
    setState(() {
      _suggested = s;
      // Prefilled for review -- never saved until the seller saves.
      if (s['title'] != null) _title.text = '${s['title']}';
      if (s['caption'] != null) _caption.text = '${s['caption']}';
      if (s['subcategory'] != null || s['category'] != null) _category.text = '${s['subcategory'] ?? s['category']}';
      if (s['tags'] is List) _tags.text = [for (final x in s['tags'] as List) '$x'].join(', ');
    });
  }

  List<String> _split(String text) => [for (final p in text.split(',')) if (p.trim().isNotEmpty) p.trim()];

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await ref.read(videoCommerceRepositoryProvider).edit(widget.video.id, {
      'title': _title.text.trim(),
      'caption': _caption.text.trim(),
      'category': _category.text.trim(),
      'tags': _split(_tags.text),
      'listing_ids': _split(_listings.text),
      'preorder_enabled': _preorder,
      if (_preDate.text.trim().isNotEmpty) 'preorder_date': _preDate.text.trim(),
      if (double.tryParse(_prePrice.text.trim()) != null) 'preorder_price': double.parse(_prePrice.text.trim()),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.error != null) {
      _say(r.error!);
      return;
    }
    _say(r.data['returned_to_review'] == true
        ? t('Saved. Changed details go back to staff review before they show again.',
            'సేవ్ అయింది. మార్చిన వివరాలు మళ్లీ రివ్యూ తర్వాత కనిపిస్తాయి.')
        : t('Saved.', 'సేవ్ అయింది.'));
    _load();
  }

  Future<void> _share() async {
    final s = await ref.read(videoCommerceRepositoryProvider).share(widget.video.id);
    final text = '${s['text'] ?? ''}';
    if (text.isEmpty) {
      _say(t('Only published videos can be shared.', 'పబ్లిష్ అయిన వీడియోలు మాత్రమే షేర్ చేయవచ్చు.'));
      return;
    }
    await ref.read(videoCommerceRepositoryProvider).event(widget.video.id, 'share');
    final shared = await ref.read(askodoxShareTextProvider)(text, subject: widget.video.title);
    if (!shared && mounted) _say(t('Link copied.', 'లింక్ కాపీ అయింది.'));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final visible = [for (final v in (_detail['visible_in'] as List? ?? const [])) '$v'];
    final top = [for (final q in (_stats['top_questions'] as List? ?? const [])) if (q is Map) q];
    final areas = [for (final a in (_stats['demand_by_area'] as List? ?? const [])) if (a is Map) a];
    return Scaffold(
      appBar: AppBar(title: Text(t('My video', 'నా వీడియో'))),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              Chip(
                  key: const ValueKey('video-status'),
                  label: Text(askodoxVideoLifecycleLabel(_status, te, processing: _processing))),
              const Spacer(),
              TextButton.icon(
                  key: const ValueKey('video-preview'),
                  onPressed: widget.video.url.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => NativeReelsScreen(videos: [widget.video]))),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(_status == 'ACTIVE' ? t('View published', 'పబ్లిష్ అయినది చూడండి') : t('Preview', 'ప్రివ్యూ'))),
            ]),
            Text(t('Where it appears', 'ఎక్కడ కనిపిస్తుంది'), style: Theme.of(context).textTheme.titleSmall),
            if (visible.isEmpty)
              Text(t('Not visible to customers yet (only published videos appear).',
                  'ఇంకా కస్టమర్లకు కనిపించదు (పబ్లిష్ అయినవి మాత్రమే).'), key: const ValueKey('video-not-visible'))
            else
              for (final v in visible) Text('• $v'),
            const Divider(height: 24),
            Row(children: [
              Expanded(child: Text(t('Details', 'వివరాలు'), style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                  key: const ValueKey('video-suggest'),
                  onPressed: _processing ? null : _suggest,
                  icon: _processing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(t('Suggest from the video', 'వీడియో నుంచి సూచించండి'))),
            ]),
            if (_suggested != null) _SuggestionNote(suggested: _suggested!, te: te),
            TextField(key: const ValueKey('video-edit-title'), controller: _title, maxLength: 140,
                decoration: InputDecoration(labelText: t('Title', 'టైటిల్'))),
            TextField(controller: _caption, maxLines: 3, maxLength: 2000,
                decoration: InputDecoration(labelText: t('Caption', 'క్యాప్షన్'))),
            TextField(key: const ValueKey('video-edit-category'), controller: _category,
                decoration: InputDecoration(labelText: t('Category', 'కేటగిరీ'))),
            TextField(controller: _tags, decoration: InputDecoration(labelText: t('Tags (comma separated)', 'ట్యాగ్స్'))),
            TextField(
                key: const ValueKey('video-edit-listings'),
                controller: _listings,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: t('My listing numbers shown in this video', 'ఈ వీడియోలో చూపిన నా లిస్టింగ్ నంబర్లు'),
                    helperText: t('Links the video to your product, price and stock.',
                        'వీడియోను మీ ప్రొడక్ట్, ధర, స్టాక్‌కి లింక్ చేస్తుంది.'))),
            SwitchListTile(
                key: const ValueKey('video-edit-preorder'),
                contentPadding: EdgeInsets.zero,
                value: _preorder,
                onChanged: (v) => setState(() => _preorder = v),
                title: Text(t('Take pre-orders from this video', 'ఈ వీడియో నుంచి ప్రీ-ఆర్డర్లు తీసుకోండి'))),
            if (_preorder)
              Row(children: [
                Expanded(
                    child: TextField(controller: _preDate,
                        decoration: InputDecoration(labelText: t('Available from (YYYY-MM-DD)', 'అందుబాటు తేదీ')))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(controller: _prePrice, keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t('Expected price ₹', 'అంచనా ధర ₹')))),
              ]),
            const SizedBox(height: 8),
            FilledButton.icon(
                key: const ValueKey('video-save'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(t('Save details', 'వివరాలు సేవ్ చేయండి'))),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                key: const ValueKey('video-share'),
                onPressed: _status == 'ACTIVE' ? _share : null,
                icon: const Icon(Icons.share_outlined),
                label: Text(t('Share (you choose where)', 'షేర్ (మీరే ఎంచుకోండి)'))),
            const Divider(height: 24),
            Text(t('Demand', 'డిమాండ్'), style: Theme.of(context).textTheme.titleSmall),
            Wrap(key: const ValueKey('video-analytics'), spacing: 12, runSpacing: 4, children: [
              Text('${t('Views', 'వ్యూస్')}: ${_stats['views'] ?? 0}'),
              Text('${t('Questions', 'ప్రశ్నలు')}: ${_stats['questions'] ?? 0}'),
              Text('${t('Unanswered', 'జవాబు లేనివి')}: ${_stats['unanswered'] ?? 0}'),
              Text('${t('AI answered', 'AI జవాబు')}: ${_stats['ai_answered'] ?? 0}'),
              Text('${t('Shares', 'షేర్లు')}: ${_stats['shares'] ?? 0}'),
              Text('${t('Pre-orders', 'ప్రీ-ఆర్డర్లు')}: ${_stats['pre_orders'] ?? 0}'),
            ]),
            if (top.isNotEmpty) Text('${t('Top questions', 'ఎక్కువ అడిగినవి')}: ${top.map((q) => '${q['topic']} (${q['count']})').join(', ')}'),
            if (areas.isNotEmpty) Text('${t('Interest by area', 'ప్రాంతాల వారీగా')}: ${areas.map((a) => '${a['area']} (${a['count']})').join(', ')}'),
            const Divider(height: 24),
            Text(t('Questions & comments', 'ప్రశ్నలు & కామెంట్లు'), style: Theme.of(context).textTheme.titleSmall),
            if (_comments.isEmpty) Text(t('No questions yet.', 'ఇంకా ప్రశ్నలు లేవు.')),
            for (final c in _comments) _CommentTile(comment: c, te: te, owner: true, onChanged: _load),
          ],
        ),
      ),
    );
  }
}

class _SuggestionNote extends StatelessWidget {
  const _SuggestionNote({required this.suggested, required this.te});
  final Map<String, Object?> suggested;
  final bool te;

  @override
  Widget build(BuildContext context) {
    final features = [for (final f in (suggested['features'] as List? ?? const [])) '$f'];
    final missing = [for (final m in (suggested['not_established'] as List? ?? const [])) '$m'];
    return Card(
      key: const ValueKey('video-suggestions'),
      color: const Color(0xFFF2F0FF),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'వీడియోలో కనిపించిన దాని నుంచి మాత్రమే సూచించాం -- సేవ్ చేసే ముందు తనిఖీ చేయండి.'
              : 'Suggested only from what the video shows -- check before saving.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (suggested['category_path'] is List)
            Text('${te ? 'కేటగిరీ' : 'Category'}: ${(suggested['category_path'] as List).join(' › ')}'),
          if (suggested['brand'] != null) Text('${te ? 'బ్రాండ్' : 'Brand'}: ${suggested['brand']}'),
          for (final f in features) Text('• $f (${te ? 'వీడియోలో కనిపించింది' : 'seen in video'})'),
          if (missing.isNotEmpty)
            Text('${te ? 'వీడియోలో నిర్ధారించలేదు' : 'Not established in the video'}: ${missing.join(', ')}',
                style: const TextStyle(color: Color(0xFF8A5A00))),
        ]),
      ),
    );
  }
}

String _basisLabel(String? basis, bool te) => switch (basis) {
      'seen_in_video' => te ? 'వీడియోలో కనిపించింది' : 'Seen in video',
      'said_by_seller' => te ? 'సెల్లర్ చెప్పారు' : 'Said by seller',
      'listing' => te ? 'లిస్టింగ్ నుంచి' : 'From the listing',
      'askodox' => te ? 'ASKODOX గమనిక' : 'ASKODOX note',
      _ => te ? 'నిర్ధారించలేదు' : 'Not confirmed',
    };

String _replyBy(String? by, bool te) => switch (by) {
      'askodox_ai' => te ? 'ASKODOX AI జవాబు' : 'ASKODOX AI answer',
      'askodox_ai_draft' => te ? 'AI డ్రాఫ్ట్ (మీ ఆమోదం కోసం)' : 'AI draft (needs your approval)',
      'seller' => te ? 'సెల్లర్ జవాబు' : 'Seller reply',
      _ => '',
    };

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.te, this.owner = false, this.onChanged});
  final Map<String, Object?> comment;
  final bool te;
  final bool owner;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reply = comment['reply'];
    final status = '${comment['reply_status'] ?? ''}';
    final by = _replyBy(comment['reply_by'] as String?, te);
    return Card(
      key: ValueKey('video-comment-${comment['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${comment['text']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (comment['status'] == 'FLAGGED')
            Text(te ? 'స్టాఫ్ రివ్యూలో ఉంది' : 'Held for staff review', style: const TextStyle(color: Color(0xFFB54708))),
          if (reply != null && '$reply'.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('$by: $reply'),
            if (comment['basis'] != null) Text(_basisLabel(comment['basis'] as String?, te),
                style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
          ] else if (status == 'waiting_seller' || status == 'draft_pending')
            Text(te ? 'సెల్లర్ జవాబు కోసం వేచి ఉంది' : 'Waiting for the seller',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
          if (owner && (status == 'waiting_seller' || status == 'draft_pending'))
            Wrap(spacing: 8, children: [
              if (status == 'draft_pending')
                TextButton(
                    key: ValueKey('video-approve-${comment['id']}'),
                    onPressed: () async {
                      await ref.read(videoCommerceRepositoryProvider).approve('${comment['id']}');
                      onChanged?.call();
                    },
                    child: Text(te ? 'AI జవాబు ఆమోదించండి' : 'Approve AI answer')),
              TextButton(
                  key: ValueKey('video-reply-${comment['id']}'),
                  onPressed: () async {
                    final text = await askodoxPromptText(context, te ? 'మీ జవాబు' : 'Your reply',
                        initial: status == 'draft_pending' ? '${reply ?? ''}' : '');
                    if (text == null) return;
                    await ref.read(videoCommerceRepositoryProvider).reply('${comment['id']}', text);
                    onChanged?.call();
                  },
                  child: Text(status == 'draft_pending' ? (te ? 'మార్చి పంపండి' : 'Edit & send') : (te ? 'జవాబు' : 'Reply'))),
            ]),
        ]),
      ),
    );
  }
}

Future<String?> askodoxPromptText(BuildContext context, String title, {String initial = '', String hint = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const ValueKey('prompt-text'), controller: controller, autofocus: true, maxLength: 1000,
          minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            key: const ValueKey('prompt-send'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

/// Customer side of a published video: its questions & answers (each answer
/// labelled with where it comes from), ask a question, pre-order.
class VideoQuestionsSheet extends ConsumerStatefulWidget {
  const VideoQuestionsSheet({super.key, required this.video, required this.te});
  final NativeVideo video;
  final bool te;

  @override
  ConsumerState<VideoQuestionsSheet> createState() => _VideoQuestionsSheetState();
}

class _VideoQuestionsSheetState extends ConsumerState<VideoQuestionsSheet> {
  List<Map<String, Object?>>? _items;
  Map<String, Object?> _detail = const {};
  final _text = TextEditingController();
  String? _notice;
  bool _busy = false;

  String t(String en, String te) => widget.te ? te : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(videoCommerceRepositoryProvider);
    final items = await repo.comments(widget.video.id);
    final detail = await repo.detail(widget.video.id);
    if (mounted) {
      setState(() {
        _items = items;
        _detail = detail;
      });
    }
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (ref.read(authSessionProvider).user == null) {
      context.push('/onboarding?signin=1');
      return;
    }
    setState(() => _busy = true);
    final r = await ref.read(videoCommerceRepositoryProvider).comment(widget.video.id, text,
        language: widget.te ? 'te' : 'en');
    if (!mounted) return;
    _text.clear();
    setState(() {
      _busy = false;
      _notice = r.error ?? (r.data['notice'] as String?) ??
          (r.data['reply_status'] == 'ai_answered' ? '${r.data['reply_label'] ?? ''}' : null);
    });
    _load();
  }

  Future<void> _preorder() async {
    if (ref.read(authSessionProvider).user == null) {
      context.push('/onboarding?signin=1');
      return;
    }
    final qty = await askodoxPromptText(context, t('How many?', 'ఎన్ని?'), initial: '1');
    if (qty == null || !mounted) return;
    final r = await ref.read(videoCommerceRepositoryProvider)
        .preorder(widget.video.id, quantity: double.tryParse(qty) ?? 1);
    if (!mounted) return;
    setState(() => _notice = r.error ?? '${r.data['message'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final pre = (_detail['preorder'] as Map?) ?? const {};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(children: [
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Text(t('Questions about this video', 'ఈ వీడియోపై ప్రశ్నలు'),
                          style: Theme.of(context).textTheme.titleMedium),
                      if (pre['enabled'] == true)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: OutlinedButton.icon(
                              key: const ValueKey('video-preorder'),
                              onPressed: _preorder,
                              icon: const Icon(Icons.event_available_outlined),
                              label: Text([
                                t('Pre-order', 'ప్రీ-ఆర్డర్'),
                                if (pre['available_date'] != null) '· ${pre['available_date']}',
                                if (pre['expected_price'] != null)
                                  '· ₹${pre['expected_price']}${pre['price_confirmed'] == true ? '' : t(' (expected)', ' (అంచనా)')}',
                              ].join(' '))),
                        ),
                      if (_notice != null)
                        Padding(padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_notice!, key: const ValueKey('video-question-notice'))),
                      if (items.isEmpty) Text(t('No questions yet -- ask the first one.', 'ఇంకా ప్రశ్నలు లేవు.')),
                      for (final c in items) _CommentTile(comment: c, te: widget.te),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        key: const ValueKey('video-question-field'),
                        controller: _text,
                        maxLength: 1000,
                        decoration: InputDecoration(
                            counterText: '', hintText: t('Ask about this video…', 'ఈ వీడియో గురించి అడగండి…')))),
                IconButton(
                    key: const ValueKey('video-question-send'),
                    onPressed: _busy ? null : _post,
                    icon: const Icon(Icons.send_rounded)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ONE seller inbox for video questions, AI drafts, private messages and
/// pre-orders, with the AI reply controls (off / draft / auto, pause).
class VideoSellerInboxScreen extends ConsumerStatefulWidget {
  const VideoSellerInboxScreen({super.key});

  @override
  ConsumerState<VideoSellerInboxScreen> createState() => _VideoSellerInboxScreenState();
}

class _VideoSellerInboxScreenState extends ConsumerState<VideoSellerInboxScreen> {
  Map<String, Object?>? _data;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String te) => _te ? te : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await ref.read(videoCommerceRepositoryProvider).inbox();
    if (mounted) setState(() => _data = d);
  }

  List<Map<String, Object?>> _list(String key) => [
        for (final i in ((_data ?? const {})[key] as List? ?? const []))
          if (i is Map) Map<String, Object?>.from(i),
      ];

  Future<void> _settings(String mode, bool paused) async {
    await ref.read(videoCommerceRepositoryProvider).saveAiSettings(mode, paused);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final settings = Map<String, Object?>.from(((_data ?? const {})['settings'] as Map?) ?? const {});
    final mode = '${settings['mode'] ?? 'draft'}';
    final paused = settings['paused'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(t('Video inbox', 'వీడియో ఇన్‌బాక్స్'))),
      body: _data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
                Text(t('AI replies', 'AI జవాబులు'), style: Theme.of(context).textTheme.titleSmall),
                SegmentedButton<String>(
                  key: const ValueKey('video-ai-mode'),
                  segments: [
                    ButtonSegment(value: 'off', label: Text(t('Off', 'ఆఫ్'))),
                    ButtonSegment(value: 'draft', label: Text(t('Draft', 'డ్రాఫ్ట్'))),
                    ButtonSegment(value: 'auto', label: Text(t('Auto', 'ఆటో'))),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => _settings(s.first, paused),
                ),
                Text(
                    switch (mode) {
                      'off' => t('You answer every question yourself.', 'ప్రతి ప్రశ్నకు మీరే జవాబు ఇస్తారు.'),
                      'auto' => t('AI answers only safe factual questions from your video / listing; the rest wait for you.',
                          'వీడియో / లిస్టింగ్‌లోని సురక్షిత వాస్తవ ప్రశ్నలకే AI జవాబు; మిగతావి మీ కోసం.'),
                      _ => t('AI drafts an answer; you approve, edit or replace it.',
                          'AI డ్రాఫ్ట్ రాస్తుంది; మీరు ఆమోదించండి లేదా మార్చండి.'),
                    },
                    style: const TextStyle(fontSize: 12)),
                Text(t('Never automatic: payments / refunds, legal, medical / safety, price negotiation, private details.',
                    'ఎప్పుడూ ఆటో కాదు: పేమెంట్ / రీఫండ్, లీగల్, వైద్య / భద్రత, ధర బేరం, వ్యక్తిగత వివరాలు.'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
                SwitchListTile(
                    key: const ValueKey('video-ai-pause'),
                    contentPadding: EdgeInsets.zero,
                    value: paused,
                    onChanged: (v) => _settings(mode, v),
                    title: Text(t('Pause AI (I take over)', 'AI ఆపండి (నేనే చూసుకుంటాను)'))),
                const Divider(),
                _section(t('Needs your reply', 'మీ జవాబు కావాలి'), _list('needs_me'), te),
                _section(t('AI drafts to approve', 'ఆమోదించాల్సిన AI డ్రాఫ్ట్‌లు'), _list('drafts'), te),
                Text(t('Pre-orders', 'ప్రీ-ఆర్డర్లు'), style: Theme.of(context).textTheme.titleSmall),
                if (_list('pre_orders').isEmpty) Text(t('None yet.', 'ఇంకా లేవు.')),
                for (final p in _list('pre_orders'))
                  Card(
                    key: ValueKey('video-preorder-${p['id']}'),
                    child: ListTile(
                      title: Text('${t('Qty', 'పరిమాణం')} ${p['quantity']}${p['variant'] == null ? '' : ' · ${p['variant']}'}'),
                      subtitle: Text([
                        '${p['status']}',
                        if (p['buyer_phone'] != null) '${t('Buyer', 'కొనుగోలుదారు')}: ${p['buyer_phone']}',
                      ].join(' · ')),
                      trailing: p['status'] == 'REQUESTED'
                          ? Wrap(spacing: 4, children: [
                              IconButton(
                                  key: ValueKey('video-preorder-accept-${p['id']}'),
                                  tooltip: t('Accept', 'అంగీకరించండి'),
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () async {
                                    await ref.read(videoCommerceRepositoryProvider).decide('${p['id']}', true);
                                    _load();
                                  }),
                              IconButton(
                                  tooltip: t('Decline', 'తిరస్కరించండి'),
                                  icon: const Icon(Icons.cancel_outlined),
                                  onPressed: () async {
                                    await ref.read(videoCommerceRepositoryProvider).decide('${p['id']}', false);
                                    _load();
                                  }),
                            ])
                          : null,
                    ),
                  ),
                const Divider(),
                _section(t('Answered', 'జవాబు ఇచ్చినవి'), _list('answered'), te),
              ]),
            ),
    );
  }

  Widget _section(String title, List<Map<String, Object?>> rows, bool te) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (rows.isEmpty) Text(te ? 'ఏమీ లేవు.' : 'Nothing here.'),
          for (final c in rows) _CommentTile(comment: c, te: te, owner: true, onChanged: _load),
          const SizedBox(height: 8),
        ],
      );
}
