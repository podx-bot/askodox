import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: the guide is the user's own ON / OFF switch (like the Buy / Sell switch). OFF = the guide says
/// and lights up nothing. ON = when the person stops on a screen for [askodoxGuideIdle] without touching anything, the
/// guide lights the next button and says what to do. A one-time card explains the switch on the first app open; the
/// app never talks on every open.
const askodoxGuideOnPrefsKey = 'askodox.guide.on.v1';
const askodoxGuideIntroPrefsKey = 'askodox.guide.intro_seen.v1';
const askodoxGuideDonePrefsKey = 'askodox.guide.done.v1';

/// The one-time intro card is shown only in the real app (set in `main()`), never in widget tests.
bool askodoxGuideIntroEnabled = false;

/// How long the person must stop (no touch) before the guide starts by itself.
const askodoxGuideIdle = Duration(seconds: 5);

/// Guide colour = the colour of the light around the button (not green: green is the Seller side).
const askodoxGuideGold = Color(0xFFFFC94D);

class AskodoxGuideSwitch extends StateNotifier<bool> {
  AskodoxGuideSwitch() : super(false) {
    unawaited(_load());
  }

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(askodoxGuideOnPrefsKey) ?? false;
      _loaded = true;
      if (mounted) state = on;
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> set(bool on) async {
    state = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(askodoxGuideOnPrefsKey, on);
    } catch (_) {}
  }
}

final askodoxGuideOnProvider = StateNotifierProvider<AskodoxGuideSwitch, bool>((ref) => AskodoxGuideSwitch());

/// Flows that already finished once (each auto walkthrough starts by itself only until it is done).
Future<Set<String>> askodoxGuideDoneFlows() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(askodoxGuideDonePrefsKey) ?? const <String>[]).toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> askodoxMarkGuideDone(String flowId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final done = (prefs.getStringList(askodoxGuideDonePrefsKey) ?? const <String>[]).toSet()..add(flowId);
    await prefs.setStringList(askodoxGuideDonePrefsKey, done.toList()..sort());
  } catch (_) {}
}

String askodoxGuideBannerText(bool on, bool te) => on
    ? (te ? 'గైడ్ ఆన్ — మీరు ఎక్కడ ఆగినా నేను చూపిస్తా' : 'Guide on — wherever you stop, I will show you')
    : (te ? 'గైడ్ ఆఫ్ — ఇక మౌనంగా ఉంటా' : 'Guide off — I will stay quiet');

/// Flip the switch and show the short banner (about 2 s; not kept in the chat).
Future<void> askodoxToggleGuide(BuildContext context, WidgetRef ref, {bool? to}) async {
  final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
  final on = to ?? !ref.read(askodoxGuideOnProvider);
  await ref.read(askodoxGuideOnProvider.notifier).set(on);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    key: Key(on ? 'askodoxGuideBannerOn' : 'askodoxGuideBannerOff'),
    duration: const Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    backgroundColor: on ? askodoxGuideGold : const Color(0xFF475467),
    content: Row(children: [
      Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 18, color: on ? const Color(0xFF14213D) : Colors.white),
      const SizedBox(width: 8),
      Expanded(
        child: Text(askodoxGuideBannerText(on, te),
            style: TextStyle(fontWeight: FontWeight.w700, color: on ? const Color(0xFF14213D) : Colors.white)),
      ),
    ]),
  ));
}

/// The header switch: "గైడ్ ఆన్" (gold) / "గైడ్ ఆఫ్" (grey). One tap flips it.
class AskodoxGuideChip extends ConsumerWidget {
  const AskodoxGuideChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(askodoxGuideOnProvider);
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final label = on ? (te ? 'గైడ్ ఆన్' : 'Guide on') : (te ? 'గైడ్ ఆఫ్' : 'Guide off');
    return Semantics(
      button: true,
      toggled: on,
      label: on ? (te ? 'గైడ్ ఆన్. నొక్కితే ఆఫ్' : 'Guide on. Tap to turn off') : (te ? 'గైడ్ ఆఫ్. నొక్కితే ఆన్' : 'Guide off. Tap to turn on'),
      child: InkWell(
        key: const Key('askodoxGuideSwitch'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => askodoxToggleGuide(context, ref),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: on ? askodoxGuideGold : const Color(0xFFE9ECF2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: on ? const Color(0xFF14213D) : const Color(0xFF98A2B3), shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label,
                key: Key(on ? 'askodoxGuideSwitchOn' : 'askodoxGuideSwitchOff'),
                maxLines: 1,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: on ? const Color(0xFF14213D) : const Color(0xFF475467))),
          ]),
        ),
      ),
    );
  }
}

/// The one-time card on the first app open: what the guide button does. Returns true when the person turned it ON.
Future<bool> askodoxGuideIntroOnce(BuildContext context, WidgetRef ref) async {
  if (!askodoxGuideIntroEnabled) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(askodoxGuideIntroPrefsKey) ?? false) return false;
    await prefs.setBool(askodoxGuideIntroPrefsKey, true);
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;
  final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
  Widget row(IconData icon, String bold, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: const Color(0xFF8A5A00)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$bold ', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14213D))),
              TextSpan(text: text),
            ]), style: const TextStyle(fontSize: 14.5, height: 1.45, color: Color(0xFF344054))),
          ),
        ]),
      );
  final on = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => SafeArea(
      child: Padding(
        key: const Key('askodoxGuideIntro'),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: askodoxGuideGold, shape: BoxShape.circle),
              child: const Icon(Icons.volume_up_rounded, color: Color(0xFF14213D)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(te ? 'నేను మీ ASKODOX గైడ్' : 'I am your ASKODOX guide',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(te ? 'ఇది ఒక్కసారే వస్తుంది' : 'You see this only once',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085))),
              ]),
            ),
          ]),
          row(Icons.highlight_rounded, te ? 'ఆన్ చేస్తే:' : 'On:',
              te ? 'మీరు ఎక్కడైనా ఆగిపోతే, ఏం నొక్కాలో వెలిగించి, మాట్లాడి చూపిస్తా.' : 'wherever you stop, I light up what to tap and say it.'),
          row(Icons.volume_off_rounded, te ? 'ఆఫ్ చేస్తే:' : 'Off:',
              te ? 'నేను మౌనంగా ఉంటా. ఏమీ చెప్పను, ఏమీ వెలిగించను.' : 'I stay quiet. I say and light up nothing.'),
          row(Icons.touch_app_rounded, te ? 'ఎప్పుడైనా మార్చొచ్చు:' : 'Change any time:',
              te ? 'పైన ఉన్న "గైడ్" బటన్ ఒక్కసారి నొక్కితే చాలు.' : 'tap the "Guide" button at the top once.'),
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('askodoxGuideIntroOn'),
            style: FilledButton.styleFrom(
                backgroundColor: askodoxGuideGold,
                foregroundColor: const Color(0xFF14213D),
                minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(te ? 'గైడ్ ఆన్ చేయి' : 'Turn the guide on',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            key: const Key('askodoxGuideIntroOff'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(te ? 'వద్దు, నేనే చేసుకుంటా' : 'No thanks, I will do it myself'),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted) return false;
  await askodoxToggleGuide(context, ref, to: on == true);
  return on == true;
}
