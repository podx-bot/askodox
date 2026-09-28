import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConversationTurnRecord {
  const ConversationTurnRecord({
    required this.text,
    required this.isUser,
    this.attachments = const [],
    this.context = '',
  });

  /// What the person wrote (or ASKODOX replied) -- exactly as shown.
  final String text;
  final bool isUser;

  /// Attachments sent with this turn: {name, kind, id} (the backend's
  /// attachment reference; the bytes are not kept on the phone's history).
  final List<Map<String, String>> attachments;

  /// Facts the backend extracted from those attachments. Never shown as the
  /// person's words; used as conversation context for later turns.
  final String context;

  /// The turn as the reasoning sees it: words + attachment facts.
  String get reasoningText => context.isEmpty ? text : (text.isEmpty ? context : '$text\n$context');

  Map<String, Object?> toJson() => {
        'text': text,
        'isUser': isUser,
        if (attachments.isNotEmpty) 'attachments': attachments,
        if (context.isNotEmpty) 'context': context,
      };

  static ConversationTurnRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    final text = map['text']?.toString().trim() ?? '';
    final isUser = map['isUser'];
    final attachments = [
      for (final item in (map['attachments'] is List ? map['attachments'] as List : const []))
        if (item is Map)
          {for (final e in item.entries) '${e.key}': '${e.value ?? ''}'},
    ];
    if ((text.isEmpty && attachments.isEmpty) || isUser is! bool) return null;
    return ConversationTurnRecord(
      text: text,
      isUser: isUser,
      attachments: attachments,
      context: map['context']?.toString() ?? '',
    );
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
