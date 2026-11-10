import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Work Mode sound (owner 2026-11-10): background music per job, a work sound when steps come in
/// (grass cut, paper thrown, mud, digging, welding ...) and a short Telugu call when nobody walks.
/// All files are small and ship with the app (assets/work_audio/<name>.ogg): music and effects are
/// code-made, the voices were recorded once -- nothing is generated while playing, so it costs nothing.
typedef AskodoxWorkSoundSet = ({String music, List<String> effects, String voice, String? call});

const askodoxWorkSoundPlan = <String, AskodoxWorkSoundSet>{
  'paddy': (music: 'music_village', effects: ['sfx_swish', 'sfx_mud'], voice: 'voice_paddy', call: null),
  'chilli': (music: 'music_village', effects: ['sfx_swish'], voice: 'voice_chilli', call: null),
  'vegetables': (music: 'music_village', effects: ['sfx_swish'], voice: 'voice_vegetables', call: null),
  'paper': (music: 'music_street', effects: ['sfx_paper', 'sfx_bell'], voice: 'voice_paper', call: 'voice_paper_call'),
  'delivery': (music: 'music_street', effects: ['sfx_bell'], voice: 'voice_delivery', call: null),
  'digging': (music: 'music_work', effects: ['sfx_dig'], voice: 'voice_digging', call: null),
  'house': (music: 'music_work', effects: ['sfx_hammer', 'sfx_dig'], voice: 'voice_house', call: null),
  'welding': (music: 'music_work', effects: ['sfx_weld', 'sfx_hammer'], voice: 'voice_welding', call: null),
  'chicken_shop': (music: 'music_kitchen', effects: ['sfx_chop'], voice: 'voice_chicken_shop', call: null),
  'hotel': (music: 'music_kitchen', effects: ['sfx_sizzle', 'sfx_chop'], voice: 'voice_hotel', call: null),
  'milk': (music: 'music_village', effects: ['sfx_bell'], voice: 'voice_milk', call: null),
  'veg_cart': (music: 'music_street', effects: ['sfx_cart'], voice: 'voice_veg_cart', call: 'voice_veg_cart_call'),
  'cattle': (music: 'music_village', effects: ['sfx_cowbell'], voice: 'voice_cattle', call: null),
  'fishing': (music: 'music_village', effects: ['sfx_splash'], voice: 'voice_fishing', call: null),
};

/// The phone's game player (native, `com.askodox.app/game_audio`). Injectable for tests.
abstract interface class AskodoxGameAudioOut {
  Future<bool> has(String name);
  Future<bool> prepare(String name, Uint8List bytes, {required bool short});
  Future<bool> play(String name, double volume);
  Future<bool> voice(String name, double volume);
  Future<bool> music(String? name, double volume);
  Future<void> stop();
}

class ChannelGameAudio implements AskodoxGameAudioOut {
  const ChannelGameAudio();
  static const _channel = MethodChannel('com.askodox.app/game_audio');

  Future<bool> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false; // no player (tests, old builds): the game simply stays silent
    }
  }

  @override
  Future<bool> has(String name) => _call('has', {'name': name});
  @override
  Future<bool> prepare(String name, Uint8List bytes, {required bool short}) =>
      _call('prepare', {'name': name, 'bytes': bytes, 'short': short});
  @override
  Future<bool> play(String name, double volume) => _call('play', {'name': name, 'volume': volume});
  @override
  Future<bool> voice(String name, double volume) => _call('voice', {'name': name, 'volume': volume});
  @override
  Future<bool> music(String? name, double volume) => _call('music', {'name': name, 'volume': volume});
  @override
  Future<void> stop() => _call('stop');
}

final askodoxGameAudioOutProvider = Provider<AskodoxGameAudioOut>((_) => const ChannelGameAudio());

/// Sound on / off for Work Mode (one switch; remembered on the phone).
class AskodoxWorkSoundSetting extends StateNotifier<bool> {
  AskodoxWorkSoundSetting() : super(true) {
    unawaited(_load());
  }
  static const key = 'askodox.work.sound.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = prefs.getBool(key) ?? true;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      (await SharedPreferences.getInstance()).setBool(key, state);
    } catch (_) {}
  }
}

