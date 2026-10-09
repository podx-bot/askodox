import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// My Business -> Conversations & Automation (and Business settings): auto
/// replies from the seller's APPROVED answers only, handover words, business
/// hours, a live "try a customer message" preview, real platform status
/// (never "connected" without a verified connection) and the conversation
/// history. Nothing is sent to any platform from here.
class BusinessAutomationScreen extends ConsumerStatefulWidget {
  const BusinessAutomationScreen({super.key, this.section});

  /// 'settings' opens with Business settings (hours) first.
  final String? section;

  @override
  ConsumerState<BusinessAutomationScreen> createState() => _BusinessAutomationScreenState();
}

String askodoxPlatformStatusLabel(String status, bool te) => switch (status) {
      'LIVE' => te ? 'కనెక్ట్ అయింది (ధృవీకరించబడింది)' : 'Connected (verified)',
      'MOCK' => te ? 'టెస్ట్ మోడ్ -- ఏదీ పంపబడదు' : 'Test mode -- nothing is sent',
      'CONFIGURED_NOT_VERIFIED' => te ? 'సెటప్ ఉంది, ధృవీకరించలేదు' : 'Set up, not verified',
      'EXTERNAL_SETUP_REQUIRED' => te ? 'మీ ప్లాట్‌ఫామ్ కనెక్షన్ అవసరం' : 'Needs your platform connection',
      'NOT_AVAILABLE' => te ? 'అందుబాటులో లేదు' : 'Not available',
      _ => te ? 'తెలియదు' : 'Unknown',
    };

