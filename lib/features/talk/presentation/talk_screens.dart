import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/askodox_hub_icons.dart';
import '../../home/presentation/question_mic.dart';
import '../data/talk_repository.dart';

const _ink = Color(0xFF10204A);
const _green = Color(0xFF1F8A5B);
const _soft = Color(0xFFF6F5F0);

/// Accepted once per phone (the rules + 18+ + what listening costs).
const askodoxTalkRulesKey = 'askodox.talk.rules.v1';

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

/// The rules shown before the first discussion (and from the ⓘ button).
class AskodoxTalkRules extends StatelessWidget {
  const AskodoxTalkRules({super.key, required this.te, this.onAccept});
  final bool te;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final rules = te
        ? const [
            (Icons.visibility_off_rounded, 'ఎవరు ఎవరో ఎవరికీ తెలియదు. ప్రతి చర్చలో మీకు ఒక మారుపేరు వస్తుంది.'),
            (Icons.block_rounded, 'బూతులు ఏ భాషలో ఉన్నా **** గా మారతాయి; వినేటప్పుడు "బీప్" వస్తుంది.'),
            (Icons.phone_disabled_rounded, 'ఫోన్ నంబర్లు, లింకులు, ఐడీలు దాచేస్తాం — ఎవరినీ బయటకు లాగలేరు.'),
            (Icons.gavel_rounded, 'బెదిరింపు, ద్వేషం, లైంగిక మాటలు, డబ్బు / OTP అడగడం → message పోస్ట్ కాదు. 3 సార్లు → 24 గంటలు ఆగాలి.'),
            (Icons.flag_rounded, 'ఇబ్బంది పెట్టే message ని Report లేదా Block చేయండి.'),
            (Icons.person_rounded, '18 ఏళ్లు పైబడిన వారికి మాత్రమే.'),
            (Icons.payments_outlined, 'ఖర్చు: టెక్స్ట్ చదవడం ఉచితం. ప్రతి message ని ASKODOX వాయిస్‌లో వినాలంటే AI Credits ఖర్చవుతాయి — ఎక్కువగా చదివితే ఖర్చు తక్కువ.'),
          ]
        : const [
            (Icons.visibility_off_rounded, 'Nobody knows who anybody is. You get a made-up name in each discussion.'),
            (Icons.block_rounded, 'Rude words in any language become ****; when read aloud they are a "beep".'),
            (Icons.phone_disabled_rounded, 'Phone numbers, links and IDs are hidden — nobody can pull you out.'),
            (Icons.gavel_rounded, 'Threats, hate, sexual talk, asking for money / OTP → not posted. 3 times → 24 hours off.'),
            (Icons.flag_rounded, 'Report or Block any message that bothers you.'),
            (Icons.person_rounded, 'Adults (18+) only.'),
            (Icons.payments_outlined, 'Cost: reading text is free. Hearing each message in the ASKODOX voice uses AI Credits — reading more keeps it cheap.'),
          ];
    return ListView(
      key: const Key('askodoxTalkRules'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(18),
      children: [
        Text(te ? 'చర్చ ఎలా పనిచేస్తుంది' : 'How Talk works',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 12),
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.$1, size: 20, color: _green),
              const SizedBox(width: 10),
              Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 14, height: 1.35))),
            ]),
          ),
        if (onAccept != null) ...[
          const SizedBox(height: 6),
          FilledButton(
            key: const Key('askodoxTalkAccept'),
            style: FilledButton.styleFrom(
                backgroundColor: _ink, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
            onPressed: onAccept,
            child: Text(te ? 'నేను 18+ · నియమాలకు ఒప్పుకుంటున్నాను' : 'I am 18+ · I agree to the rules'),
          ),
        ],
      ],
    );
  }
}

/// Talk home (`/talk`): search a topic, see active discussions, start one.
class AskodoxTalkScreen extends ConsumerStatefulWidget {
  const AskodoxTalkScreen({super.key});

  @override
  ConsumerState<AskodoxTalkScreen> createState() => _AskodoxTalkScreenState();
}

