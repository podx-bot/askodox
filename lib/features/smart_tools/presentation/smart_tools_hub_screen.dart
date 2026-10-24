import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/askodox_tile_grid.dart';
import '../domain/smart_tool_catalog.dart';
import 'smart_tool_widgets.dart';

/// Smart Tools hub: every tool from the ONE registry, grouped, each with an
/// honest readiness label. Only built tools open; the rest explain what they
/// need. Reached from Profile and from chat ("how many bricks ...").
class AskodoxSmartToolsHubScreen extends StatelessWidget {
  const AskodoxSmartToolsHubScreen({super.key});

  static String groupLabel(AskodoxToolGroup group, bool te) => switch (group) {
        AskodoxToolGroup.measure => te ? 'కొలతలు & ప్లానింగ్' : 'Measure & plan',
        AskodoxToolGroup.construction => te ? 'నిర్మాణ మెటీరియల్ లెక్కలు' : 'Construction materials',
        AskodoxToolGroup.inspect => te ? 'ఫోటో పరిశీలన' : 'Photo inspection',
        AskodoxToolGroup.money => te ? 'డబ్బు, పన్ను & మోసాల జాగ్రత్త' : 'Money, tax & scam safety',
        AskodoxToolGroup.sensors => te ? 'ఫోన్ సెన్సార్లు' : 'Phone sensors',
        AskodoxToolGroup.devices => te ? 'బయటి పరికరాలు' : 'External devices',
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్మార్ట్ టూల్స్' : 'Smart Tools')),
      body: ListView(
        key: const Key('askodoxSmartToolsHub'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              te
                  ? 'అంచనాలు మాత్రమే — సర్టిఫైడ్ కొలత పరికరాలు లేదా ఇంజనీర్ / నిపుణుల స్థానాన్ని భర్తీ చేయవు.'
                  : 'Estimates only — they never replace certified instruments, an engineer or an expert.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
          for (final group in AskodoxToolGroup.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(groupLabel(group, te), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            AskodoxTileGrid(
              keyPrefix: 'askodoxTool',
              tiles: [
                for (final tool in askodoxSmartTools.where((t) => t.group == group))
                  AskodoxTile(
                    id: tool.id,
                    icon: askodoxToolIcon(tool),
                    title: tool.name(te),
                    enabled: tool.opens,
                    badge: tool.readiness == AskodoxToolReadiness.ready ? null : askodoxReadinessLabel(tool.readiness, te),
                    onTap: () {
                      if (tool.opens) {
                        context.push(tool.route!);
                      } else {
                        _explain(context, tool, te);
                      }
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One icon per tool (falls back to its group's icon).
IconData askodoxToolIcon(AskodoxSmartTool tool) => switch (tool.id) {
      'level' || 'plumb' => Icons.straighten,
      'inclinometer' || 'angle' => Icons.architecture,
      'protractor' => Icons.change_history,
      'ar_tape' || 'distance' => Icons.social_distance,
      'height' => Icons.height,
      'photo_measure' => Icons.photo_size_select_small,
      'area' => Icons.crop_square,
      'volume' => Icons.view_in_ar_outlined,
      'compass' => Icons.explore_outlined,
      'magnifier' => Icons.zoom_in,
      'colour' => Icons.palette_outlined,
      'light' => Icons.light_mode_outlined,
      'sound' => Icons.graphic_eq,
      'vibration' => Icons.vibration,
      'rpm' => Icons.speed,
      'counter' => Icons.format_list_numbered,
      'inspect' => Icons.image_search,
      'vehicle_report' => Icons.directions_car_outlined,
      'crack' => Icons.broken_image_outlined,
      'brick' => Icons.grid_view,
      'cement' => Icons.foundation,
      'tile' => Icons.grid_on,
      'paint' => Icons.format_paint_outlined,
      'load' => Icons.local_shipping_outlined,
      'animal_weight' => Icons.pets_outlined,
      'income_tax' => Icons.account_balance_outlined,
      'gst' => Icons.receipt_long_outlined,
      'fraud_check' => Icons.gpp_maybe_outlined,
      'smart_tricks' => Icons.lightbulb_outline,
      'bt_scale' => Icons.scale_outlined,
      'moisture' => Icons.water_drop_outlined,
      'temperature' => Icons.thermostat,
      'electrical' => Icons.electrical_services,
      'pairing' => Icons.bluetooth,
      'smart_home' => Icons.settings_remote_outlined,
      'walkie' => Icons.record_voice_over_outlined,
      'laser' => Icons.square_foot,
      _ => switch (tool.group) {
          AskodoxToolGroup.measure => Icons.straighten,
          AskodoxToolGroup.construction => Icons.construction,
          AskodoxToolGroup.inspect => Icons.image_search,
          AskodoxToolGroup.money => Icons.currency_rupee,
          AskodoxToolGroup.sensors => Icons.sensors,
          AskodoxToolGroup.devices => Icons.devices_other,
        },
    };

void _explain(BuildContext context, AskodoxSmartTool tool, bool te) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      key: ValueKey('askodoxToolInfo-${tool.id}'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tool.name(te), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 6),
        Text(askodoxReadinessLabel(tool.readiness, te)),
        const SizedBox(height: 10),
        Text(te ? 'దీనికి కావలసినవి:' : 'What it needs:', style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final need in tool.needs) Text('• ${askodoxNeedLabel(need, te)}'),
        const SizedBox(height: 10),
        Text(te
            ? 'ఇది ఇంకా ఈ యాప్‌లో పని చేయదు. పని చేస్తున్నట్లు చూపించము.'
            : 'This does not work in the app yet; ASKODOX will not pretend it does.'),
      ]),
    ),
  );
}
