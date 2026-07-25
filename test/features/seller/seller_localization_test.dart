import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/seller/presentation/seller_shell.dart';
import 'package:podx/generated/l10n/app_localizations.dart';

void main() {
  testWidgets('seller navigation uses Telugu translations', (tester) async {
    final router = GoRouter(
      initialLocation: '/seller/dashboard',
      routes: [
        GoRoute(
          path: '/seller/dashboard',
          builder: (context, state) => const SellerShell(child: SizedBox()),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('te'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    expect(find.text('విక్రేత డ్యాష్‌బోర్డ్'), findsOneWidget);
    expect(find.text('ఉత్పత్తులు'), findsOneWidget);
    expect(find.text('అభ్యర్థనలు'), findsOneWidget);
    expect(find.text('విశ్లేషణలు'), findsOneWidget);
  });
}