class _AskodoxTalkScreenState extends ConsumerState<AskodoxTalkScreen> {
  final _search = TextEditingController();
  bool? _accepted;
  bool _busy = false;
  String? _problem;
  List<AskodoxTalkRoom> _rooms = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAccepted();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAccepted() async {
    var ok = false;
    try {
      ok = (await SharedPreferences.getInstance()).getBool(askodoxTalkRulesKey) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _accepted = ok);
    if (ok) unawaited(_refresh());
  }

  Future<void> _accept() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(askodoxTalkRulesKey, true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _accepted = true);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final rooms = await ref.read(talkRepositoryProvider).rooms(_search.text);
    if (mounted) setState(() => _rooms = rooms);
  }

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refresh);
    setState(() {});
  }

  Future<void> _enter(String topic) async {
    if (topic.trim().length < 2 || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final (room, problem) = await ref.read(talkRepositoryProvider).open(topic.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    if (room != null) {
      await context.push('/talk/${room.id}?topic=${Uri.encodeQueryComponent(room.topic)}');
      if (mounted) unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final signedIn = ref.watch(talkRepositoryProvider).signedIn;
    final query = _search.text.trim();
    final exact = _rooms.any((r) => r.topic.toLowerCase() == query.toLowerCase());
    return Scaffold(
      key: const Key('askodoxTalkScreen'),
      backgroundColor: _soft,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(te ? 'చర్చ' : 'Talk', style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            key: const Key('askodoxTalkRulesButton'),
            tooltip: te ? 'నియమాలు' : 'Rules',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (sheet) => SafeArea(child: AskodoxTalkRules(te: te)),
            ),
          ),
          const AskodoxHubIcons(current: 'talk'),
        ],
      ),
      body: !signedIn
          ? Center(child: Text(askodoxTalkProblemText('signin', te), key: const Key('askodoxTalkSignIn')))
          : _accepted == null
              ? const Center(child: CircularProgressIndicator())
              : _accepted == false
                  ? AskodoxTalkRules(te: te, onAccept: _accept)
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      TextField(
                        key: const Key('askodoxTalkSearch'),
                        controller: _search,
                        onChanged: _typed,
                        onSubmitted: _enter,
                        textInputAction: TextInputAction.go,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: te ? 'ఏ విషయం మీద మాట్లాడాలి? ఉదా. వరి ధరలు' : 'What to talk about? e.g. paddy prices',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                      if (query.length >= 2 && !exact)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: FilledButton.icon(
                            key: const Key('askodoxTalkStart'),
                            style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(46)),
                            onPressed: _busy ? null : () => _enter(query),
                            icon: const Icon(Icons.add_comment_rounded),
                            label: Text(te ? '"$query" మీద చర్చ మొదలుపెట్టు' : 'Start a talk on "$query"'),
                          ),
                        ),
                      if (_problem != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(askodoxTalkProblemText(_problem!, te),
                              key: const Key('askodoxTalkProblem'), style: const TextStyle(color: Color(0xFFB45309))),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        query.isEmpty ? (te ? 'ఇప్పుడు జరుగుతున్న చర్చలు' : 'Active now') : (te ? 'దొరికిన చర్చలు' : 'Found'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF5B6670)),
                      ),
                      const SizedBox(height: 8),
                      if (_rooms.isEmpty)
                        Text(te ? 'ఇంకా ఏ చర్చా లేదు — మొదటి వారు మీరే అవ్వండి.' : 'No talk yet — be the first.',
                            style: const TextStyle(color: Color(0xFF7A838C))),
                      for (final room in _rooms)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              key: ValueKey('askodoxTalkRoom-${room.id}'),
                              leading: const Icon(Icons.forum_rounded, color: _ink),
                              title: Text(room.topic, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(te ? '${room.messages} మాటలు' : '${room.messages} messages'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _enter(room.topic),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        te
                            ? 'చదవడం ఉచితం · 🔊 వినడం = AI Credits'
                            : 'Reading is free · 🔊 listening = AI Credits',
                        key: const Key('askodoxTalkCostNote'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A838C)),
                      ),
                    ]),
    );
  }
}

/// One discussion (`/talk/:id`). New messages are fetched every few seconds.
class AskodoxTalkRoomScreen extends ConsumerStatefulWidget {
  const AskodoxTalkRoomScreen({super.key, required this.roomId, this.topic = '',
      this.device = const MethodChannel('com.askodox.app/device')});
  final String roomId;
  final String topic;
  final MethodChannel device;

