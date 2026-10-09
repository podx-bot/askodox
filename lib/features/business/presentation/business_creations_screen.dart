import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// My Business -> My Creations: posts, descriptions, offer / catalogue /
/// poster text and reel scripts -- written by the owner or drafted by AI from
/// the owner's facts only. Saved here; shared only by the owner through the
/// phone's share sheet. Image / video generation are shown as not available
/// (no provider) -- never faked; video is upload-only.
class BusinessCreationsScreen extends ConsumerStatefulWidget {
  const BusinessCreationsScreen({super.key});

  @override
  ConsumerState<BusinessCreationsScreen> createState() => _BusinessCreationsScreenState();
}

const askodoxCreationKinds = ['post', 'description', 'offer_text', 'catalogue_text', 'poster_text', 'reel_script'];

String askodoxCreationKindLabel(String kind, bool te) => switch (kind) {
      'post' => te ? 'పోస్ట్' : 'Post',
      'description' => te ? 'వివరణ' : 'Description',
      'offer_text' => te ? 'ఆఫర్ టెక్స్ట్' : 'Offer text',
      'catalogue_text' => te ? 'క్యాటలాగ్' : 'Catalogue text',
      'poster_text' => te ? 'పోస్టర్ పదాలు' : 'Poster text',
      'reel_script' => te ? 'రీల్ స్క్రిప్ట్' : 'Reel script',
      _ => kind,
    };

