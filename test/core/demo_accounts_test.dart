import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/auth/auth_service.dart';
import 'package:podx/core/demo/demo_accounts.dart';

void main() {
  test('every demo module has Party A and Party B accounts', () {
    for (final module in DemoModule.values) {
      final accounts = DemoAccounts.forModule(module);
      expect(accounts.length, 2, reason: module.name);
      expect(accounts.map((a) => a.party).toSet(), {DemoParty.a, DemoParty.b});
      expect(accounts.every((a) => a.loginId.startsWith('demo.')), isTrue);
    }
  });

  test('demo login ids are unique and clearly isolated', () {
    final ids = DemoAccounts.all.map((a) => a.loginId).toList();
    expect(ids.toSet().length, ids.length);
    expect(DemoAccounts.all.every((a) => a.id.startsWith('demo-')), isTrue);
  });

  test('mock authentication logs into requested demo party', () async {
    final auth = MockAuthenticationService();
    final session = await auth.loginWithEmail(
      'demo.rides.driver',
      DemoAccounts.demoPassword,
    );
    expect(session.status, AuthStatus.loggedIn);
    expect(session.role, UserRole.seller);
    expect(session.user?.displayName, 'Demo Driver');
    expect(session.tokenPlaceholder, 'DEMO_ONLY');
  });
}
