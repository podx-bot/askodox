import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/diagnostics/test_mode.dart';

void main() {
  tearDown(() => AskodoxTestLog.instance.configure(on: false));

  test('Test Mode off: nothing is collected or sent', () async {
    final sent = <List<Map<String, Object?>>>[];
    AskodoxTestLog.instance.configure(on: false, sink: (events) async => sent.add(events));
    askodoxTestLog('send', detail: {'input': 'typed', 'text': 'hello'});
    await AskodoxTestLog.instance.flush();
    expect(AskodoxTestLog.instance.pending, isEmpty);
    expect(sent, isEmpty);
  });

  test('Test Mode on: events queue with screen + time, long text is cut, flush sends a batch', () async {
    final sent = <List<Map<String, Object?>>>[];
    AskodoxTestLog.instance.configure(on: true, sink: (events) async => sent.add(events));
    AskodoxTestLog.instance.currentScreen = '/';
    askodoxTestLog('voice', detail: {'engine': 'device_fallback', 'reason': 'server_audio_not_played'});
    askodoxTestLog('reply', detail: {'reply': 'x' * 900, 'honesty': ['unbacked_nonexistence']});
    expect(AskodoxTestLog.instance.pending, hasLength(2));
    await AskodoxTestLog.instance.flush();
    expect(sent.single, hasLength(2));
    expect(sent.single.first['screen'], '/');
    expect(sent.single.first['kind'], 'voice');
    final reply = (sent.single.last['detail'] as Map)['reply'] as String;
    expect(reply.length, lessThanOrEqualTo(501));
    expect((sent.single.last['detail'] as Map)['honesty'], ['unbacked_nonexistence']);
    expect(AskodoxTestLog.instance.pending, isEmpty);
  });

  test('a failing upload never throws into the app', () async {
    AskodoxTestLog.instance.configure(on: true, sink: (events) async => throw StateError('offline'));
    askodoxTestLog('error', detail: {'error': 'x'});
    await AskodoxTestLog.instance.flush();
    expect(AskodoxTestLog.instance.pending, isEmpty);
  });
}
