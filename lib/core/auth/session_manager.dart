import '../persistence/local_store.dart'; import 'auth_models.dart'; import 'auth_service.dart';
class SessionManager { SessionManager(this.store,this.auth); final LocalStore store; final AuthenticationService auth; AuthSession _current=AuthSession.loggedOut; AuthSession get current=>_current;
 Future<AuthSession> restore() async { final raw=await store.read<Map<String,Object?>>(LocalKeys.session); if(raw==null)return _current=AuthSession.loggedOut; final restored=AuthSession.fromJson(raw); _current=restored.isExpired?restored.copyWith(status:AuthStatus.sessionExpired):restored; return _current; }
 Future<void> save(AuthSession session) async{_current=session; await store.write(LocalKeys.session,session.toJson());}
 Future<AuthSession> refresh() async{final refreshed=await auth.refresh(_current);await save(refreshed);return refreshed;}
 Future<void> logout() async{await auth.logout();_current=AuthSession.loggedOut;await store.remove(LocalKeys.session);}
}
