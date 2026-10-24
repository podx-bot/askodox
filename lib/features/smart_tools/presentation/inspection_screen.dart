import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/chat_attachment_service.dart';
import '../../../services/media_picker.dart';
import '../data/vision_inspection_repository.dart';
import 'smart_tool_widgets.dart';

/// AI photo inspection: choose what is being checked, take / pick photos,
/// choose Quick / Deep / Expert, read an evidence-tiered report (seen /
/// likely / cannot confirm from a photo / what to check / warnings).
class AskodoxInspectionScreen extends ConsumerStatefulWidget {
  const AskodoxInspectionScreen({super.key, this.initialDomain});
  final String? initialDomain;

  @override
  ConsumerState<AskodoxInspectionScreen> createState() => _AskodoxInspectionScreenState();
}

const _modeLimits = {'quick': 1, 'deep': 2, 'expert': 4};

class _AskodoxInspectionScreenState extends ConsumerState<AskodoxInspectionScreen> {
  late String _domain = widget.initialDomain ?? 'general';
  String _mode = 'quick';
  final _photos = <ChatAttachment>[];
  final _note = TextEditingController();
  final _reference = TextEditingController();
  List<AskodoxInspectionProfile> _profiles = const [];
  bool _busy = false;
  AskodoxInspectionReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    if (!mounted) return;
    final te = askodoxToolsTe(context);
    try {
      final rows = await ref.read(askodoxVisionInspectionRepositoryProvider).profiles(te ? 'te' : 'en');
      if (mounted) setState(() => _profiles = rows);
    } catch (_) {
      // The domain chips fall back to the plain list below.
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pick(String source) async {
    try {
      final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
      if (!mounted) return;
      setState(() {
        _photos.addAll(picked.where((p) => p.isImage));
        while (_photos.length > 4) {
          _photos.removeAt(0);
        }
        _report = null;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      final te = askodoxToolsTe(context);
      setState(() => _error = te ? 'ఫోటో తీసుకోలేకపోయాను. కెమెరా అనుమతి చూడండి.'
          : 'Could not get the photo. Check the camera / photos permission.');
    }
  }

  Future<void> _inspect() async {
    final te = askodoxToolsTe(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await ref.read(askodoxVisionInspectionRepositoryProvider).inspect(
            _photos,
            domain: _domain,
            mode: _mode,
            language: te ? 'te' : 'en',
            userText: _note.text.trim(),
            referenceObject: _reference.text.trim(),
          );
      if (mounted) setState(() => _report = report);
    } on AskodoxInspectionException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _fallbackDomains = <String, (String, String)>{
    'general': ('General', 'సాధారణ'),
    'food': ('Food', 'ఆహారం'),
    'dish': ('Dish / recipe', 'వంటకం'),
    'vehicle': ('Vehicle', 'వాహనం'),
    'tyre': ('Tyre', 'టైర్'),
    'livestock': ('Livestock', 'పశువులు'),
    'crop': ('Crop / leaf', 'పంట / ఆకు'),
    'construction': ('Crack / construction', 'పగుళ్లు / నిర్మాణం'),
    'product': ('Product condition', 'వస్తువు పరిస్థితి'),
  };

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final profile = _profiles.where((p) => p.domain == _domain).firstOrNull;
    final domains = _profiles.isNotEmpty
        ? {for (final p in _profiles) p.domain: p.label}
        : {for (final e in _fallbackDomains.entries) e.key: te ? e.value.$2 : e.value.$1};
    final limit = _modeLimits[_mode]!;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'AI ఫోటో పరిశీలన' : 'AI photo inspection')),
      body: ListView(
        key: const Key('askodoxInspection'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const AskodoxToolSafetyNote('inspect'),
          Text(te ? 'ఏమి పరిశీలించాలి?' : 'What are you checking?', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final entry in domains.entries)
              ChoiceChip(
                key: ValueKey('askodoxInspectDomain-${entry.key}'),
                label: Text(entry.value),
                selected: _domain == entry.key,
                onSelected: (_) => setState(() {
                  _domain = entry.key;
                  _report = null;
                }),
              ),
          ]),
          if (profile != null && profile.guidance.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final g in profile.guidance)
              Text('📷 $g', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const Key('askodoxInspectMode'),
            segments: [
              ButtonSegment(value: 'quick', label: Text(te ? 'త్వరిత' : 'Quick')),
              ButtonSegment(value: 'deep', label: Text(te ? 'లోతుగా' : 'Deep')),
              ButtonSegment(value: 'expert', label: Text(te ? 'నిపుణ' : 'Expert')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _report = null;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              te ? 'ఈ మోడ్ గరిష్టంగా $limit ఫోటో(లు) పంపుతుంది.' : 'This mode sends up to $limit photo(s).',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxInspectCamera'),
                onPressed: _busy ? null : () => _pick('camera'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(te ? 'కెమెరా' : 'Camera'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxInspectGallery'),
                onPressed: _busy ? null : () => _pick('photos'),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(te ? 'గ్యాలరీ' : 'Gallery'),
              ),
            ),
          ]),
          if (_photos.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (var i = 0; i < _photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_photos[i].bytes, width: 76, height: 76, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 76, height: 76, child: Icon(Icons.image))),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: const Icon(Icons.cancel_rounded, size: 20),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: te ? 'ఏం తెలుసుకోవాలి? (ఐచ్ఛికం)' : 'What do you want to know? (optional)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_domain == 'livestock' || _domain == 'construction') ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('askodoxInspectReference'),
              controller: _reference,
              decoration: InputDecoration(
                labelText: te ? 'ఫోటోలో తెలిసిన సైజు వస్తువు (ఉదా: A4 పేపర్)' : 'Known-size object in the photo (e.g. A4 sheet)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('askodoxInspectRun'),
            onPressed: _busy || _photos.isEmpty ? null : _inspect,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search_rounded),
            label: Text(te ? 'పరిశీలించు' : 'Inspect'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, key: const Key('askodoxInspectError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_report != null) AskodoxInspectionReportView(report: _report!, te: te),
        ],
      ),
    );
  }
}

class AskodoxInspectionReportView extends StatelessWidget {
  const AskodoxInspectionReportView({super.key, required this.report, required this.te});
  final AskodoxInspectionReport report;
  final bool te;

