import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'askodox_companion.dart';

/// What the ONE ASKODOX conversation is doing right now, published by Main
/// Chat so the centre nav avatar and the floating companion show the same
/// assistant (same mood, same listening state) -- never a second session.
class AskodoxCompanionLive {
  const AskodoxCompanionLive({this.mood = AskodoxCompanionMood.idle, this.listening = false, this.line});

  final AskodoxCompanionMood mood;

  /// The microphone is open: a tap on the companion stops listening.
  final bool listening;

  /// What the companion is saying / guiding right now (speech bubble).
  final String? line;

  @override
  bool operator ==(Object other) =>
      other is AskodoxCompanionLive && other.mood == mood && other.listening == listening && other.line == line;

  @override
  int get hashCode => Object.hash(mood, listening, line);
}

final askodoxCompanionLiveProvider = StateProvider<AskodoxCompanionLive>((ref) => const AskodoxCompanionLive());

/// The companion's action ring is open (Voice, Chat, Camera ...). Only
/// shown while the user is interacting with the companion -- never a
/// permanent row of buttons.
final askodoxCompanionHubOpenProvider = StateProvider<bool>((ref) => false);

/// How many full-screen detail pages (video, study, ...) Main Chat has
/// pushed over itself. The centre mic uses it to OPEN (never toggle) the
/// hub, and Main Chat closes those pages first.
final askodoxDetailPagesOpenProvider = StateProvider<int>((ref) => 0);

/// The companion actions. Attachments go through the one attachment
/// pipeline; voice is the only microphone in the app.
enum AskodoxHubAction { voice, chat, camera, photos, video, files, location }

String askodoxHubLabel(AskodoxHubAction a, String lang) => switch (lang) {
      'te' => const {
          AskodoxHubAction.voice: 'మాట్లాడండి',
          AskodoxHubAction.chat: 'టైప్ చేయండి',
          AskodoxHubAction.camera: 'కెమెరా',
          AskodoxHubAction.photos: 'ఫోటోలు',
          AskodoxHubAction.video: 'వీడియో',
          AskodoxHubAction.files: 'ఫైల్స్',
          AskodoxHubAction.location: 'లొకేషన్',
        }[a]!,
      'hi' => const {
          AskodoxHubAction.voice: 'बोलें',
          AskodoxHubAction.chat: 'लिखें',
          AskodoxHubAction.camera: 'कैमरा',
          AskodoxHubAction.photos: 'फ़ोटो',
          AskodoxHubAction.video: 'वीडियो',
          AskodoxHubAction.files: 'फ़ाइलें',
          AskodoxHubAction.location: 'लोकेशन',
        }[a]!,
      _ => const {
          AskodoxHubAction.voice: 'Voice',
          AskodoxHubAction.chat: 'Chat',
          AskodoxHubAction.camera: 'Camera',
          AskodoxHubAction.photos: 'Photos',
          AskodoxHubAction.video: 'Video',
          AskodoxHubAction.files: 'Files',
          AskodoxHubAction.location: 'Location',
        }[a]!,
    };

IconData askodoxHubIcon(AskodoxHubAction a) => switch (a) {
      AskodoxHubAction.voice => Icons.mic_rounded,
      AskodoxHubAction.chat => Icons.chat_bubble_rounded,
      AskodoxHubAction.camera => Icons.photo_camera_rounded,
      AskodoxHubAction.photos => Icons.photo_library_rounded,
      AskodoxHubAction.video => Icons.videocam_rounded,
      AskodoxHubAction.files => Icons.description_rounded,
      AskodoxHubAction.location => Icons.place_rounded,
    };

const _hubColors = {
  AskodoxHubAction.voice: Color(0xFF6C4DFF),
  AskodoxHubAction.chat: Color(0xFF1769FF),
  AskodoxHubAction.camera: Color(0xFFE5484D),
  AskodoxHubAction.photos: Color(0xFF0F7B3F),
  AskodoxHubAction.video: Color(0xFFD9344F),
  AskodoxHubAction.files: Color(0xFFE08A00),
  AskodoxHubAction.location: Color(0xFF0B9E6A),
};

