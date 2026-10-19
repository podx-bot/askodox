import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/profile/presentation/profile_screen.dart';
import 'package:podx/features/selling/presentation/sell_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> files) async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File('$root/bin/cache/artifacts/material_fonts/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _Growth implements GrowthRepository {
  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async => const [];
  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async => null;
  @override
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId}) async => null;
  @override
  Future<AskodoxCatalogDraft?> draftListing(
          {String text = '', Map<String, Object?>? imageAnalysis, Map<String, Object?>? videoAnalysis}) async =>
      const AskodoxCatalogDraft(id: 1, draft: {'subject': 'Cotton saree', 'price': 1200}, missing: []);
  @override
  Future<int?> publishDraft(int draftId, Map<String, Object?> reviewed) async => 1;
  @override
  Future<List<AskodoxLead>> leads() async => const [];
  @override
  Future<bool> expressInterest(String requestId) async => true;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await _font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  for (final active in ['buyer', 'seller']) {
    testWidgets('profile $active', (tester) async {
      SharedPreferences.setMockInitialValues({
        'askodox.roles.v1': '{"owned":["buyer","seller","deliveryPartner"],"active":"$active"}',
      });
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey();
      final router = GoRouter(initialLocation: '/profile', routes: [
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ]);
      await tester.pumpWidget(ProviderScope(
        child: RepaintBoundary(
          key: key,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
            routerConfig: router,
          ),
        ),
      ));
      await _frames(tester);
      await _shot(tester, key, 'profile_$active');
    });
  }

  testWidgets('sell sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [growthRepositoryProvider.overrideWithValue(_Growth())],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  TextButton(key: const Key('open'), onPressed: () => showAskodoxSellSheet(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('askodoxSellDescribe')), 'Cotton saree 6 m, ₹1200');
    await tester.tap(find.byKey(const Key('askodoxSellMakeDraft')));
    await _frames(tester);
    await _shot(tester, key, 'sell_sheet');
  });
}
