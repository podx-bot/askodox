import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';
import '../../core/share/askodox_image_share.dart';
import '../../services/media_picker.dart';

/// Photo try-on (owner 2026-11-24): "this dress / chappal / frame / hairstyle on ME", "this stove / TV / tile / paint
/// on MY table / wall / floor". Your photo + the item's photo -> one AI picture (POST /api/images/try-on), labelled as
/// an AI picture, never stored on the server. On-me needs "my photo, or the person agreed"; revealing wear is refused
/// by the server. Paid like any AI picture (AI Credits / the daily free count).
class AskodoxTryOnScreen extends ConsumerStatefulWidget {
  const AskodoxTryOnScreen({super.key, this.imageUrl = '', this.itemName = '', this.mode = 'on_me'});
  final String imageUrl;
  final String itemName;
  final String mode;

  @override
  ConsumerState<AskodoxTryOnScreen> createState() => _AskodoxTryOnScreenState();
}

/// The words for a refusal / failure code from the server (or the HTTP status).
String askodoxTryOnProblem(String code, bool te) => switch (code) {
      'consent' => te ? 'మీ ఫోటో, లేదా ఫోటోలో ఉన్నవాళ్ళు ఒప్పుకున్న ఫోటో మాత్రమే వాడండి.' : 'Use your own photo, or one the person agreed to.',
      'blocked_item' => te ? 'ఈ రకం వస్తువుకి ట్రై-ఆన్ లేదు.' : 'Try-on is not offered for this kind of item.',
      'daily_limit' => te ? 'ఈ రోజు ఫోటోల లిమిట్ అయిపోయింది. రేపు మళ్ళీ ప్రయత్నించండి.' : "Today's picture limit is used up. Try tomorrow.",
      'credits_low' => te ? 'AI Credits సరిపోవు. కొంచెం రీఛార్జ్ చేసి మళ్ళీ ప్రయత్నించండి.' : 'Not enough AI Credits. Recharge a little and try again.',
      'sign_in' => te ? 'ముందు సైన్ ఇన్ చేయండి.' : 'Sign in first.',
      'not_configured' || 'off' => te ? 'ట్రై-ఆన్ ఇప్పుడు ఆన్‌లో లేదు.' : 'Try-on is not switched on right now.',
      _ => te ? 'చిత్రం ఈసారి రాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'The picture could not be made this time. Try again.',
    };

