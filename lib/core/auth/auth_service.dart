import 'auth_models.dart';
abstract interface class AuthenticationService { Future<AuthSession> requestMobileOtp(String mobile); Future<AuthSession> verifyOtp(String requestId,String otp); Future<AuthSession> loginWithEmail(String email,String password); Future<AuthSession> socialLogin(String provider); Future<AuthSession> refresh(AuthSession session); Future<void> logout(); Future<void> deleteAccount(); }
class MockAuthenticationService implements AuthenticationService {
  AuthSession _session=AuthSession.loggedOut;
  @override Future<AuthSession> requestMobileOtp(String mobile) async=>_session=const AuthSession(status:AuthStatus.otpRequested);
  @override Future<AuthSession> verifyOtp(String requestId,String otp) async=>_session=const AuthSession(status:AuthStatus.otpVerified);
  @override Future<AuthSession> loginWithEmail(String email,String password) async=>_session=AuthSession(user:const AuthUser(id:'demo',role:UserRole.buyer,displayName:'Demo Buyer'),status:AuthStatus.loggedIn,expiresAt:DateTime.now().add(const Duration(hours:1)));
  @override Future<AuthSession> socialLogin(String provider)=>loginWithEmail('demo@podx.local','');
  @override Future<AuthSession> refresh(AuthSession session) async=>_session=session.copyWith(status:AuthStatus.loggedIn,expiresAt:DateTime.now().add(const Duration(hours:1)));
  @override Future<void> logout() async{_session=AuthSession.loggedOut;}
  @override Future<void> deleteAccount()=>logout();
}
