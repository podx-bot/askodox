import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/askodox_mascot.dart';
import 'in_app_guide.dart';
import 'screen_help.dart';

/// The guide button on EVERY screen (a small ASKO tab on the left edge). One
/// press opens "what to do here" for the screen on top, with "Show me on the
/// screen" when a walkthrough exists for it. Hidden while a walkthrough runs,
/// while the keyboard is open, and on exempt screens (sign-up, staff tools).
class AskodoxScreenHelpLayer extends ConsumerStatefulWidget {
  const AskodoxScreenHelpLayer({super.key, required this.child, this.router});
  final Widget child;
  final GoRouter? router;

  @override
  ConsumerState<AskodoxScreenHelpLayer> createState() => _AskodoxScreenHelpLayerState();
}

class _AskodoxScreenHelpLayerState extends ConsumerState<AskodoxScreenHelpLayer> {
  @override
  void initState() {
    super.initState();
    widget.router?.routerDelegate.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AskodoxScreenHelpLayer old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routerDelegate.removeListener(_changed);
      widget.router?.routerDelegate.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.router?.routerDelegate.removeListener(_changed);
    super.dispose();
  }

  // The router notifies while the app is still building a frame: redraw after it.
  bool _queued = false;
  void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
  }

  (String pattern, String path) _where() {
    final config = widget.router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return ('', '');
    return (config.fullPath, config.uri.path);
  }

  AskodoxGuideFlow? _flowFor(String path) {
    for (final flow in askodoxGuideFlows) {
      if (flow.steps.isNotEmpty && flow.steps.first.route == path) return flow;
    }
    for (final flow in askodoxGuideFlows) {
      if (flow.steps.any((s) => s.route == path)) return flow;
    }
    return null;
  }

  Future<void> _open(AskodoxScreenHelp help, String path) async {
    final navContext = widget.router?.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;
    final te = Localizations.maybeLocaleOf(navContext)?.languageCode == 'te';
    final flow = _flowFor(path);
    final start = await showModalBottomSheet<bool>(
      context: navContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          key: const Key('askodoxScreenHelpSheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AskodoxMascot(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'ఇక్కడ ఏం చేయాలి' : 'What to do here',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
                  Text(help.title(te), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            for (final (i, step) in help.steps(te).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFFEAF1FF),
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1769FF))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: const TextStyle(fontSize: 14.5, height: 1.35))),
                ]),
              ),
            const SizedBox(height: 4),
            Row(children: [
              if (flow != null)
                FilledButton.icon(
                  key: const Key('askodoxScreenHelpShowMe'),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text(te ? 'స్క్రీన్‌పై చూపించు' : 'Show me on the screen'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'సరే' : 'OK')),
            ]),
          ]),
        ),
      ),
    );
    if (start == true && flow != null) ref.read(askodoxGuideProvider.notifier).start(flow);
  }

  @override
  Widget build(BuildContext context) {
    final (pattern, path) = _where();
    final help = askodoxScreenHelpFor(pattern);
    final guiding = ref.watch(askodoxGuideProvider) != null;
    final keyboard = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
    final te = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    final show = help != null && !guiding && keyboard == 0 && !askodoxGuideIsPrivate(path);
    return Stack(children: [
      widget.child,
      if (show)
        Positioned(
          left: 0,
          bottom: 168,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: te ? 'గైడ్: ఇక్కడ ఏం చేయాలి' : 'Guide: what to do here',
              child: Material(
                color: Colors.white,
                elevation: 3,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
                  side: BorderSide(color: Color(0xFFD0DCF5)),
                ),
                child: InkWell(
                  key: const Key('askodoxScreenHelpButton'),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
                  onTap: () => _open(help, path),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 6, 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AskodoxMascot(size: 30),
                      SizedBox(width: 2),
                      Icon(Icons.help_outline, size: 18, color: Color(0xFF1769FF)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
