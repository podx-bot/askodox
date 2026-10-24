import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../companion/companion_hub.dart';

/// History status filters.
enum AskodoxConversationStatus { active, matched, completed }

/// One ASKODOX conversation exactly as it was: turns, per-turn results and
/// deals, role notices, the deal-brain state, active role and which options
/// were already discussed or requested.
class AskodoxConversationSnapshot {
  const AskodoxConversationSnapshot({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.status,
    required this.data,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final AskodoxConversationStatus status;

  /// Opaque screen state (see AskodoxPrimaryHomeScreen._snapshotData).
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'status': status.name,
        'data': data,
      };

  static AskodoxConversationSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final status = AskodoxConversationStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => AskodoxConversationStatus.active,
    );
    return AskodoxConversationSnapshot(
      id: id,
      title: json['title']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      status: status,
      data: json['data'] is Map ? (json['data'] as Map).cast<String, Object?>() : const {},
    );
  }
}

/// The account's copy of History on the server (`/api/me/conversations`), so
/// uninstalling, resetting or a new phone never loses it.
abstract interface class AskodoxHistoryBackup {
  /// Mirrors one saved conversation (best effort; never blocks the chat).
  Future<void> push(AskodoxConversationSnapshot snapshot);

  /// Everything the account has backed up; null when not signed in / offline.
  Future<List<AskodoxConversationSnapshot>?> pull();
}

/// Token-proven calls only: without a real session token nothing is sent.
class ApiHistoryBackup implements AskodoxHistoryBackup {
  ApiHistoryBackup(this._client, this._token);
  final ApiClient Function() _client;
  final String? Function() _token;

  String? get _real {
    try {
      final t = _token();
      return t == null || t.isEmpty || t == 'OTP_VERIFIED' || t == 'DEMO_ONLY' ? null : t;
    } catch (_) {
      return null; // no session available (tests / early start)
    }
  }

  @override
  Future<void> push(AskodoxConversationSnapshot snapshot) async {
    final token = _real;
    if (token == null) return;
    try {
      await _client().put<Object?>('/api/me/conversations/${Uri.encodeComponent(snapshot.id)}',
          body: {'snapshot': snapshot.toJson()}, options: ApiRequestOptions(authToken: token));
    } catch (_) {}
  }

  @override
  Future<List<AskodoxConversationSnapshot>?> pull() async {
    final token = _real;
    if (token == null) return null;
    try {
      final out = await _client().get<Object?>('/api/me/conversations', options: ApiRequestOptions(authToken: token));
      if (out is! ApiSuccess<Object?>) return null;
      final data = out.data;
      final list = data is Map ? data['conversations'] : null;
      if (list is! List) return null;
      return list.map(AskodoxConversationSnapshot.fromJson).whereType<AskodoxConversationSnapshot>().toList();
    } catch (_) {
      return null;
    }
  }
}

/// Newest-first list of saved conversations: on the phone (SharedPreferences,
/// fast + offline) AND backed up to the account, restored after a reinstall.
class AskodoxConversationArchive extends StateNotifier<List<AskodoxConversationSnapshot>> {
  AskodoxConversationArchive({this.backup}) : super(const []) {
    _load();
  }

  final AskodoxHistoryBackup? backup;

  static const _key = 'askodox.conversation_archive.v1';
  static const _currentKey = 'askodox.conversation_current.v1';
  static const _limit = 50;

  Future<void>? _loading;

  Future<void> ready() => _loading ?? Future<void>.value();

  AskodoxConversationSnapshot? byId(String id) {
    for (final item in state) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> save(AskodoxConversationSnapshot snapshot) async {
    await ready();
    state = [snapshot, ...state.where((item) => item.id != snapshot.id)].take(_limit).toList();
    await _persist(currentId: snapshot.id);
    final b = backup;
    if (b != null) unawaited(b.push(snapshot));
  }

  /// Brings back the account's History (after a reinstall / on a new phone)
  /// and merges it with what is on this phone: per conversation the newer
  /// copy wins; nothing on the phone is dropped.
  Future<int> restore() async {
    final b = backup;
    if (b == null) return 0;
    await ready();
    final remote = await b.pull();
    if (remote == null || remote.isEmpty || !mounted) return 0;
    final byId = {for (final item in state) item.id: item};
    var added = 0;
    for (final r in remote) {
      final local = byId[r.id];
      if (local == null || r.updatedAt.isAfter(local.updatedAt)) {
        if (local == null) added++;
        byId[r.id] = r;
      }
    }
    final merged = byId.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = merged.take(_limit).toList();
    await _persist();
    // Conversations only on this phone (made before signing in) go up too.
    for (final item in state) {
      if (!remote.any((r) => r.id == item.id)) unawaited(b.push(item));
    }
    return added;
  }

  Future<String?> currentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> setCurrent(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_currentKey);
      } else {
        await prefs.setString(_currentKey, id);
      }
    } catch (_) {}
  }

  void _load() {
    _loading = () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_key);
        if (raw == null || !mounted) return;
        final decoded = jsonDecode(raw);
        if (decoded is! List) return;
        state = decoded
            .map(AskodoxConversationSnapshot.fromJson)
            .whereType<AskodoxConversationSnapshot>()
            .toList();
      } catch (_) {
        // A corrupt archive starts empty rather than crashing History.
      }
    }();
  }

  Future<void> _persist({String? currentId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final item in state) item.toJson()]));
      if (currentId != null) await prefs.setString(_currentKey, currentId);
    } catch (_) {}
  }
}