  Widget _section(BuildContext context, String title, List<String> lines, {Color? color, IconData? icon}) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) Icon(icon, size: 18, color: color),
          if (icon != null) const SizedBox(width: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 4),
        for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $line')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final statusText = switch (r.status) {
      'insufficient_evidence' => te ? 'ఫోటోల నుండి సరిపడా ఆధారం లేదు.' : 'Not enough evidence in the photos.',
      'low_confidence' => te ? 'తక్కువ నమ్మకం — మరో ఫోటో తీయండి.' : 'Low confidence — take another photo.',
      _ => null,
    };
    return Card(
      key: const Key('askodoxInspectionReport'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.subject ?? (te ? 'విషయం స్పష్టంగా లేదు' : 'Subject unclear'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('${te ? 'నమ్మకం' : 'Confidence'} ${(r.confidence * 100).round()}%'
              '${r.cached ? (te ? ' · సేవ్ చేసిన ఫలితం' : ' · saved result') : ''}',
              style: const TextStyle(fontSize: 12)),
          if (statusText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(statusText, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700)),
            ),
          _section(context, te ? 'కనిపిస్తున్నవి' : 'Seen in the photo',
              [for (final o in r.observed) o.detail == null ? o.finding : '${o.finding} (${o.detail})'],
              icon: Icons.visibility_outlined),
          _section(context, te ? 'అవకాశం ఉన్నవి (అంచనా)' : 'Likely (inferred)',
              [for (final i in r.inferred) i.detail == null ? i.finding : '${i.finding} — ${i.detail}'],
              icon: Icons.lightbulb_outline_rounded),
          _section(context, te ? 'అంచనా పరిమాణాలు' : 'Estimated quantities', [
            for (final q in r.quantities)
              '${q.name}: ${q.low.toStringAsFixed(1)}–${q.high.toStringAsFixed(1)} ${q.unit}'
                  '${q.status == 'experimental' ? (te ? ' (ప్రయోగాత్మకం)' : ' (experimental)') : ''}',
          ], icon: Icons.straighten_rounded),
          if (r.visibleText != null)
            _section(context, te ? 'చదివిన టెక్స్ట్' : 'Text read', [r.visibleText!], icon: Icons.text_snippet_outlined),
          _section(context, te ? 'ఫోటో నుండి నిర్ధారించలేనివి' : 'Cannot be confirmed from a photo', r.notVerifiable,
              icon: Icons.help_outline_rounded, color: const Color(0xFFB45309)),
          _section(context, te ? 'చేయాల్సిన పరీక్షలు' : 'What to check', r.recommendedChecks,
              icon: Icons.fact_check_outlined),
          _section(context, te ? 'భద్రతా హెచ్చరికలు' : 'Safety warnings', r.safetyWarnings,
              icon: Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
          _section(context, te ? 'ఇంకా కావాల్సినవి' : 'More evidence needed', r.needsMoreEvidence,
              icon: Icons.add_a_photo_outlined),
          _section(context, te ? 'పరిమితులు' : 'Limits', r.limits, icon: Icons.info_outline_rounded),
        ]),
      ),
    );
  }
}
