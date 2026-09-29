import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'askodox_companion.dart';
import 'companion_3d.dart';
import 'companion_human.dart';

/// Profile > ASKODOX friend: pick the companion once (remembered). Options:
/// Automatic, the human 3D personas, the lightweight robot (Lite) and 3D
/// off (flat friend). Each option shows a small still preview.
class AskodoxCompanionPicker extends ConsumerWidget {
  const AskodoxCompanionPicker({super.key, required this.telugu});

  final bool telugu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(askodoxCompanionSettingsProvider);
    final notifier = ref.read(askodoxCompanionSettingsProvider.notifier);
    String t(String en, String te) => telugu ? te : en;
    final off3d = !settings.render3d;

    Widget option({
      required String id,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      required Widget preview,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            key: ValueKey('askodoxPersona-$id'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              width: 84,
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEDE8FF) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? const Color(0xFF6C4DFF) : const Color(0xFFE2E6EF), width: selected ? 2 : 1),
              ),
              child: Column(children: [
                SizedBox.square(dimension: 56, child: preview),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.15)),
              ]),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text(t('Your companion', 'మీ సహచరుడు'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      SizedBox(
        height: 104,
        child: ListView(
          key: const Key('askodoxCompanionPicker'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            option(
              id: AskodoxCompanionSettings.automatic,
              // Automatic shows who it is right now (it follows the chat).
              label: '${t('Automatic', 'ఆటోమేటిక్')} · ${askodoxPersonaLabel(askodoxPersonaForDomain(ref.watch(askodoxCompanionDomainProvider)), telugu: telugu)}',
              selected: !off3d && settings.companion == AskodoxCompanionSettings.automatic,
              onTap: () => notifier.update(companion: AskodoxCompanionSettings.automatic, render3d: true),
              preview: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C4DFF), size: 34),
            ),
            for (final persona in AskodoxPersona.values)
              option(
                id: persona.name,
                label: askodoxPersonaLabel(persona, telugu: telugu),
                selected: !off3d && settings.companion == persona.name,
                onTap: () => notifier.update(companion: persona.name, render3d: true),
                preview: _PersonaPreview(persona: persona),
              ),
            option(
              id: AskodoxCompanionSettings.humanHd,
              label: t('Human HD (beta)', 'హ్యూమన్ HD (బీటా)'),
              selected: !off3d && settings.companion == AskodoxCompanionSettings.humanHd,
              onTap: () => notifier.update(companion: AskodoxCompanionSettings.humanHd, render3d: true),
              preview: const Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF6C4DFF), size: 34),
            ),
            option(
              id: AskodoxCompanionSettings.robotLite,
              label: t('Robot (Lite)', 'రోబోట్ (లైట్)'),
              selected: !off3d && settings.companion == AskodoxCompanionSettings.robotLite,
              onTap: () => notifier.update(companion: AskodoxCompanionSettings.robotLite, render3d: true),
              preview: _RobotPreview(look: settings.look),
            ),
            option(
              id: 'off3d',
              label: t('3D off', '3D ఆఫ్'),
              selected: off3d,
              onTap: () => notifier.update(render3d: false),
              preview: const Icon(Icons.crop_square_rounded, color: Color(0xFF8A94A6), size: 34),
            ),
          ],
        ),
      ),
      if (!off3d && AskodoxCompanionPerformance.level > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(key: const Key('askodoxCompanionLiteNotice'), children: [
            const Icon(Icons.speed_rounded, size: 18, color: Color(0xFF8A94A6)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t('Lighter motion for smoothness on this phone (same companion).',
                  'ఈ ఫోన్‌లో స్మూత్‌గా ఉండేందుకు తేలికపాటి కదలికలు (అదే సహచరుడు).')),
            ),
            TextButton(
              key: const Key('askodoxCompanionRetry3d'),
              onPressed: () => notifier.update(companion: settings.companion),
              child: Text(t('Try 3D again', 'మళ్లీ 3D')),
            ),
          ]),
        ),
      if (!off3d && settings.companion == AskodoxCompanionSettings.robotLite)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(spacing: 8, children: [
            for (final look in AskodoxCompanionLook.values)
              ChoiceChip(
                key: ValueKey('askodoxLook-${look.name}'),
                selected: settings.look == look,
                onSelected: (_) => notifier.update(look: look),
                label: Text(switch (look) {
                  AskodoxCompanionLook.robot => t('Robot', 'రోబోట్'),
                  AskodoxCompanionLook.friendlyFace => t('Friendly face', 'స్నేహ ముఖం'),
                  AskodoxCompanionLook.simpleOrb => t('Simple', 'సింపుల్'),
                }),
              ),
          ]),
        ),
    ]);
  }
}

class _PersonaPreview extends StatelessWidget {
  const _PersonaPreview({required this.persona});
  final AskodoxPersona persona;

  static final _meshes = <AskodoxPersona, AskodoxMesh>{};

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: AskodoxHuman3dPainter(
            mesh: _meshes.putIfAbsent(persona, () => AskodoxHumanRig.build(AskodoxHumanStyle.of(persona))),
            mood: AskodoxCompanionMood.idle,
            t: 0,
          ),
        ),
      );
}

class _RobotPreview extends StatelessWidget {
  const _RobotPreview({required this.look});
  final AskodoxCompanionLook look;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: AskodoxCompanion3dPainter(
            mesh: AskodoxMesh.forLook(look, const Color(0xFF6C4DFF)),
            mood: AskodoxCompanionMood.idle,
            t: 0,
          ),
        ),
      );
}
