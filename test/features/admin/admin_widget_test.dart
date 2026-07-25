import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/admin/presentation/admin_screens.dart';

void main() {
  testWidgets('admin login displays role selection and mock access', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AdminLoginScreen())));
    expect(find.text('PODX Admin'), findsOneWidget);
    expect(find.text('Admin role'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