class _AskodoxTryOnScreenState extends ConsumerState<AskodoxTryOnScreen> {
  late String _mode = widget.mode == 'in_home' ? 'in_home' : 'on_me';
  late final _name = TextEditingController(text: widget.itemName);
  final _size = TextEditingController();
  Uint8List? _mine;
  Uint8List? _item;
  Uint8List? _result;
  String _label = '';
  bool _consent = false;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrl.startsWith('https://')) unawaited(_fetchItem());
  }

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    super.dispose();
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  Future<void> _fetchItem() async {
    try {
      final response = await http.get(Uri.parse(widget.imageUrl)).timeout(const Duration(seconds: 15));
      final type = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 && type.startsWith('image/') && response.bodyBytes.length < 8000000 && mounted) {
        setState(() => _item = response.bodyBytes);
      }
    } catch (_) {
      // the person picks the item's photo themselves
    }
  }

  Future<void> _pick(bool mine) async {
    final te = _te;
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              key: const Key('askodoxTryOnCamera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(te ? 'ఫోటో తీయి' : 'Take a photo'),
              onTap: () => Navigator.pop(sheet, 'camera')),
          ListTile(
              key: const Key('askodoxTryOnGallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(te ? 'గ్యాలరీ నుంచి' : 'From the gallery'),
              onTap: () => Navigator.pop(sheet, 'photos')),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      if (mine) {
        _mine = picked.first.bytes;
      } else {
        _item = picked.first.bytes;
      }
      _result = null;
    });
  }

  Future<void> _make() async {
    final te = _te;
    final mine = _mine, item = _item;
    if (mine == null || item == null) {
      setState(() => _problem = te ? 'రెండు ఫోటోలు కావాలి.' : 'Both photos are needed.');
      return;
    }
    if (_mode == 'on_me' && !_consent) {
      setState(() => _problem = askodoxTryOnProblem('consent', te));
      return;
    }
    final session = ref.read(authSessionProvider);
    if (session.user == null) {
      setState(() => _problem = askodoxTryOnProblem('sign_in', te));
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _result = null;
    });
    final result = await ref.read(apiClientProvider).post<Map<String, Object?>>(
          '/api/images/try-on',
          body: {
            'mode': _mode,
            'person_or_place': {'data_base64': base64Encode(mine)},
            'item': {'data_base64': base64Encode(item)},
            'item_name': _name.text.trim(),
            'item_size': _size.text.trim(),
            'consent': _consent,
            'language': te ? 'te' : 'en',
          },
          options: ApiRequestOptions(authToken: session.tokenPlaceholder, timeout: const Duration(seconds: 150)),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
        if (data['ok'] == true) {
          try {
            _result = base64Decode('${data['image_base64'] ?? ''}');
            _label = '${data['label'] ?? ''}';
            return;
          } on FormatException {
            _problem = askodoxTryOnProblem('failed', te);
            return;
          }
        }
        _problem = askodoxTryOnProblem('${data['code'] ?? ''}', te);
      } else {
        final status = (result as ApiError<Map<String, Object?>>).failure.statusCode;
        _problem = askodoxTryOnProblem(switch (status) { 401 || 403 => 'sign_in', 402 => 'credits_low', _ => 'failed' }, te);
      }
    });
  }

  Future<void> _report() async {
    final te = _te;
    final session = ref.read(authSessionProvider);
    await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/feedback',
        body: {
          'kind': 'wrong_result',
          'message': 'Try-on picture reported (${_mode == 'on_me' ? 'on me' : 'in my home'}): ${_name.text.trim()}',
          'feature': 'try_on',
          'platform': 'android',
        },
        options: ApiRequestOptions(authToken: session.user == null ? null : session.tokenPlaceholder));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(te ? 'రిపోర్ట్ పంపాం. ధన్యవాదాలు.' : 'Reported. Thank you.')));
      setState(() => _result = null);
    }
  }

  Widget _photoBox(Uint8List? bytes, String label, IconData icon, Key key, VoidCallback onTap) => Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 34, color: const Color(0xFF475569)),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])
                : Image.memory(bytes, fit: BoxFit.cover, width: double.infinity),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final onMe = _mode == 'on_me';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ట్రై చేసి చూడు' : 'Try it')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SegmentedButton<String>(
          key: const Key('askodoxTryOnMode'),
          segments: [
            ButtonSegment(value: 'on_me', icon: const Icon(Icons.person_outline), label: Text(te ? 'నా మీద' : 'On me')),
            ButtonSegment(value: 'in_home', icon: const Icon(Icons.home_outlined), label: Text(te ? 'నా ఇంట్లో' : 'In my home')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() {
            _mode = v.first;
            _result = null;
          }),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _photoBox(_mine, onMe ? (te ? 'మీ ఫోటో' : 'Your photo') : (te ? 'గది / టేబుల్ / గోడ ఫోటో' : 'Room / table / wall photo'),
              onMe ? Icons.person_add_alt_1 : Icons.add_home_outlined, const Key('askodoxTryOnMine'), () => _pick(true)),
          const SizedBox(width: 10),
          _photoBox(_item, te ? 'వస్తువు ఫోటో' : 'Item photo', Icons.checkroom, const Key('askodoxTryOnItem'), () => _pick(false)),
        ]),
        const SizedBox(height: 10),
        TextField(
          key: const Key('askodoxTryOnName'),
          controller: _name,
          decoration: InputDecoration(labelText: te ? 'ఏమిటి (ఐచ్ఛికం)' : 'What it is (optional)', border: const OutlineInputBorder()),
        ),
        if (!onMe) ...[
          const SizedBox(height: 10),
          TextField(
            key: const Key('askodoxTryOnSize'),
            controller: _size,
            decoration: InputDecoration(
                labelText: te ? 'సైజ్ (ఉదా: 55 inch, 3 బర్నర్)' : 'Size (e.g. 55 inch, 3 burner)',
                border: const OutlineInputBorder()),
          ),
        ],
        if (onMe)
          CheckboxListTile(
            key: const Key('askodoxTryOnConsent'),
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(te ? 'ఇది నా ఫోటో, లేదా ఫోటోలో ఉన్నవాళ్ళు ఒప్పుకున్నారు' : 'This is my photo, or the person in it agreed'),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('askodoxTryOnMake'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _make,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(_busy ? (te ? 'తయారు చేస్తున్నాను… (30-60 సెకన్లు)' : 'Making it… (30-60 seconds)') : (te ? 'చూపించు' : 'Show me')),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_problem!, key: const Key('askodoxTryOnProblem'), style: const TextStyle(color: Color(0xFFB91C1C))),
          ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_result!, key: const Key('askodoxTryOnResult'))),
          const SizedBox(height: 6),
          Text(_label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxTryOnShare'),
                onPressed: () => askodoxShareImage(_result!, name: 'askodox-try-on', text: 'ASKODOX ✨'),
                icon: const Icon(Icons.share_outlined),
                label: Text(te ? 'షేర్' : 'Share'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const Key('askodoxTryOnReport'),
              onPressed: _report,
              icon: const Icon(Icons.flag_outlined),
              label: Text(te ? 'రిపోర్ట్' : 'Report'),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        Text(
            te
                ? 'మీ ఫోటోలు చిత్రం తయారు చేయడానికి మాత్రమే; ASKODOX దాచుకోదు. AI చిత్రం కాబట్టి నిజమైన ఫిట్, రంగు కొంచెం వేరుగా ఉండొచ్చు.'
                : 'Your photos are used only to make the picture; ASKODOX does not keep them. It is an AI picture, so the real fit and colour may differ.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ]),
    );
  }
}
