import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/brand/brand_config.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/shared/widgets/askodox_ai_state.dart';
import 'package:podx/shared/widgets/askodox_components.dart';

void main() {
  test('ASKODOX master brand copy is centralized', () {
    expect(BrandConfig.displayName, 'ASKODOX');
    expect(BrandConfig.tagline, 'Ask Anything. Get It Done.');
    expect(
      BrandConfig.localPromise,
      'Ask anything local. Buy, sell, work, services or rides.',
    );
  });

  testWidgets('AI states expose semantic visual and labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: AskodoxAiStateVisual(
              state: AskodoxAiState.listening,
              showLabel: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('askodoxAiStateVisual')), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets('composer sends and exposes voice action', (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    var sends = 0;
    var voices = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: AskodoxComposer(
            controller: controller,
            onSend: () => sends++,
            onVoice: () => voices++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('askodoxComposerField')), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.tap(find.byTooltip('Speak to ASKODOX'));

    expect(sends, 1);
    expect(voices, 1);
  });
}
