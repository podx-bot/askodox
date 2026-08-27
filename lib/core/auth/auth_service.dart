import '../demo/demo_accounts.dart';
import 'auth_models.dart';

abstract interface class AuthenticationService {
  Future<AuthSession> requestMobileOtp(String mobile);
  Future<AuthSession> verifyOtp(String requestId, String otp);
  Future<AuthSession> loginWithEmail(String email, String password);
  Future<AuthSession> socialLogin(String provider);
  Future<AuthSession> refresh(AuthSession session);
  Future<void> logout();
  Future<void> deleteAccount();
}

class MockAuthenticationService implements AuthenticationService {
  AuthSession _session = AuthSession.loggedOut;

  @override
  Future<AuthSession> requestMobileOtp(String mobile) async =>
      _session = const AuthSession(status: AuthStatus.otpRequested);

  @override
  Future<AuthSession> verifyOtp(String requestId, String otp) async =>
      _session = const AuthSession(status: AuthStatus.otpVerified);

  @override
  Future<AuthSession> loginWithEmail(String email, String password) async {
    final demo = DemoAccounts.byLoginId(email);
    if (demo != null && password == DemoAccounts.demoPassword) {
      return _session = AuthSession(
        user: demo.user,
        status: AuthStatus.loggedIn,
        tokenPlaceholder: 'DEMO_ONLY',
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
      );
    }

    // Preserve the generic mock login used by existing development tests.
    return _session = AuthSession(
      user: const AuthUser(
        id: 'demo',
        role: UserRole.buyer,
        displayName: 'Demo Buyer',
      ),
      status: AuthStatus.loggedIn,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<AuthSession> socialLogin(String provider) =>
      loginWithEmail('demo@askodox.local', '');

  @override
  Future<AuthSession> refresh(AuthSession session) async =>
      _session = session.copyWith(
        status: AuthStatus.loggedIn,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  @override
  Future<void> logout() async {
    _session = AuthSession.loggedOut;
  }

  @override
  Future<void> deleteAccount() => logout();
}
