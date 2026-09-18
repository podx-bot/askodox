import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_accounts.dart';
import 'auth_models.dart';
import 'session_manager.dart';

class AuthController extends StateNotifier<AuthSession> {
  AuthController(this.manager) : super(AuthSession.loggedOut);

  final SessionManager manager;

  Future<void> restore() async => state = await manager.restore();

  // Added 2026-09-16 (round 10): `token` now carries the REAL signed
  // session token returned by POST /onboarding/otp/verify (see
  // session_tokens.py on the backend) -- not a fabricated placeholder.
  // Callers (see main.dart's _restoreOnboardingIdentity) read it back out
  // of SharedPreferences (saved by onboarding_screen.dart's _finish()) and
  // pass it through here. It is optional only so this method still
  // compiles against any old caller; a null/blank token falls back to the
  // old 'OTP_VERIFIED' placeholder, which the backend will now correctly
  // reject with 401 on every order endpoint -- see orders.py's
  // _authenticated_app_user.
  Future<void> completeOnboarding({
    required String mobile,
    required String displayName,
    String? token,
  }) async {
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    final stableId = digits.isEmpty ? 'onboarding-user' : 'phone-$digits';
    final realToken = token?.trim();
    final session = AuthSession(
      user: AuthUser(
        id: stableId,
        role: UserRole.buyer,
        displayName: displayName.trim(),
      ),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: (realToken != null && realToken.isNotEmpty) ? realToken : 'OTP_VERIFIED',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await manager.save(session);
    state = session;
  }

  Future<void> setDemoRole(UserRole role) async {
    final s = AuthSession(
      user: AuthUser(
        id: 'demo-${role.name}',
        role: role,
        displayName: 'Demo ${role.name}',
      ),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 'DEMO_ONLY',
      expiresAt: DateTime.now().add(const Duration(hours: 8)),
    );
    await manager.save(s);
    state = s;
  }

  Future<void> setDemoAccount(DemoAccount account) async {
    final s = AuthSession(
      user: account.user,
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 'DEMO_ONLY',
      expiresAt: DateTime.now().add(const Duration(hours: 8)),
    );
    await manager.save(s);
    state = s;
  }

  Future<void> simulate(AuthStatus status) async {
    final s = state.copyWith(
      status: status,
      clearUser: status == AuthStatus.loggedOut,
    );
    await manager.save(s);
    state = s;
  }

  Future<void> logout() async {
    await manager.logout();
    state = AuthSession.loggedOut;
  }

  Future<void> refresh() async => state = await manager.refresh();
}
