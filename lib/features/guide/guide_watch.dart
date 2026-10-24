import 'package:flutter/widgets.dart';

/// What a form field is for, so the guide can explain it when the person gets
/// stuck there (no "?" icon on the field itself). Wrap any field with it.
class AskodoxFieldGuideInfo extends StatelessWidget {
  const AskodoxFieldGuideInfo({
    super.key,
    required this.titleEn,
    required this.titleTe,
    required this.en,
    required this.te,
    this.exampleEn,
    this.exampleTe,
    required this.child,
  });

  final String titleEn;
  final String titleTe;
  final String en;
  final String te;
  final String? exampleEn;
  final String? exampleTe;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// One reason for the guide to offer help on its own.
class AskodoxGuideNudge {
  const AskodoxGuideNudge({required this.kind, this.messageEn = '', this.messageTe = '', this.field});

  /// idle_field (stuck on an empty box) | error (something was refused)
  final String kind;
  final String messageEn;
  final String messageTe;

  /// The field the person is on (for idle_field), when it carries guide info.
  final AskodoxFieldGuideInfo? field;
}

/// Anything in the app can report a problem; the guide on the left offers help.
class AskodoxGuideNudges extends ChangeNotifier {
  AskodoxGuideNudges._();
  static final AskodoxGuideNudges instance = AskodoxGuideNudges._();

  AskodoxGuideNudge? _current;
  AskodoxGuideNudge? get current => _current;

  /// Something the person did was refused (validation / server). Shown as
  /// "That did not go through — want help?" with the reason in plain words.
  void reportError(String messageEn, [String? messageTe]) {
    _current = AskodoxGuideNudge(kind: 'error', messageEn: messageEn, messageTe: messageTe ?? messageEn);
    notifyListeners();
  }

  void offer(AskodoxGuideNudge nudge) {
    _current = nudge;
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

/// How long an empty, focused box waits before the guide offers help.
const askodoxGuideIdleDelay = Duration(seconds: 5);