class _BusinessCreationsScreenState extends ConsumerState<BusinessCreationsScreen> {
  static const _device = MethodChannel('com.askodox.app/device');
  bool _loading = true;
  bool _error = false;
  List<Map<String, Object?>> _items = [];
  Map<String, Object?> _caps = {};

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: ref.read(authSessionProvider).tokenPlaceholder);
  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final r = await ref.read(apiClientProvider).get<Map<String, Object?>>('/api/business/creations', options: _auth);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r is! ApiSuccess<Map<String, Object?>>;
      if (r is ApiSuccess<Map<String, Object?>>) {
        _items = [for (final i in (r.data['items'] as List?) ?? const []) if (i is Map) Map<String, Object?>.from(i)];
        _caps = Map<String, Object?>.from((r.data['capabilities'] as Map?) ?? const {});
      }
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _status(String key) => '${(_caps[key] as Map?)?['status'] ?? 'NOT_AVAILABLE'}';
  String _reason(String key) => '${(_caps[key] as Map?)?['reason'] ?? ''}';

  Future<void> _compose({required bool ai}) async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Composer(ai: ai, te: _te, draft: (kind, about) async {
        final r = await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/business/creations/draft',
            body: {'kind': kind, 'about': about, 'language': _te ? 'te' : 'en'}, options: _auth);
        return r is ApiSuccess<Map<String, Object?>> ? '${r.data['text'] ?? ''}' : null;
      }),
    );
    if (result == null) return;
    final r = await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/business/creations',
        body: result, options: _auth);
    if (!mounted) return;
    _say(r is ApiSuccess ? _t('Saved to My Creations.', 'నా సృష్టిలో సేవ్ అయింది.') : _t('Could not save.', 'సేవ్ కాలేదు.'));
    await _load();
  }

  Future<void> _edit(Map<String, Object?> item) async {
    final controller = TextEditingController(text: '${item['body'] ?? ''}');
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: TextField(
            key: const Key('askodoxCreationEditField'), controller: controller, maxLines: 8, minLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(_t('Cancel', 'రద్దు'))),
          TextButton(
              key: const Key('askodoxCreationEditSave'),
              onPressed: () => Navigator.pop(dialog, controller.text),
              child: Text(_t('Save', 'సేవ్'))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    await ref.read(apiClientProvider).patch<Map<String, Object?>>('/api/business/creations/${item['id']}',
        body: {'body': text.trim(), 'status': 'saved'}, options: _auth);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final aiReady = _status('text_drafts') == 'READY';
    return Scaffold(
      appBar: AppBar(title: Text(_t('My creations', 'నా సృష్టి'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: TextButton(
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      },
                      child: Text(_t('Could not load. Retry', 'లోడ్ కాలేదు. మళ్లీ'))))
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        key: const Key('askodoxCreationAi'),
                        onPressed: aiReady ? () => _compose(ai: true) : null,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(_t('Write with AI', 'AIతో రాయండి')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('askodoxCreationManual'),
                        onPressed: () => _compose(ai: false),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(_t('Write myself', 'నేనే రాస్తా')),
                      ),
                    ]),
                    if (!aiReady)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_reason('text_drafts'), key: const Key('askodoxCreationAiUnavailable')),
                      ),
                    const SizedBox(height: 8),
                    ListTile(
                      key: const Key('askodoxCreationVideoUpload'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.video_call_outlined),
                      title: Text(_t('Upload a video / reel', 'వీడియో / రీల్ అప్‌లోడ్')),
                      subtitle: Text(_t('Your own video. ASKODOX does not generate video.',
                          'మీ సొంత వీడియో. ASKODOX వీడియోను తయారు చేయదు.')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/videos/native'),
                    ),
                    ListTile(
                      key: const Key('askodoxCreationImageGen'),
                      contentPadding: EdgeInsets.zero,
                      enabled: false,
                      leading: const Icon(Icons.image_not_supported_outlined),
                      title: Text(_t('Poster / image generation', 'పోస్టర్ / చిత్రం తయారీ')),
                      subtitle: Text('${_t('Not available', 'అందుబాటులో లేదు')}: ${_reason('image_generation')}'),
                    ),
                    const Divider(),
                    if (_items.isEmpty)
                      Padding(
                        key: const Key('askodoxCreationsEmpty'),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_t('Nothing saved yet.', 'ఇంకా ఏమీ సేవ్ కాలేదు.')),
                      ),
                    for (final item in _items)
                      Card(
                        key: ValueKey('askodoxCreation-${item['id']}'),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                                '${askodoxCreationKindLabel('${item['kind']}', _te)}'
                                '${item['source'] == 'ai' ? ' · ${_t('AI draft', 'AI డ్రాఫ్ట్')}' : ''}'
                                ' · ${item['status']}',
                                style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            SelectableText('${item['body'] ?? ''}'),
                            Wrap(spacing: 4, children: [
                              TextButton(onPressed: () => _edit(item), child: Text(_t('Edit', 'మార్చు'))),
                              TextButton(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: '${item['body'] ?? ''}'));
                                    if (mounted) _say(_t('Copied', 'కాపీ అయింది'));
                                  },
                                  child: Text(_t('Copy', 'కాపీ'))),
                              TextButton(
                                  key: ValueKey('askodoxCreationShare-${item['id']}'),
                                  onPressed: () async {
                                    try {
                                      await _device.invokeMethod<bool>(
                                          'shareText', <String, Object?>{'text': '${item['body'] ?? ''}'});
                                    } catch (_) {
                                      if (mounted) _say(_t('Could not open sharing.', 'షేర్ తెరవలేకపోయాం.'));
                                    }
                                  },
                                  child: Text(_t('Share', 'షేర్'))),
                              TextButton(
                                  key: ValueKey('askodoxCreationDelete-${item['id']}'),
                                  onPressed: () async {
                                    await ref.read(apiClientProvider).delete<Map<String, Object?>>(
                                        '/api/business/creations/${item['id']}',
                                        options: _auth);
                                    await _load();
                                  },
                                  child: Text(_t('Delete', 'తొలగించు'))),
                            ]),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.ai, required this.te, required this.draft});
  final bool ai;
  final bool te;
  final Future<String?> Function(String kind, String about) draft;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  String _kind = 'post';
  final _about = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  bool _fromAi = false;
  String? _error;

  String _t(String en, String te) => widget.te ? te : en;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: _t('What to create', 'ఏమి సృష్టించాలి')),
            items: [
              for (final k in askodoxCreationKinds)
                DropdownMenuItem(value: k, child: Text(askodoxCreationKindLabel(k, widget.te))),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          if (widget.ai) ...[
            TextField(
                key: const Key('askodoxCreationAbout'),
                controller: _about,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: _t('Your facts (product, price, offer, place...)', 'మీ వివరాలు (ఉత్పత్తి, ధర, ఆఫర్...)'))),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('askodoxCreationDraft'),
              onPressed: _busy
                  ? null
                  : () async {
                      if (_about.text.trim().length < 3) return;
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      final text = await widget.draft(_kind, _about.text.trim());
                      if (!mounted) return;
                      setState(() {
                        _busy = false;
                        if (text == null || text.isEmpty) {
                          _error = _t('AI writing is not available right now -- write it yourself or try later.',
                              'ఇప్పుడు AI రాయలేదు -- మీరే రాయండి లేదా తర్వాత ప్రయత్నించండి.');
                        } else {
                          _body.text = text;
                          _fromAi = true;
                        }
                      });
                    },
              child: Text(_busy ? _t('Drafting…', 'రాస్తోంది…') : _t('Draft it', 'డ్రాఫ్ట్ చేయి')),
            ),
            if (_error != null) Text(_error!, key: const Key('askodoxCreationDraftError')),
          ],
          TextField(
              key: const Key('askodoxCreationBody'),
              controller: _body,
              maxLines: 8,
              minLines: 3,
              decoration: InputDecoration(labelText: _t('Text', 'టెక్స్ట్'))),
          if (_fromAi)
            Text(_t('AI draft from your facts -- check it before you share.', 'మీ వివరాల నుంచి AI డ్రాఫ్ట్ -- షేర్ చేసే ముందు చూడండి.'),
                key: const Key('askodoxCreationAiNote')),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('askodoxCreationSave'),
            onPressed: () {
              if (_body.text.trim().isEmpty) return;
              Navigator.pop(context, <String, Object?>{
                'kind': _kind,
                'body': _body.text.trim(),
                'status': 'saved',
                'source': _fromAi ? 'ai' : 'owner',
              });
            },
            child: Text(_t('Save', 'సేవ్')),
          ),
        ]),
      ),
    );
  }
}
