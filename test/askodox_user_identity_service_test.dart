import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podx/services/askodox_user_identity_service.dart';

void main() {
  const service = AskodoxUserIdentityService();

  test('prefers authenticated ASKODOX app session identity', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.local.session': jsonEncode(<String, Object?>{
        'user': <String, Object?>{
          'id': 'buyer-42',
          'role': 'buyer',
          'displayName': 'Buyer',
          'profileComplete': true,
        },
        'status': 'loggedIn',
        'expiresAt': null,
      }),
      'askodox.profile.mobile': '+91 98765 43210',
    });

    expect(await service.currentUserId(), 'app-buyer-42');
  });

  test('keeps an existing app-prefixed session id unchanged', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.local.session': jsonEncode(<String, Object?>{
        'user': <String, Object?>{'id': 'app-user-7'},
        'status': 'loggedIn',
      }),
    });

    expect(await service.currentUserId(), 'app-user-7');
  });

  test('falls back to verified mobile while auth session is unavailable', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'askodox.profile.mobile': '+91 98765 43210',
    });

    expect(await service.currentUserId(), 'mobile:+919876543210');
  });

  test('does not invent a guest identity', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    expect(await service.currentUserId(), isNull);
  });
}
