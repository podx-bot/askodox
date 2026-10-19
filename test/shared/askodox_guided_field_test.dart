import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:podx/shared/widgets/askodox_guided_field.dart';
import 'package:podx/shared/widgets/askodox_mascot.dart';

Future<(TextEditingController, List<String>)> _pump(WidgetTester tester, AskodoxFieldGuide guide) async {
  final controller = TextEditingController();
  final spoken = <String>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxGuideSpeakerProvider.overrideWithValue((text, language) async => spoken.add(text))],
    child: MaterialApp(
      home: Scaffold(
        body: Column(children: [
          AskodoxGuidedField(fieldKey: const Key('f'), controller: controller, label: 'Name', guide: guide),
          const TextField(key: Key('other')),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (controller, spoken);
}

void main() {
  testWidgets('example in the blank; wrong -> "write it like this"; right -> tick', (tester) async {
    final (controller, _) = await _pump(tester, AskodoxFieldGuides.name);
    expect(find.text('e.g. Lakshmi Devi'), findsOneWidget, reason: 'example shown inside the empty field');
    await tester.enterText(find.byKey(const Key('f')), '9876543210');
    await tester.pumpAndSettle();
    expect(find.text('A name has no numbers. Write it like: Lakshmi Devi'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxFieldOk-f')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxMascot-confused')), findsOneWidget, reason: 'ASKO looks confused');
    await tester.enterText(find.byKey(const Key('f')), 'Lakshmi Devi');
    await tester.pumpAndSettle();
    expect(find.textContaining('Write it like'), findsNothing);
    expect(find.byKey(const ValueKey('askodoxFieldOk-f')), findsOneWidget, reason: 'green tick when right');
    expect(find.byKey(const ValueKey('askodoxMascot-success')), findsOneWidget);
    expect(controller.text, 'Lakshmi Devi');
  });

  testWidgets('no complaint for a just-started word; optional fields may stay empty', (tester) async {
    await _pump(tester, AskodoxFieldGuides.email);
    await tester.enterText(find.byKey(const Key('f')), 'ab');
    await tester.pumpAndSettle();
    expect(find.textContaining('e-mail looks like'), findsNothing, reason: 'not judged after two letters');
    await tester.tap(find.byKey(const Key('other')));
    await tester.pumpAndSettle();
    expect(find.text('An e-mail looks like: name@gmail.com'), findsOneWidget, reason: 'judged once the field is left');
    await tester.enterText(find.byKey(const Key('f')), '');
    await tester.pumpAndSettle();
    expect(find.textContaining('e-mail looks like'), findsNothing);
  });

  testWidgets('the mascot "?" explains the field and says it aloud', (tester) async {
    final (_, spoken) = await _pump(tester, AskodoxFieldGuides.offerValue);
    await tester.tap(find.byKey(const ValueKey('askodoxFieldHelp-f')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxFieldHelpText')), findsOneWidget);
    expect(find.text('friend, the discount: an amount in rupees, or a percent with %.'), findsOneWidget,
        reason: 'ASKO addresses the person by the chosen relation (default friend)');
    expect(spoken.single, contains('The discount'));
  });

  test('field checks', () {
    expect(AskodoxFieldGuides.offerValue.problem('10%', false), isNull);
    expect(AskodoxFieldGuides.offerValue.problem('₹ 50', false), isNull);
    expect(AskodoxFieldGuides.offerValue.problem('150%', false), contains('100%'));
    expect(AskodoxFieldGuides.offerValue.problem('ten', false), isNotNull);
    expect(AskodoxFieldGuides.price.problem('1,250', false), isNull);
    expect(AskodoxFieldGuides.price.problem('0', false), isNotNull);
    expect(AskodoxFieldGuides.gstin.problem('37abcde1234f1z5', false), isNull);
    expect(AskodoxFieldGuides.gstin.problem('12345', false), isNotNull);
    expect(AskodoxFieldGuides.town.problem('Vuyyuru, Krishna district', false), isNull);
    expect(AskodoxFieldGuides.name.problem('లక్ష్మీ దేవి', true), isNull, reason: 'Telugu letters are letters');
    expect(AskodoxFieldGuides.name.problem('12', true), contains('అంకెలు'));
  });

  test('every mascot picture exists', () {
    for (final role in AskodoxMascotRole.values) {
      expect(File(AskodoxMascot.assetFor(role, AskodoxMascotMood.happy)).existsSync(), isTrue, reason: role.name);
    }
    for (final mood in AskodoxMascotMood.values) {
      expect(File(AskodoxMascot.assetFor(AskodoxMascotRole.asko, mood)).existsSync(), isTrue, reason: mood.name);
    }
  });
}
