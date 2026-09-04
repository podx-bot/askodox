import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConversationTurnRecord {
  const ConversationTurnRecord({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  Map<String, Object?> toJson() => {
        'text': text,
        'isUser': isUser,
      };

  static ConversationTurnRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    final text = map['text']?.toString().trim() ?? '';
    final isUser = map['isUser'];
    if (text.isEmpty || isUser is! bool) return null;
    return ConversationTurnRecord(text: text, isUser: isUser);
  }
}

class ConversationTurnStore {
  const ConversationTurnStore();

  static const _storageKey = 'askodox.active_conversation_turns.v1';

  Future<List<ConversationTurnRecord>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return List<ConversationTurnRecord>.unmodifiable(
        decoded.map(ConversationTurnRecord.fromJson).whereType<ConversationTurnRecord>(),
      );
    } catch (_) {
      await clear();
      return const [];
    }
  }

  Future<void> save(List<ConversationTurnRecord> turns) async {
    final prefs = await SharedPreferences.getInstance();
    if (turns.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    await prefs.setString(
      _storageKey,
      jsonEncode(turns.map((turn) => turn.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
