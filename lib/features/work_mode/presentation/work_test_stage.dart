import 'package:flutter/material.dart';

import 'work_scene_images.dart';

/// Test builds only: pick a stage to preview the work scene. Null = the real
/// progress of the job. Never changes what is counted or saved.
final askodoxWorkTestStage = ValueNotifier<int?>(null);

/// Shown in non-production builds, and in test APKs built with ASKODOX_WORK_TEST=true.
bool get askodoxWorkTestPickerVisible =>
    const bool.fromEnvironment('ASKODOX_WORK_TEST') ||
    const String.fromEnvironment('APP_ENV', defaultValue: 'development') != 'production';

class AskodoxWorkTestStagePicker extends StatelessWidget {
  const AskodoxWorkTestStagePicker({required this.stages, super.key});

  final List<String> stages;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
        valueListenable: askodoxWorkTestStage,
        builder: (context, forced, _) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          ValueListenableBuilder<String>(
            valueListenable: askodoxWorkImageStatus,
            builder: (context, status, _) => Text(
              'test: picture $status · stage ${forced == null ? 'real' : forced + 1}',
              key: const Key('askodoxWorkTestStatus'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF5A6478)),
            ),
          ),
          Wrap(
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
            ],
          ),
        ),
      );
}
