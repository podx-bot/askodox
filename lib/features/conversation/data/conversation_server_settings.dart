import 'package:shared_preferences/shared_preferences.dart';

class ConversationServerSettings {
  static const _baseUrlKey = 'askodox.conversation.baseUrl';
  static const _senderIdKey = 'askodox.conversation.senderId';

  const ConversationServerSettings();

  Future<String> loadBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getString(_baseUrlKey) ?? '').trim();
  }

  Future<void> saveBaseUrl(String value) async {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Enter a valid https:// server URL.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, normalized);
  }

  Future<void> clearBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_baseUrlKey);
  }

  Future<String> loadOrCreateSenderId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = (preferences.getString(_senderIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;

    final created = 'app-${DateTime.now().microsecondsSinceEpoch}';
    await preferences.setString(_senderIdKey, created);
    return created;
  }
}
