import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/askodox_tile_grid.dart';
import 'package:podx/shared/widgets/page_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('press and hold a tile, drag it onto another: the order is saved (phone style)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AskodoxTileGrid(layoutId: 'drag-test', tiles: [
              for (final id in ['a', 'b', 'c'])
                AskodoxTile(id: id, icon: Icons.circle, title: 'Tile $id', onTap: () {}),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.byKey(const ValueKey('askodoxDrag-a')));
    final to = tester.getCenter(find.byKey(const ValueKey('askodoxDrop-c')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(to, timeStamp: const Duration(milliseconds: 900));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(container.read(askodoxPageLayoutProvider)['drag-test']?.order, ['b', 'a', 'c']);
  });
}
