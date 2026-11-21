import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/work_mode/domain/live_work_status.dart';

void main() {
  test('Live Work dot: green while steps are counted, grey when the phone is still, red when it needs the person', () {
    const now = 1000000;
    expect(askodoxLiveWorkStatus(lastCountedAt: null, now: now), AskodoxLiveWorkStatus.idle);
    expect(askodoxLiveWorkStatus(lastCountedAt: now - 30, now: now), AskodoxLiveWorkStatus.live);
    expect(askodoxLiveWorkStatus(lastCountedAt: now - askodoxLiveWorkWindowSeconds, now: now), AskodoxLiveWorkStatus.live);
    expect(askodoxLiveWorkStatus(lastCountedAt: now - askodoxLiveWorkWindowSeconds - 1, now: now), AskodoxLiveWorkStatus.idle);
    // A clock that went backwards never shows "running".
    expect(askodoxLiveWorkStatus(lastCountedAt: now + 60, now: now), AskodoxLiveWorkStatus.idle);
    // Needing the person wins over everything else.
    expect(askodoxLiveWorkStatus(lastCountedAt: now - 5, now: now, needsAttention: true), AskodoxLiveWorkStatus.attention);
  });
}