class _BusinessAutomationScreenState extends ConsumerState<BusinessAutomationScreen> {
  bool _loading = true;
  bool _error = false;
  bool _enabled = false;
  final Map<String, String> _faq = {};
  final _hours = TextEditingController();
  final _outOfHours = TextEditingController();
  final _handoff = TextEditingController();
  final _tryMessage = TextEditingController();
  Map<String, Map<String, Object?>> _platforms = {};
  String _note = '';
  String? _preview;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: ref.read(authSessionProvider).tokenPlaceholder);
  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final r = await ref.read(apiClientProvider).get<Map<String, Object?>>('/api/business/auto-response', options: _auth);
    if (!mounted) return;
    if (r is! ApiSuccess<Map<String, Object?>>) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    final item = r.data['item'] is Map ? Map<String, Object?>.from(r.data['item'] as Map) : null;
    final data = item?['data'] is Map ? Map<String, Object?>.from(item!['data'] as Map) : <String, Object?>{};
    setState(() {
      _loading = false;
      _error = false;
      _enabled = '${item?['status'] ?? ''}' == 'ACTIVE';
      _faq
        ..clear()
        ..addAll({
          for (final e in ((data['faq'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
        });
      _hours.text = '${data['business_hours'] ?? ''}';
      _outOfHours.text = '${data['out_of_hours_reply'] ?? ''}';
      _handoff.text = ((data['handoff_words'] as List?) ?? const []).join(', ');
      _platforms = {
        for (final e in ((r.data['platforms'] as Map?) ?? const {}).entries)
          '${e.key}': Map<String, Object?>.from(e.value as Map),
      };
      _note = '${r.data['note'] ?? ''}';
    });
  }

  Future<void> _save() async {
    final r = await ref.read(apiClientProvider).put<Map<String, Object?>>('/api/business/auto-response',
        body: {
          'enabled': _enabled,
          'business_hours': _hours.text.trim(),
          'out_of_hours_reply': _outOfHours.text.trim(),
          'faq': Map<String, String>.of(_faq),
          'handoff_words': [for (final w in _handoff.text.split(',')) if (w.trim().isNotEmpty) w.trim()],
        },
        options: _auth);
    if (!mounted) return;
    final ok = r is ApiSuccess;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? _t('Saved.', 'సేవ్ అయింది.')
            : r is ApiError && (r as ApiError).failure.statusCode == 400
                ? _t('Business hours must look like 09-21.', 'వ్యాపార సమయం 09-21 లాగా ఉండాలి.')
                : _t('Could not save.', 'సేవ్ కాలేదు.'))));
    if (ok) await _load();
  }

  Future<void> _try() async {
    final message = _tryMessage.text.trim();
    if (message.isEmpty) return;
    final r = await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/business/auto-response/preview',
        body: {'message': message}, options: _auth);
    if (!mounted) return;
    setState(() {
      if (r is ApiSuccess<Map<String, Object?>>) {
        final text = '${r.data['text'] ?? ''}';
        _preview = switch ('${r.data['status']}') {
          'answered' => '${_t('Auto-reply', 'ఆటో-రిప్లై')}: $text',
          'handoff' => _t('Handed over to you (handover word).', 'మీకు అప్పగించబడింది (హ్యాండోవర్ పదం).'),
          'out_of_hours' => text.isEmpty
              ? _t('Outside business hours -- it waits for you.', 'వ్యాపార సమయం కాదు -- మీ కోసం వేచి ఉంటుంది.')
              : '${_t('Outside hours', 'సమయం కాదు')}: $text',
          _ => _t('No approved answer -- it comes to you.', 'ఆమోదించిన జవాబు లేదు -- మీకు వస్తుంది.'),
        };
      } else {
        _preview = _t('Save your auto-replies first.', 'ముందుగా ఆటో-రిప్లైలు సేవ్ చేయండి.');
      }
    });
  }

  Future<void> _addAnswer() async {
    final topic = TextEditingController();
    final answer = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(_t('Approved answer', 'ఆమోదించిన జవాబు')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('askodoxAutoFaqTopic'),
              controller: topic,
              decoration: InputDecoration(labelText: _t('Customer asks about (e.g. delivery)', 'కస్టమర్ అడిగేది'))),
          TextField(
              key: const Key('askodoxAutoFaqAnswer'),
              controller: answer,
              decoration: InputDecoration(labelText: _t('Your answer', 'మీ జవాబు'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_t('Cancel', 'రద్దు'))),
          TextButton(
              key: const Key('askodoxAutoFaqSave'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Add', 'జోడించు'))),
        ],
      ),
    );
    if (ok == true && topic.text.trim().isNotEmpty && answer.text.trim().isNotEmpty) {
      setState(() => _faq[topic.text.trim()] = answer.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsFirst = widget.section == 'settings';
    final settings = Card(
      key: const Key('askodoxAutoSettings'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_t('Business settings', 'వ్యాపార సెట్టింగ్‌లు'), style: Theme.of(context).textTheme.titleSmall),
          TextField(
              key: const Key('askodoxAutoHours'),
              controller: _hours,
              decoration: InputDecoration(
                  labelText: _t('Business hours (HH-HH, e.g. 09-21; empty = always)', 'వ్యాపార సమయం (ఉదా. 09-21)'))),
          TextField(
              controller: _outOfHours,
              decoration: InputDecoration(labelText: _t('Reply outside hours', 'సమయం కాని సమయంలో జవాబు'))),
          TextField(
              key: const Key('askodoxAutoHandoff'),
              controller: _handoff,
              decoration: InputDecoration(
                  labelText: _t('Handover words (comma separated) -- these always come to you',
                      'హ్యాండోవర్ పదాలు (కామాతో) -- ఇవి ఎప్పుడూ మీకే వస్తాయి'))),
        ]),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(_t('Conversations & automation', 'సంభాషణలు & ఆటోమేషన్'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: TextButton(
                      key: const Key('askodoxAutoRetry'),
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      },
                      child: Text(_t('Could not load. Retry', 'లోడ్ కాలేదు. మళ్లీ'))))
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    if (settingsFirst) settings,
                    SwitchListTile(
                      key: const Key('askodoxAutoReplyEnabled'),
                      contentPadding: EdgeInsets.zero,
                      value: _enabled,
                      title: Text(_t('Auto-replies in ASKODOX chats', 'ASKODOX చాట్‌లలో ఆటో-రిప్లైలు')),
                      subtitle: Text(_t('Only your approved answers; anything else comes to you.',
                          'మీరు ఆమోదించిన జవాబులు మాత్రమే; మిగతావి మీకే వస్తాయి.')),
                      onChanged: (on) => setState(() => _enabled = on),
                    ),
                    Text(_t('Approved answers (templates)', 'ఆమోదించిన జవాబులు'),
                        style: Theme.of(context).textTheme.titleSmall),
                    for (final e in _faq.entries)
                      ListTile(
                        key: ValueKey('askodoxAutoFaq-${e.key}'),
                        title: Text(e.key),
                        subtitle: Text(e.value),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: _t('Remove', 'తొలగించు'),
                          onPressed: () => setState(() => _faq.remove(e.key)),
                        ),
                      ),
                    TextButton.icon(
                      key: const Key('askodoxAutoFaqAdd'),
                      onPressed: _addAnswer,
                      icon: const Icon(Icons.add),
                      label: Text(_t('Add an approved answer', 'జవాబు జోడించు')),
                    ),
                    if (!settingsFirst) settings,
                    const SizedBox(height: 8),
                    FilledButton(
                        key: const Key('askodoxAutoSave'), onPressed: _save, child: Text(_t('Save', 'సేవ్'))),
                    const Divider(height: 28),
                    Text(_t('Try a customer message', 'కస్టమర్ సందేశం ప్రయత్నించండి'),
                        style: Theme.of(context).textTheme.titleSmall),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              key: const Key('askodoxAutoTryMessage'),
                              controller: _tryMessage,
                              decoration: InputDecoration(hintText: _t('e.g. Do you deliver?', 'ఉదా. డెలివరీ ఉందా?')))),
                      TextButton(
                          key: const Key('askodoxAutoPreview'), onPressed: _try, child: Text(_t('Try', 'చూడు'))),
                    ]),
                    if (_preview != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_preview!, key: const Key('askodoxAutoPreviewResult'))),
                    const Divider(height: 28),
                    Text(_t('Platforms', 'ప్లాట్‌ఫామ్‌లు'), style: Theme.of(context).textTheme.titleSmall),
                    for (final e in _platforms.entries)
                      ListTile(
                        key: ValueKey('askodoxPlatform-${e.key}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(switch (e.key) {
                          'askodox_chat' => 'ASKODOX chats',
                          'facebook' => 'Facebook',
                          'instagram' => 'Instagram',
                          'whatsapp' => 'WhatsApp',
                          'snapchat' => 'Snapchat',
                          _ => e.key,
                        }),
                        subtitle: Text('${e.value['reason'] ?? ''}'),
                        trailing: Text(askodoxPlatformStatusLabel('${e.value['status']}', _te)),
                      ),
                    if (_note.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_note, style: Theme.of(context).textTheme.bodySmall)),
                    const Divider(height: 28),
                    ListTile(
                      key: const Key('askodoxAutoHistory'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(_t('Conversation history', 'సంభాషణల చరిత్ర')),
                      subtitle: Text(_t('Every chat, with auto-replies marked.', 'ఆటో-రిప్లైలు గుర్తించబడిన చాట్‌లు.')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/deals'),
                    ),
                  ],
                ),
    );
  }
}
