import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../smart_tools/presentation/smart_tool_widgets.dart';
import '../data/ptt_repository.dart';

/// Native recorder / player on the ONE device bridge (MainActivity):
/// startVoiceRecording / stopVoiceRecording (MediaRecorder, AAC .m4a) and
/// playReplyAudio (MediaPlayer). Injectable for tests.
abstract interface class AskodoxPttAudio {
  Future<bool> start();
  Future<Uint8List?> stop();
  Future<bool> play(Uint8List bytes);
}

class DevicePttAudio implements AskodoxPttAudio {
  const DevicePttAudio();
  static const _device = MethodChannel('com.askodox.app/device');

  @override
  Future<bool> start() async {
    try {
      return await _device.invokeMethod<bool>('startVoiceRecording', {'languageCode': 'en'}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> stop() async {
    try {
      final path = await _device.invokeMethod<String>('stopVoiceRecording');
      if (path == null || path.isEmpty) return null;
      final file = File(path);
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> play(Uint8List bytes) async {
    try {
      return await _device.invokeMethod<bool>('playReplyAudio', {'bytes': bytes, 'languageCode': 'en'}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

final askodoxPttAudioProvider = Provider<AskodoxPttAudio>((ref) => const DevicePttAudio());

// ---------------------------------------------------------------- groups

class AskodoxPttHomeScreen extends ConsumerStatefulWidget {
  const AskodoxPttHomeScreen({super.key});

  @override
  ConsumerState<AskodoxPttHomeScreen> createState() => _AskodoxPttHomeScreenState();
}

class _AskodoxPttHomeScreenState extends ConsumerState<AskodoxPttHomeScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _group = TextEditingController();
  Future<List<AskodoxPttChannel>>? _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = ref.read(askodoxPttRepositoryProvider).mine();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _open(Future<AskodoxPttChannel> Function(AskodoxPttRepository repo) action) async {
    final te = askodoxToolsTe(context);
    try {
      final channel = await action(ref.read(askodoxPttRepositoryProvider));
      if (!mounted) return;
      setState(() => _error = null);
      await context.push('/ptt/${channel.id}?name=${Uri.encodeComponent(channel.name)}&code=${channel.code}');
      if (mounted) setState(() => _future = ref.read(askodoxPttRepositoryProvider).mine());
    } on AskodoxPttException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'వాకీ-టాకీ (ఇంటర్నెట్)' : 'Push-to-talk (internet)')),
      body: ListView(
        key: const Key('askodoxPttHome'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            te
                ? 'ఇంటర్నెట్ ద్వారా పనిచేస్తుంది — ఫోన్‌లు ఆఫ్‌లైన్ రేడియోల్లా పని చేయవు. కోడ్ ఉన్నవారే చేరగలరు; సందేశాలు 24 గంటల్లో తొలగిపోతాయి.'
                : 'Works over the internet — phones cannot act as offline radios. Only people with the code can join; clips are deleted after 24 hours.',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('askodoxPttName'),
            controller: _name,
            decoration: InputDecoration(labelText: te ? 'మీ పేరు (గ్రూప్‌లో)' : 'Your name (shown in the group)',
                border: const OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('askodoxPttCode'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: te ? 'గ్రూప్ కోడ్' : 'Group code', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('askodoxPttJoin'),
              onPressed: () => _open((repo) => repo.join(_code.text.trim(), _name.text.trim())),
              child: Text(te ? 'చేరు' : 'Join'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _group,
                decoration: InputDecoration(labelText: te ? 'కొత్త గ్రూప్ పేరు' : 'New group name', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('askodoxPttCreate'),
              onPressed: () => _open((repo) => repo.create(_group.text.trim(), _name.text.trim())),
              child: Text(te ? 'సృష్టించు' : 'Create'),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, key: const Key('askodoxPttError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FutureBuilder<List<AskodoxPttChannel>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                final e = snap.error;
                return Text(e is AskodoxPttException ? e.message(te) : '$e');
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return Column(children: [
                for (final c in snap.data!)
                  Card(
                    child: ListTile(
                      key: ValueKey('askodoxPttChannel-${c.id}'),
                      leading: const Icon(Icons.record_voice_over_outlined),
                      title: Text(c.name),
                      subtitle: Text('${te ? 'కోడ్' : 'Code'} ${c.code} · ${c.members} ${te ? 'సభ్యులు' : 'members'}'),
                      onTap: () => _open((repo) async => c),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- talk

class AskodoxPttChannelScreen extends ConsumerStatefulWidget {
  const AskodoxPttChannelScreen({super.key, required this.channelId, required this.name, required this.code});
  final String channelId;
  final String name;
  final String code;

  @override
  ConsumerState<AskodoxPttChannelScreen> createState() => _AskodoxPttChannelScreenState();
}

class _AskodoxPttChannelScreenState extends ConsumerState<AskodoxPttChannelScreen> {
  static const maxTalk = Duration(seconds: 60);
  late final AskodoxPttRepository _repo;
  late final AskodoxPttAudio _audio;
  final _clips = <AskodoxPttClip>[];
  final _played = <String>{};
  Timer? _poll;
  Timer? _limit;
  DateTime? _talkStarted;
  bool _talking = false;
  bool _sending = false;
  bool _autoPlay = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(askodoxPttRepositoryProvider);
    _audio = ref.read(askodoxPttAudioProvider);
    unawaited(_refresh(initial: true));
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _limit?.cancel();
    if (_talking) unawaited(_audio.stop());
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    try {
      final after = _clips.isEmpty ? '' : _clips.last.createdAt;
      final known = {for (final c in _clips) c.id};
      final fresh = [for (final c in await _repo.clips(widget.channelId, after: after)) if (!known.contains(c.id)) c];
      if (!mounted || fresh.isEmpty) return;
      setState(() => _clips.addAll(fresh));
      if (initial) {
        _played.addAll(fresh.map((c) => c.id)); // history is not auto-played
      } else if (_autoPlay) {
        for (final clip in fresh.where((c) => !c.mine && !_played.contains(c.id))) {
          await _play(clip);
        }
      }
    } on AskodoxPttException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxToolsTe(context)));
    }
  }

  Future<void> _play(AskodoxPttClip clip) async {
    _played.add(clip.id);
    try {
      final bytes = await _repo.audio(clip.id);
      await _audio.play(bytes);
    } on AskodoxPttException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxToolsTe(context)));
    }
  }

  Future<void> _startTalk() async {
    if (_talking || _sending) return;
    final ok = await _audio.start();
    if (!mounted) return;
    if (!ok) {
      final te = askodoxToolsTe(context);
      setState(() => _error = te ? 'మైక్ ప్రారంభం కాలేదు — అనుమతి చూడండి.' : 'The microphone did not start — check the permission.');
      return;
    }
    setState(() {
      _talking = true;
      _error = null;
      _talkStarted = DateTime.now();
    });
    _limit = Timer(maxTalk, () => unawaited(_stopTalk()));
  }

  Future<void> _stopTalk() async {
    if (!_talking) return;
    _limit?.cancel();
    final started = _talkStarted ?? DateTime.now();
    setState(() {
      _talking = false;
      _sending = true;
    });
    final bytes = await _audio.stop();
    final duration = DateTime.now().difference(started).inMilliseconds;
    try {
      if (bytes != null && bytes.isNotEmpty) {
        final clip = await _repo.send(widget.channelId, bytes, duration.clamp(0, maxTalk.inMilliseconds).toInt());
        _played.add(clip.id);
        if (mounted) setState(() => _clips.add(clip));
      }
    } on AskodoxPttException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxToolsTe(context)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leave() async {
    try {
      await _repo.leave(widget.channelId);
    } on AskodoxPttException {
      // leaving is best-effort
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            key: const Key('askodoxPttLeave'),
            tooltip: te ? 'గ్రూప్ వదిలేయి' : 'Leave group',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _leave,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(child: SelectableText('${te ? 'కోడ్' : 'Code'}: ${widget.code}', style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(te ? 'ఆటో-ప్లే' : 'Auto-play'),
            Switch(key: const Key('askodoxPttAutoplay'), value: _autoPlay, onChanged: (v) => setState(() => _autoPlay = v)),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, key: const Key('askodoxPttChannelError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: ListView(
            key: const Key('askodoxPttClips'),
            padding: const EdgeInsets.all(12),
            children: [
              for (final clip in _clips)
                Align(
                  alignment: clip.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    child: ListTile(
                      key: ValueKey('askodoxPttClip-${clip.id}'),
                      dense: true,
                      leading: const Icon(Icons.play_arrow_rounded),
                      title: Text(clip.mine ? (te ? 'మీరు' : 'You') : clip.senderName),
                      subtitle: Text('${(clip.durationMs / 1000).toStringAsFixed(1)} s'),
                      onTap: () => _play(clip),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 28, top: 8),
          child: GestureDetector(
            key: const Key('askodoxPttTalk'),
            onLongPressStart: (_) => _startTalk(),
            onLongPressEnd: (_) => _stopTalk(),
            child: Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _talking ? const Color(0xFFDC2626) : (_sending ? Colors.grey : const Color(0xFF1769FF)),
              ),
              child: Text(
                _talking ? (te ? 'మాట్లాడుతున్నారు' : 'Talking') : (_sending ? (te ? 'పంపుతోంది' : 'Sending') : (te ? 'పట్టుకుని మాట్లాడండి' : 'Hold to talk')),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
