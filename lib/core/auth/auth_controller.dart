import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_accounts.dart';
import 'auth_models.dart';
import 'session_manager.dart';

class AuthController extends StateNotifier<AuthSession> {
  AuthController(this.manager) : super(AuthSession.loggedOut);

  final SessionManager manager;

  Future<void> restore() async => state = await manager.restore();

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