  @override
  ConsumerState<AskodoxTalkRoomScreen> createState() => _AskodoxTalkRoomScreenState();
}

class _AskodoxTalkRoomScreenState extends ConsumerState<AskodoxTalkRoomScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<AskodoxTalkMessage> _messages = [];
  Timer? _poll;
  AskodoxTalkRoom? _room;
  String? _mutedUntil;
  String? _speaking;
  bool _sending = false;
  bool _fromVoice = false;

  int get _last => _messages.isEmpty ? 0 : _messages.last.seq;

  @override
  void initState() {
    super.initState();
    _openAndLoad();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    widget.device.invokeMethod<bool>('stopSpeaking').catchError((_) => false);
    super.dispose();
  }

  Future<void> _openAndLoad() async {
    if (widget.topic.isNotEmpty) {
      final (room, _) = await ref.read(talkRepositoryProvider).open(widget.topic);
      if (mounted && room != null) setState(() => _room = room);
    }
    await _load();
  }

  Future<void> _load() async {
    final page = await ref.read(talkRepositoryProvider).messages(widget.roomId, after: _last);
    if (!mounted || page.problem != null) return;
    final known = _messages.map((m) => m.id).toSet();
    final fresh = page.messages.where((m) => !known.contains(m.id)).toList();
    setState(() {
      _mutedUntil = page.mutedUntil;
      _messages.addAll(fresh);
    });
    if (fresh.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  Future<void> _send() async {
    final te = _te(context);
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await ref.read(talkRepositoryProvider)
        .send(widget.roomId, text, kind: _fromVoice ? 'voice' : 'text', lang: te ? 'te' : 'en');
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent.problem != null) {
      _snack(askodoxTalkProblemText(sent.problem!, te));
      return;
    }
    _text.clear();
    _fromVoice = false;
    if (sent.support != null) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: const Key('askodoxTalkSupport'),
          title: Text(te ? 'మేము మీతో ఉన్నాం' : 'We are with you'),
          content: Text(sent.support!),
          actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'సరే' : 'OK'))],
        ),
      );
      return;
    }
    if (!sent.posted) {
      _snack(te
          ? 'ఈ message నియమాలకు విరుద్ధం (బెదిరింపు / ద్వేషం / లైంగిక / డబ్బు / వ్యక్తిగత వివరాలు), అందుకే పోస్ట్ కాలేదు.'
          : 'This message breaks the rules (threat / hate / sexual / money / personal details), so it was not posted.');
      if (sent.mutedUntil != null) setState(() => _mutedUntil = sent.mutedUntil);
      return;
    }
    if (sent.maskedWords > 0 || sent.contactsHidden > 0) {
      _snack(te ? 'కొన్ని మాటలు / నంబర్లు దాచి పోస్ట్ చేశాం.' : 'Posted with some words / contacts hidden.');
    }
    await _load();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _listen(AskodoxTalkMessage m) async {
    final te = _te(context);
    final lang = te ? 'te' : 'en';
    setState(() => _speaking = m.id);
    final (audio, spokenText, problem) = await ref.read(talkRepositoryProvider).speak(m.id, lang);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _speaking = null);
      _snack(askodoxTalkProblemText(problem, te));
      return;
    }
    try {
      var played = false;
      if (audio != null) {
        played = await widget.device.invokeMethod<bool>(
                'playReplyAudio', <String, Object?>{'bytes': audio, 'languageCode': lang}) ==
            true;
      }
      if (!played) {
        await widget.device.invokeMethod<bool>('speakReply', <String, Object?>{'text': spokenText, 'languageCode': lang});
      }
    } catch (_) {
      // No audio on this device: the text stays readable.
    } finally {
      if (mounted) setState(() => _speaking = null);
    }
  }

  Future<void> _more(AskodoxTalkMessage m) async {
    final te = _te(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('askodoxTalkReport'),
            leading: const Icon(Icons.flag_rounded),
            title: Text(te ? 'Report చేయి' : 'Report'),
            subtitle: Text(te ? 'ASKODOX బృందం చూస్తుంది' : 'The ASKODOX team will look at it'),
            onTap: () => Navigator.of(sheet).pop('report'),
          ),
          ListTile(
            key: const Key('askodoxTalkBlock'),
            leading: const Icon(Icons.block_rounded),
            title: Text(te ? 'ఈ వ్యక్తిని Block చేయి' : 'Block this person'),
            subtitle: Text(te ? 'వీరి messages మీకు ఇక కనిపించవు' : 'You will not see their messages again'),
            onTap: () => Navigator.of(sheet).pop('block'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final repo = ref.read(talkRepositoryProvider);
    if (choice == 'report') {
      final ok = await repo.report(m.id, 'user_report');
      if (mounted) _snack(ok ? (te ? 'Report చేశాం. ధన్యవాదాలు.' : 'Reported. Thank you.') : askodoxTalkProblemText('x', te));
    } else {
      final ok = await repo.block(m.id);
      if (!mounted) return;
      if (ok) {
        final alias = m.alias;
        setState(() => _messages.removeWhere((x) => x.alias == alias && !x.mine));
        _snack(te ? 'Block చేశాం.' : 'Blocked.');
      } else {
        _snack(askodoxTalkProblemText('x', te));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final muted = _mutedUntil != null;
    return Scaffold(
      key: const Key('askodoxTalkRoomScreen'),
      backgroundColor: _soft,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.topic.isEmpty ? (te ? 'చర్చ' : 'Talk') : widget.topic,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (_room?.alias != null)
            Text(te ? 'మీ పేరు: ${_room!.alias}' : 'You are: ${_room!.aliasEn ?? _room!.alias}',
                key: const Key('askodoxTalkYou'), style: const TextStyle(fontSize: 12, color: Color(0xFF5B6670))),
        ]),
        actions: const [AskodoxHubIcons(current: 'talk')],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFF6E0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            te ? 'చదవడం ఉచితం · 🔊 వినడం = AI Credits · బూతులు **** అవుతాయి' : 'Reading free · 🔊 listening = AI Credits · rude words become ****',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B4A00)),
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text(te ? 'మొదటి మాట మీదే!' : 'Say the first word!', style: const TextStyle(color: Color(0xFF7A838C))))
              : ListView.builder(
                  key: const Key('askodoxTalkMessages'),
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    return Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        key: ValueKey('askodoxTalkMsg-${m.id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: m.mine ? const Color(0xFFE3F4EA) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                              child: Text(te ? m.alias : m.aliasEn,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _green)),
                            ),
                            if (m.kind == 'voice')
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.mic_rounded, size: 13, color: Color(0xFF7A838C)),
                              ),
                          ]),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Flexible(child: Text(m.text, style: const TextStyle(fontSize: 15, height: 1.3))),
                            IconButton(
                              key: ValueKey('askodoxTalkListen-${m.id}'),
                              tooltip: te ? 'వినండి (AI Credits)' : 'Listen (AI Credits)',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(_speaking == m.id ? Icons.graphic_eq_rounded : Icons.volume_up_rounded, size: 18),
                              onPressed: _speaking == null ? () => _listen(m) : null,
                            ),
                            if (!m.mine)
                              IconButton(
                                key: ValueKey('askodoxTalkMore-${m.id}'),
                                tooltip: te ? 'Report / Block' : 'Report / Block',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.more_vert_rounded, size: 18),
                                onPressed: () => _more(m),
                              ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: muted
                ? Text(askodoxTalkProblemText('muted', te), key: const Key('askodoxTalkMuted'),
                    style: const TextStyle(color: Color(0xFFB45309)))
                : Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('askodoxTalkInput'),
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        onChanged: (_) => _fromVoice = false,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: te ? 'మీ మాట రాయండి లేదా మాట్లాడండి' : 'Write or speak',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    AskodoxQuestionMic(
                      lang: te ? 'te' : 'en',
                      onText: (spoken) {
                        _text.text = spoken;
                        _fromVoice = true;
                      },
                    ),
                    IconButton.filled(
                      key: const Key('askodoxTalkSend'),
                      style: IconButton.styleFrom(backgroundColor: _ink),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }
}
