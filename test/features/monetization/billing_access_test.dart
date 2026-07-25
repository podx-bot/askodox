import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/auth/route_guard.dart';
void main(){ const guard=RouteGuard(); AuthSession session(UserRole role)=>AuthSession(status:AuthStatus.loggedIn,user:AuthUser(id:'x',role:role)); test('billing routes enforce seller and admin roles',(){expect(guard.redirect(session(UserRole.buyer),'/seller/plans'),'/forbidden');expect(guard.redirect(session(UserRole.seller),'/seller/plans'),isNull);expect(guard.redirect(session(UserRole.seller),'/admin/subscriptions'),'/forbidden');expect(guard.redirect(session(UserRole.admin),'/admin/subscriptions'),isNull);});}
