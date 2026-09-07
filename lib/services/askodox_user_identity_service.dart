import 'package:shared_preferences/shared_preferences.dart';

class AskodoxUserIdentityService {
  const AskodoxUserIdentityService();

  static const _mobileKey = 'askodox.profile.mobile';

  Future<String?> currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final mobile = prefs.getString(_mobileKey)?.trim();
    if (mobile == null || mobile.isEmpty) return null;

    final normalized = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return null;
    return 'mobile:$normalized';
  }
}
