import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/work_mode/data/work_audio.dart';
import 'package:podx/features/work_mode/domain/work_mode_plan.dart';

class _FakeOut implements AskodoxGameAudioOut {
  final prepared = <String>{};
  final calls = <String>[];
  @override
  Future<bool> has(String name) async => prepared.contains(name);
  @override
  Future<bool> prepare(String name, Uint8List bytes, {required bool short}) async {
    prepared.add(name);
    return bytes.isNotEmpty;
  }
  @override
  Future<bool> play(String name, double volume) async {
    calls.add('play $name');
    return true;
  }
  @override
  Future<bool> voice(String name, double volume) async {
    calls.add('voice $name');
    return true;
  }
  @override
  Future<bool> music(String? name, double volume) async {
    calls.add('music $name');
    return true;
  }
  @override
  Future<void> stop() async => calls.add('stop');
}

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

void main() {
  test('every job has its sound set, and every file it names ships with the app', () {
    for (final job in askodoxWorkJobs) {
      final set = askodoxWorkSoundPlan[job.id];
      expect(set, isNotNull, reason: job.id);
      for (final name in [set!.music, ...set.effects, set.voice, if (set.call != null) set.call!]) {
        expect(File('assets/work_audio/$name.ogg').existsSync(), isTrue, reason: '${job.id}: $name');
      }
    }
    final total = Directory('assets/work_audio').listSync().whereType<File>().fold<int>(0, (s, f) => s + f.lengthSync());
    expect(total, lessThan(1024 * 1024), reason: 'game sound stays small (owner: watch the app size)');
  });

  test('music on open; work sounds throttled; a call only after a quiet minute; one switch turns it off', () async {
    var now = DateTime(2026, 11, 10, 7);
    final out = _FakeOut();
    final audio = AskodoxWorkAudioDirector(out, clock: () => now, bundle: _Bundle());
    await audio.open('paper', soundOn: true);
    expect(out.calls, contains('music music_street'));

    // Walking: the paper boy calls once, then work sounds -- never more than one per 3 s.
    await audio.steps(telugu: true);
    expect(out.calls.last, 'voice voice_paper_call');
    now = now.add(const Duration(seconds: 1));
    await audio.steps(telugu: true);
    expect(out.calls.last, 'voice voice_paper_call', reason: 'too soon for another sound');
    now = now.add(const Duration(seconds: 4));
    await audio.steps(telugu: true);
    expect(out.calls.last, 'play sfx_paper');

    // Stopped walking: nothing for the first minute, then the waiting customer calls -- once per 3 minutes.
    now = now.add(const Duration(seconds: 30));
    await audio.tick(walking: false, telugu: true, done: false);
    expect(out.calls.where((c) => c == 'voice voice_paper'), isEmpty);
    now = now.add(const Duration(seconds: 40));
    await audio.tick(walking: false, telugu: true, done: false);
    expect(out.calls.last, 'voice voice_paper');
    now = now.add(const Duration(seconds: 60));
    await audio.tick(walking: false, telugu: true, done: false);
    expect(out.calls.where((c) => c == 'voice voice_paper').length, 1);

    await audio.setSound(false);
    expect(out.calls, contains('stop'));
    final before = out.calls.length;
    now = now.add(const Duration(minutes: 10));
    await audio.steps(telugu: true);
    await audio.tick(walking: false, telugu: true, done: false);
    expect(out.calls.sublist(before).where((c) => c.startsWith('play') || c.startsWith('voice')), isEmpty,
        reason: 'sound off = silent');
  });

  test('English screen: no Telugu calls, work sounds still play', () async {
    var now = DateTime(2026, 11, 10, 7);
    final out = _FakeOut();
    final audio = AskodoxWorkAudioDirector(out, clock: () => now, bundle: _Bundle());
    await audio.open('veg_cart', soundOn: true);
    await audio.steps(telugu: false);
    expect(out.calls.last, 'play sfx_cart');
    now = now.add(const Duration(minutes: 5));
    await audio.tick(walking: false, telugu: false, done: false);
    expect(out.calls.where((c) => c.startsWith('voice')), isEmpty);
  });
}
