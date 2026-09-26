import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Newest-first list of saved conversations (SharedPreferences, per device).
class AskodoxConversationArchive extends StateNotifier<List<AskodoxConversationSnapshot>> {
  AskodoxConversationArchive() : super(const []) {
    _load();
  }

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

final askodoxConversationArchiveProvider =
    StateNotifierProvider<AskodoxConversationArchive, List<AskodoxConversationSnapshot>>(
  (ref) => AskodoxConversationArchive(),
);

/// Cross-screen requests into Main Chat: reopen a History conversation,
/// start a clean "New ask", or ask something chosen in Explore. Each value
/// carries a nonce so repeating the same request still fires.
class AskodoxChatRequest {
  AskodoxChatRequest.restore(this.conversationId)
      : prompt = null,
        newConversation = false;
  AskodoxChatRequest.newConversation()
      : conversationId = null,
        prompt = null,
        newConversation = true;
  AskodoxChatRequest.ask(this.prompt)
      : conversationId = null,
        newConversation = false;

  final String? conversationId;
  final String? prompt;
  final bool newConversation;
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