/// The ring of companion actions around the companion (the approved
/// reference: Voice on top, Chat / Camera, Photos / Location, Video /
/// Files). Tap outside or the companion again closes it.
class AskodoxCompanionHub extends StatelessWidget {
  const AskodoxCompanionHub({
    super.key,
    required this.lang,
    required this.onAction,
    required this.onClose,
    this.actions = AskodoxHubAction.values,
    this.radius = 118,
  });

  final String lang;
  final void Function(AskodoxHubAction action) onAction;
  final VoidCallback onClose;
  final List<AskodoxHubAction> actions;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // Wide enough that the buttons never overlap, never wider than the
    // screen (the arc must hold every button with a small gap).
    final width = MediaQuery.sizeOf(context).width;
    final needed = (actions.length * (_button + 8)) / math.pi;
    final r = math.min(math.max(radius, needed), (width - _button - 8) / 2);
    final size = r * 2 + _button + 12;
    return Stack(key: const Key('askodoxCompanionHub'), children: [
      // Tap outside the ring closes it.
      Positioned.fill(
        child: GestureDetector(
          key: const Key('askodoxHubScrim'),
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const ColoredBox(color: Color(0x33101A3A)),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            width: size,
            height: size / 2 + _button / 2 + 20,
            child: Stack(clipBehavior: Clip.none, children: [
              for (final a in actions) _positioned(actions.length, size, r, a),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// Spread over the upper half-circle, Voice at the top centre.
  static const _button = 64.0;

  Widget _positioned(int n, double size, double radius, AskodoxHubAction a) {
    final ordered = [...actions]..sort((x, y) => _slot(x).compareTo(_slot(y)));
    final index = ordered.indexOf(a);
    final angle = math.pi - (math.pi * (index + .5) / n);
    final cx = size / 2 + radius * math.cos(angle) - _button / 2;
    final cy = size / 2 - radius * math.sin(angle) - _button / 2;
    return Positioned(
      left: cx,
      top: cy + 20,
      child: _HubButton(action: a, lang: lang, onTap: () => onAction(a)),
    );
  }

  static int _slot(AskodoxHubAction a) => switch (a) {
        AskodoxHubAction.photos => 0,
        AskodoxHubAction.chat => 1,
        AskodoxHubAction.video => 2,
        AskodoxHubAction.voice => 3,
        AskodoxHubAction.files => 4,
        AskodoxHubAction.camera => 5,
        AskodoxHubAction.location => 6,
      };
}

class _HubButton extends StatelessWidget {
  const _HubButton({required this.action, required this.lang, required this.onTap});

  final AskodoxHubAction action;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: askodoxHubLabel(action, lang),
        child: GestureDetector(
          key: ValueKey('askodoxHubAction-${action.name}'),
          onTap: onTap,
          child: Container(
            width: AskodoxCompanionHub._button,
            height: AskodoxCompanionHub._button,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD9D2FF), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x336C4DFF), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(askodoxHubIcon(action), color: _hubColors[action], size: 22),
              const SizedBox(height: 2),
              Text(askodoxHubLabel(action, lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10204A))),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------ in-app floating --

/// The optional floating companion INSIDE ASKODOX (Profile switch): a small
/// avatar that stays over the other ASKODOX screens, draggable, snapping to
/// the nearest side, remembering where it was left. It is the SAME
/// assistant as Main Chat -- its actions continue that conversation.
class AskodoxInAppFloatState {
  const AskodoxInAppFloatState({this.enabled = false, this.x = 1, this.y = .62, this.panelOpen = false});

  final bool enabled;

  /// 0 = left edge, 1 = right edge (snapped).
  final double x;

  /// 0 = top of the safe area, 1 = just above the bottom navigation.
  final double y;
  final bool panelOpen;

  AskodoxInAppFloatState copyWith({bool? enabled, double? x, double? y, bool? panelOpen}) => AskodoxInAppFloatState(
      enabled: enabled ?? this.enabled, x: x ?? this.x, y: y ?? this.y, panelOpen: panelOpen ?? this.panelOpen);
}

class AskodoxInAppFloatController extends StateNotifier<AskodoxInAppFloatState> {
  AskodoxInAppFloatController() : super(const AskodoxInAppFloatState()) {
    _load();
  }

  static const _key = 'askodox.companion.float.v1';

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getStringList(_key);
      if (raw == null || raw.length < 3 || !mounted) return;
      state = AskodoxInAppFloatState(
        enabled: raw[0] == '1',
        x: (double.tryParse(raw[1]) ?? 1).clamp(0, 1).toDouble(),
        y: (double.tryParse(raw[2]) ?? .62).clamp(0, 1).toDouble(),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance())
          .setStringList(_key, [state.enabled ? '1' : '0', '${state.x}', '${state.y}']);
    } catch (_) {}
  }

  void setEnabled(bool on) {
    state = state.copyWith(enabled: on, panelOpen: false);
    _save();
  }

  /// Released after a drag: snap to the nearest side, keep the height.
  void dropAt(double x, double y) {
    state = state.copyWith(x: x < .5 ? 0 : 1, y: y.clamp(0, 1).toDouble());
    _save();
  }

  void togglePanel([bool? open]) => state = state.copyWith(panelOpen: open ?? !state.panelOpen);
}

final askodoxInAppFloatProvider = StateNotifierProvider<AskodoxInAppFloatController, AskodoxInAppFloatState>(
  (ref) => AskodoxInAppFloatController(),
);

/// The floating avatar + its compact panel. Placed by the app shell over
/// every screen except Main Chat (which already shows the companion), inside
/// the safe area, above the bottom navigation and the keyboard.
class AskodoxInAppFloatingCompanion extends ConsumerStatefulWidget {
  const AskodoxInAppFloatingCompanion({
    super.key,
    required this.lang,
    required this.onAction,
    this.onAskAboutThis,
    this.bottomInset = 80,
  });

  final String lang;
  final void Function(AskodoxHubAction action) onAction;

  /// "Ask about this": continue the conversation about the current screen.
  final VoidCallback? onAskAboutThis;

  /// Space kept free at the bottom (navigation bar).
  final double bottomInset;

  @override
  ConsumerState<AskodoxInAppFloatingCompanion> createState() => _AskodoxInAppFloatingCompanionState();
}

class _AskodoxInAppFloatingCompanionState extends ConsumerState<AskodoxInAppFloatingCompanion> {
  static const size = 60.0;
  Offset? _drag;

  String _t(String en, String te) => widget.lang == 'te' ? te : en;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(askodoxInAppFloatProvider);
    if (!state.enabled) return const SizedBox.shrink();
    final live = ref.watch(askodoxCompanionLiveProvider);
    return LayoutBuilder(builder: (context, box) {
      final media = MediaQuery.of(context);
      final top = media.padding.top + 8;
      final bottom = widget.bottomInset + media.viewInsets.bottom + 8;
      final usableH = math.max(1.0, box.maxHeight - top - bottom - size);
      final usableW = math.max(1.0, box.maxWidth - size - 16);
      final pos = _drag ?? Offset(8 + state.x * usableW, top + state.y * usableH);
      final openUp = _drag == null && state.y > .5;
      final panelRoom = openUp ? pos.dy - top - 6 : box.maxHeight - bottom - pos.dy - size - 6;
      return Stack(children: [
        if (state.panelOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(askodoxInAppFloatProvider.notifier).togglePanel(false),
            ),
          ),
        Positioned(
          // On the right edge the panel opens leftwards (anchored by its
          // right side) so it never goes off screen.
          left: _drag != null || state.x < .5 ? pos.dx : null,
          right: _drag == null && state.x >= .5 ? math.max(0.0, box.maxWidth - pos.dx - size) : null,
          // In the lower half the panel opens upwards (anchored by the
          // avatar's bottom) so it stays above the navigation / keyboard.
          top: openUp ? null : pos.dy,
          bottom: openUp ? math.max(0.0, box.maxHeight - pos.dy - size) : null,
          child: Column(
            crossAxisAlignment: state.x < .5 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            verticalDirection: openUp ? VerticalDirection.up : VerticalDirection.down,
            children: [
              GestureDetector(
                key: const Key('askodoxFloatingCompanion'),
                onTap: () {
                  // Listening: the tap stops it (same rule as everywhere).
                  if (live.listening) {
                    widget.onAction(AskodoxHubAction.voice);
                  } else {
                    ref.read(askodoxInAppFloatProvider.notifier).togglePanel();
                  }
                },
                onPanUpdate: (d) => setState(() => _drag = (_drag ?? pos) + d.delta),
                onPanEnd: (_) {
                  final p = _drag ?? pos;
                  setState(() => _drag = null);
                  ref.read(askodoxInAppFloatProvider.notifier).dropAt(
                      ((p.dx - 8) / usableW).clamp(0, 1).toDouble(), ((p.dy - top) / usableH).clamp(0, 1).toDouble());
                },
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border:
                        Border.all(color: live.listening ? const Color(0xFFE5484D) : const Color(0xFF6C4DFF), width: 2),
                    boxShadow: const [BoxShadow(color: Color(0x406C4DFF), blurRadius: 12)],
                  ),
                  child: ClipOval(child: AskodoxCompanion(mood: live.mood, size: size - 4)),
                ),
              ),
              if (state.panelOpen)
                Container(
                  key: const Key('askodoxFloatingPanel'),
                  margin: EdgeInsets.only(top: openUp ? 0 : 6, bottom: openUp ? 6 : 0),
                  padding: const EdgeInsets.all(6),
                  width: 208,
                  // Never taller than the room above / below the avatar.
                  constraints: BoxConstraints(maxHeight: math.max(120.0, panelRoom)),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x33101A3A), blurRadius: 16)],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // The actions scroll if the room is short; Minimize /
                    // Hide below them always stay reachable.
                    Flexible(
                        child: SingleChildScrollView(
                            child: Wrap(spacing: 4, runSpacing: 4, children: [
                      if (widget.onAskAboutThis != null)
                        ActionChip(
                          key: const Key('askodoxFloatAskThis'),
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.help_outline_rounded, size: 16, color: Color(0xFF6C4DFF)),
                          label: Text(
                              switch (widget.lang) {
                                'te' => 'దీని గురించి అడగండి',
                                'hi' => 'इसके बारे में पूछें',
                                _ => 'Ask about this',
                              },
                              style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            ref.read(askodoxInAppFloatProvider.notifier).togglePanel(false);
                            widget.onAskAboutThis!();
                          },
                        ),
                      for (final a in AskodoxHubAction.values)
                        ActionChip(
                          key: ValueKey('askodoxFloatAction-${a.name}'),
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(askodoxHubIcon(a), size: 16, color: _hubColors[a]),
                          label: Text(askodoxHubLabel(a, widget.lang), style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            ref.read(askodoxInAppFloatProvider.notifier).togglePanel(false);
                            widget.onAction(a);
                          },
                        ),
                    ]))),
                    OverflowBar(alignment: MainAxisAlignment.spaceBetween, children: [
                      TextButton(
                        key: const Key('askodoxFloatMinimize'),
                        onPressed: () => ref.read(askodoxInAppFloatProvider.notifier).togglePanel(false),
                        child: Text(_t('Minimize', 'చిన్నదిగా')),
                      ),
                      TextButton(
                        key: const Key('askodoxFloatHide'),
                        onPressed: () => ref.read(askodoxInAppFloatProvider.notifier).setEnabled(false),
                        child: Text(_t('Hide', 'దాచు')),
                      ),
                    ]),
                  ]),
                ),
            ],
          ),
        ),
      ]);
    });
  }
}
