import 'package:flutter/material.dart';

/// The ONE attachment control beside the chat input: "+" opens Camera,
/// Photos, Videos and Files. Each choice goes to the existing picker
/// (`_pickAttachment` on Main Chat) -- the same choices the companion offers,
/// so there is never a second attachment pipeline.
class AskodoxAttachButton extends StatelessWidget {
  const AskodoxAttachButton({super.key, required this.lang, required this.onPick, this.enabled = true});

  final String lang;
  final bool enabled;

  /// 'camera' | 'photos' | 'video' | 'files' (the picker's own choice ids).
  final ValueChanged<String> onPick;

  static const choices = ['camera', 'photos', 'video', 'files'];

  static String label(String choice, String lang) => switch ((lang, choice)) {
        ('te', 'camera') => 'కెమెరా',
        ('te', 'photos') => 'ఫోటోలు',
        ('te', 'video') => 'వీడియోలు',
        ('te', 'files') => 'ఫైల్స్',
        ('hi', 'camera') => 'कैमरा',
        ('hi', 'photos') => 'फ़ोटो',
        ('hi', 'video') => 'वीडियो',
        ('hi', 'files') => 'फ़ाइलें',
        (_, 'camera') => 'Camera',
        (_, 'photos') => 'Photos',
        (_, 'video') => 'Videos',
        _ => 'Files',
      };

  static IconData icon(String choice) => switch (choice) {
        'camera' => Icons.photo_camera_outlined,
        'photos' => Icons.photo_library_outlined,
        'video' => Icons.videocam_outlined,
        _ => Icons.attach_file_rounded,
      };

  Future<void> _open(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(children: [
            for (final c in choices)
              Expanded(
                child: InkWell(
                  key: ValueKey('askodoxAttachChoice-$c'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(sheet, c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFEDEBFF),
                        child: Icon(icon(c), color: const Color(0xFF5B4BFF)),
                      ),
                      const SizedBox(height: 6),
                      Text(label(c, lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (choice != null) onPick(choice);
  }

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('askodoxAttachButton'),
        tooltip: switch (lang) { 'te' => 'జత చేయండి', 'hi' => 'जोड़ें', _ => 'Attach' },
        onPressed: enabled ? () => _open(context) : null,
        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF5B4BFF), size: 28),
      );
}
