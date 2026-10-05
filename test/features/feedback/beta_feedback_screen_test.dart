import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/feedback/presentation/beta_feedback_screen.dart';
import 'package:podx/features/staff/askodox_staff_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Staff implements AskodoxStaffRepository {
  final sent = <Map<String, Object?>>[];

  @override
  Future<String?> sendFeedback({required String kind, required String message, String feature = '',
      String appVersion = '', String installId = '', bool consentDiagnostics = false,
      Map<String, String> diagnostics = const {}, String? token}) async {
    sent.add({'kind': kind, 'message': message, 'consent': consentDiagnostics, 'diagnostics': diagnostics});
    return 'FB-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('small phone + keyboard + gesture bar: Submit is reachable and sends to the team', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    // Gesture navigation bar (bottom padding) and an open keyboard.
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewInsets = const FakeViewPadding(bottom: 560);
    addTearDown(tester.view.reset);
    final staff = _Staff();
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxStaffRepositoryProvider.overrideWithValue(staff)],
      child: const MaterialApp(home: BetaFeedbackScreen()),
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'The location search showed a black screen');
    final submit = find.byKey(const Key('askodoxFeedbackSubmit'));
    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    final box = tester.getRect(submit);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(box.bottom, lessThanOrEqualTo(screen.height - 560 / 2), reason: 'above the keyboard, never clipped');
    await tester.tap(submit);
    // PackageInfo / SharedPreferences resolve on real async.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(staff.sent, hasLength(1), reason: 'feedback reaches /api/feedback (admin Early Access dashboard)');
    expect(staff.sent.single['consent'], isFalse, reason: 'no diagnostics unless the user switches them on');
    expect(find.text('Sent to the ASKODOX team. Thank you!'), findsOneWidget);
  });
}