final askodoxWorkSoundOnProvider = StateNotifierProvider<AskodoxWorkSoundSetting, bool>((_) => AskodoxWorkSoundSetting());

/// Decides WHEN a sound plays, so the screen never turns into noise:
/// - music loops quietly while the Today screen is open;
/// - a work sound at most every few seconds while steps come in;
/// - a Telugu call only after a minute of nobody walking, then at most every 3 minutes;
/// - while walking, a street seller's own call now and then (paper boy, vegetable cart).
class AskodoxWorkAudioDirector {
  AskodoxWorkAudioDirector(this._out, {DateTime Function()? clock, AssetBundle? bundle})
      : _clock = clock ?? DateTime.now,
        _bundle = bundle ?? rootBundle;

  final AskodoxGameAudioOut _out;
  final DateTime Function() _clock;
  final AssetBundle _bundle;

  static const musicVolume = 0.22;
  static const effectGap = Duration(seconds: 3);
  static const quietBeforeCall = Duration(seconds: 60);
  static const callGap = Duration(minutes: 3);
  static const sellerCallGap = Duration(seconds: 90);

  String? _job;
  bool _on = true;
  bool _paused = false;
  final _prepared = <String>{};
  DateTime? _lastEffect, _lastVoice, _lastSellerCall, _lastStep;
  late DateTime _openedAt = _clock();
  int _effectTurn = 0;

  /// What was played, newest last (tests and diagnostics).
  final played = <String>[];

  AskodoxWorkSoundSet? get _set => askodoxWorkSoundPlan[_job];

  Future<void> _ready(String name, {required bool short}) async {
    if (_prepared.contains(name)) return;
    try {
      final data = await _bundle.load('assets/work_audio/$name.ogg');
      if (await _out.prepare(name, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), short: short)) {
        _prepared.add(name);
      }
    } catch (_) {}
  }

  /// The job on screen (again and again is fine); loads its few files and starts the music.
  Future<void> open(String jobId, {required bool soundOn}) async {
    _on = soundOn;
    if (_job == jobId) return;
    _job = jobId;
    _openedAt = _clock();
    final set = _set;
    if (set == null) return;
    await _ready(set.music, short: false);
    for (final e in set.effects) {
      await _ready(e, short: true);
    }
    await _ready(set.voice, short: false);
    if (set.call != null) await _ready(set.call!, short: false);
    await _music();
  }

  Future<void> _music() async {
    final set = _set;
    if (set == null) return;
    if (_on && !_paused) {
      if (await _out.music(set.music, musicVolume)) played.add(set.music);
    } else {
      await _out.music(null, 0);
    }
  }

  Future<void> setSound(bool on) async {
    _on = on;
    if (!on) await _out.stop();
    await _music();
  }

  Future<void> pause() async {
    _paused = true;
    await _out.stop();
  }

  Future<void> resume() async {
    _paused = false;
    await _music();
  }

  /// New steps arrived: a work sound (throttled), and now and then the seller's call.
  Future<void> steps({required bool telugu}) async {
    final now = _clock();
    _lastStep = now;
    final set = _set;
    if (set == null || !_on || _paused) return;
    final call = set.call;
    if (telugu && call != null && (_lastSellerCall == null || now.difference(_lastSellerCall!) >= sellerCallGap)) {
      _lastSellerCall = now;
      _lastEffect = now;
      if (await _out.voice(call, 0.9)) played.add(call);
      return;
    }
    if (_lastEffect != null && now.difference(_lastEffect!) < effectGap) return;
    _lastEffect = now;
    final name = set.effects[_effectTurn++ % set.effects.length];
    if (await _out.play(name, 0.75)) played.add(name);
  }

  /// Called every few seconds: nobody walking for a while -> the waiting customer calls out.
  Future<void> tick({required bool walking, required bool telugu, required bool done}) async {
    final set = _set;
    if (set == null || !_on || _paused || walking || done || !telugu) return;
    final now = _clock();
    final quietSince = _lastStep ?? _openedAt;
    if (now.difference(quietSince) < quietBeforeCall) return;
    if (_lastVoice != null && now.difference(_lastVoice!) < callGap) return;
    _lastVoice = now;
    if (await _out.voice(set.voice, 1.0)) played.add(set.voice);
  }

  Future<void> close() async {
    _job = null;
    await _out.stop();
  }
}
