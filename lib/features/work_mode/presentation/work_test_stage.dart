import 'package:flutter/material.dart';

/// Test builds only: pick a stage to preview the work scene. Null = the real
/// progress of the job. Never changes what is counted or saved.
final askodoxWorkTestStage = ValueNotifier<int?>(null);

/// The picker is shown in every build except APP_ENV=production.
bool get askodoxWorkTestPickerVisible =>
    const String.fromEnvironment('APP_ENV', defaultValue: 'development') != 'production';

class AskodoxWorkTestStagePicker extends StatelessWidget {
  const AskodoxWorkTestStagePicker({required this.stages, super.key});

  final List<String> stages;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
        valueListenable: askodoxWorkTestStage,
        builder: (context, forced, _) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            key: const Key('askodoxWorkTestStages'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < stages.length; i++)
                ChoiceChip(
                  label: Text('${i + 1}. ${stages[i]}', style: const TextStyle(fontSize: 11)),
                  selected: forced == i,
                  onSelected: (_) => askodoxWorkTestStage.value = forced == i ? null : i,
                ),
            ],
          ),
        ),
      );
}
