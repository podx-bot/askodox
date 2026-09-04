import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_orb.dart';
import 'package:podx/features/search/domain/search_models.dart';

void main() {
  Widget host(AskodoxOrbState state) => MaterialApp(
        home: Scaffold(
          body: Center(child: AskodoxOrb(state: state)),
        ),
      );

  test('maps ASKODOX voice lifecycle to home orb states', () {
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.idle),
      AskodoxOrbState.idle,
    );
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.listening),
      AskodoxOrbState.listening,
    );
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.processing),
      AskodoxOrbState.thinking,
    );
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.speaking),
      AskodoxOrbState.speaking,
    );
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.result),
      AskodoxOrbState.idle,
    );
    expect(
      askodoxOrbStateForVoice(VoiceSearchState.error),
      AskodoxOrbState.idle,
    );
  });

  testWidgets('renders every ASKODOX orb state accessibly', (tester) async {
    const cases = <AskodoxOrbState, String>{
      AskodoxOrbState.idle: 'ASKODOX ready',
      AskodoxOrbState.listening: 'ASKODOX listening',
      AskodoxOrbState.thinking: 'ASKODOX thinking',
      AskodoxOrbState.speaking: 'ASKODOX speaking',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(host(entry.key));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const Key('askodoxHomeOrb')), findsOneWidget);
      expect(find.bySemanticsLabel(entry.value), findsOneWidget);
    }
  });

  testWidgets('changes robot cue when state changes', (tester) async {
    await tester.pumpWidget(host(AskodoxOrbState.listening));
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget);

    await tester.pumpWidget(host(AskodoxOrbState.thinking));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Icons.psychology_rounded), findsOneWidget);

    await tester.pumpWidget(host(AskodoxOrbState.speaking));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });
}
