import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backup implements AskodoxHistoryBackup {
  _Backup(this.remote);
  final List<AskodoxConversationSnapshot> remote;
  final pushed = <String>[];
  @override
  Future<void> push(AskodoxConversationSnapshot snapshot) async => pushed.add(snapshot.id);
  @override
  Future<List<AskodoxConversationSnapshot>?> pull() async => remote;
}

AskodoxConversationSnapshot _s(String id, String title, String at) => AskodoxConversationSnapshot(
    id: id, title: title, updatedAt: DateTime.parse(at), status: AskodoxConversationStatus.active, data: {'t': title});

void main() {
  test('after a reinstall History comes back from the account; the newer copy wins; nothing local is lost', () async {
    SharedPreferences.setMockInitialValues({});
    final backup = _Backup([_s('a', 'TV 43 inch', '2026-10-20T10:00:00'), _s('b', 'Chicken (server)', '2026-10-22T10:00:00')]);
    final archive = AskodoxConversationArchive(backup: backup);
    await archive.save(_s('b', 'Chicken (phone, older)', '2026-10-21T10:00:00'));
    await archive.save(_s('c', 'Only on this phone', '2026-10-23T10:00:00'));
    expect(backup.pushed, ['b', 'c'], reason: 'every save is mirrored to the account');
    final added = await archive.restore();
    expect(added, 1);
    expect([for (final s in archive.state) s.title], ['Only on this phone', 'Chicken (server)', 'TV 43 inch']);
    expect(backup.pushed.last, 'c', reason: 'phone-only conversations go up too');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('askodox.conversation_archive.v1'), contains('TV 43 inch'), reason: 'kept on the phone too');
  });

  test('not signed in: nothing is sent and nothing is pulled', () async {
    SharedPreferences.setMockInitialValues({});
    var called = false;
    final backup = ApiHistoryBackup(() => throw StateError('no client'), () {
      called = true;
      return 'OTP_VERIFIED';
    });
    expect(await backup.pull(), isNull);
    await backup.push(_s('x', 'x', '2026-10-23T10:00:00'));
    expect(called, isTrue);
  });
}