/// Override in tests; production mirrors History to the signed-in account.
final askodoxHistoryBackupProvider = Provider<AskodoxHistoryBackup?>((ref) => ApiHistoryBackup(
      () => ref.read(apiClientProvider),
      () => ref.read(authSessionProvider).user == null ? null : ref.read(authSessionProvider).tokenPlaceholder,
    ));

final askodoxConversationArchiveProvider =
    StateNotifierProvider<AskodoxConversationArchive, List<AskodoxConversationSnapshot>>((ref) {
  final archive = AskodoxConversationArchive(backup: ref.watch(askodoxHistoryBackupProvider));
  // Restore once at start (a signed-in reinstall) and again whenever someone signs in.
  unawaited(archive.restore());
  ref.listen(authSessionProvider, (previous, next) {
    if (next.user != null && previous?.user == null) unawaited(archive.restore());
  });
  return archive;
});

/// Cross-screen requests into Main Chat: reopen a History conversation,
/// start a clean "New ask", or ask something chosen in Explore. Each value
/// carries a nonce so repeating the same request still fires.
class AskodoxChatRequest {
  AskodoxChatRequest.restore(this.conversationId)
      : prompt = null,
        newConversation = false,
        voice = false,
        hubAction = null,
        search = false,
        videoRef = null;
  AskodoxChatRequest.newConversation()
      : conversationId = null,
        prompt = null,
        newConversation = true,
        voice = false,
        hubAction = null,
        search = false,
        videoRef = null;
  AskodoxChatRequest.ask(this.prompt, {this.search = false})
      : conversationId = null,
        newConversation = false,
        voice = false,
        hubAction = null,
        videoRef = null;

  /// The centre ASKODOX button: open Main Chat and start listening at once.
  AskodoxChatRequest.voice()
      : conversationId = null,
        prompt = null,
        newConversation = false,
        voice = true,
        hubAction = null,
        search = false,
        videoRef = null;

  /// A companion action (Voice, Chat, Camera, Photos, Video, Files,
  /// Location) chosen outside Main Chat -- nav avatar or floating companion
  /// -- carried into the SAME conversation.
  AskodoxChatRequest.action(AskodoxHubAction this.hubAction)
      : conversationId = null,
        prompt = null,
        newConversation = false,
        voice = false,
        search = false,
        videoRef = null;

  /// "Ask about this video": Main Chat continues with THIS video as the
  /// context ([videoRef] `nv_<id>`, [prompt] = its title).
  AskodoxChatRequest.aboutVideo(String this.videoRef, String title)
      : conversationId = null,
        prompt = title,
        newConversation = false,
        voice = false,
        hubAction = null,
        search = false;

  final String? videoRef;

  final AskodoxHubAction? hubAction;
  final String? conversationId;
  final String? prompt;
  final bool newConversation;
  final bool voice;

  /// A next step ASKODOX itself offered ("AC service near me" from a video):
  /// always a search with what is known, never routed as general chat.
  final bool search;
}

final askodoxChatRequestProvider = StateProvider<AskodoxChatRequest?>((ref) => null);

/// True until Main Chat has handled this app process's first mount. The
/// root ProviderScope lives exactly as long as the process, so a genuine
/// launch/relaunch (or a restart after a crash) starts a fresh ask, while
/// in-app navigation during the same session keeps the active chat.
final askodoxFreshLaunchProvider = Provider<AskodoxLaunchSession>((ref) => AskodoxLaunchSession());

class AskodoxLaunchSession {
  bool _fresh = true;

  /// True exactly once per app process: the first Main Chat mount.
  bool consumeFreshLaunch() {
    final fresh = _fresh;
    _fresh = false;
    return fresh;
  }
}
