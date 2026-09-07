import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AskodoxUserIdentityService {
  const AskodoxUserIdentityService();

  static const _sessionKey = 'askodox.local.session';
  static const _mobileKey = 'askodox.profile.mobile';

  Future<String?> currentUserId() async {
    final prefs = await SharedPreferences.getInstance();

    // The authenticated ASKODOX app session is the canonical app identity used
    // by matching, deal inbox, and in-app notification flows. Prefer it so
    // reminders share the same user boundary as the rest of the app.
    final sessionUserId = _sessionUserId(prefs.getString(_sessionKey));
    if (sessionUserId != null) {
      return sessionUserId.startsWith('app-')
          ? sessionUserId
          : 'app-$sessionUserId';
    }

    // Registration persists the verified mobile independently of the auth
    // session. Keep this as a recovery path while session restoration is still
    // in progress, rather than inventing a guest/demo identity.
    final mobile = prefs.getString(_mobileKey)?.trim();
    if (mobile == null || mobile.isEmpty) return null;

    final normalized = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return null;
    return 'mobile:$normalized';
  }

  String? _sessionUserId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final user = decoded['user'];
      if (user is! Map) return null;
      final id = user['id']?.toString().trim();
      if (id == null || id.isEmpty) return null;
      return id;
    } on FormatException {
      return null;
    }
  }
}
