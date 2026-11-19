import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/askodox_tile_grid.dart';
import 'package:podx/shared/widgets/chat_pins.dart';

void main() {
  testWidgets('a tile with a screen has a pin button that pins it above the chat', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AskodoxTileGrid(tiles: [
              AskodoxTile(id: 'sale', icon: Icons.receipt_long, title: 'New bill', pinRoute: '/pos/1/sale', onTap: () {}),
              AskodoxTile(id: 'plain', icon: Icons.settings, title: 'Plain', onTap: () {}),
            ]),
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('askodoxPin-sale')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPin-plain')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxPin-sale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxChatPinAdd')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxTileGrid)));
    expect(container.read(askodoxChatPinsProvider).pins.map((p) => p.route), ['/pos/1/sale']);
  });
}
