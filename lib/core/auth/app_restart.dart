import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rebuilds the whole app with a FRESH provider container.
///
/// Used after sign-out (and when a stored session turns out to be invalid):
/// every in-memory state of the previous account -- profile, chats, results,
/// roles, notifications -- is discarded at once, the navigation stack is gone
/// (Back can never reopen an authenticated screen) and the app starts again
/// from its first route.
class AskodoxAppRestart extends StatefulWidget {
  const AskodoxAppRestart({super.key, required this.child, this.overrides = const []});

  final Widget child;
  final List<Override> overrides;

  /// Restarts the app that [context] belongs to. Returns false when there is
  /// no restart scope above it (tests that mount screens directly).
  static bool restart(BuildContext context) {
    final state = context.findAncestorStateOfType<_AskodoxAppRestartState>();
    if (state == null) return false;
    state._restart();
    return true;
  }

  @override
  State<AskodoxAppRestart> createState() => _AskodoxAppRestartState();
}

class _AskodoxAppRestartState extends State<AskodoxAppRestart> {
  int _generation = 0;

  void _restart() {
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: ValueKey<int>(_generation),
        child: ProviderScope(overrides: widget.overrides, child: widget.child),
      );
}
