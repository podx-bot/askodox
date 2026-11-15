import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/question_mic.dart';
import '../../features/pos/data/pos_repository.dart';

/// One box of a page that the fill mic may fill. A text box passes its [controller]; a choice / switch the page keeps
/// in its own state passes [apply] (called with the checked value).
class AskodoxFillField {
  const AskodoxFillField(this.key, this.label, {this.kind = 'text', this.options = const [], this.controller, this.apply});

  final String key;
  final String label;

  /// text | number | phone | choice
  final String kind;
  final List<String> options;
  final TextEditingController? controller;
  final ValueChanged<String>? apply;
}

/// ONE mic at the bottom of a page (owner 2026-11-16): press, say it all ("Rama, 8125656812, advance 9000"), and the
/// page's boxes fill at once; the person can correct any box by hand. The server only maps the words onto the boxes
/// ([AskodoxPosRepository.formFill]); a box the words do not mention stays as it is.
class AskodoxFillBar extends ConsumerStatefulWidget {
  const AskodoxFillBar({super.key, required this.fields, this.onFilled, this.lang = 'te'});

  /// Read when the mic result arrives, so a page whose boxes change (more lines) passes the current list.
  final List<AskodoxFillField> Function() fields;
  final VoidCallback? onFilled;
  final String lang;

  @override
  ConsumerState<AskodoxFillBar> createState() => _AskodoxFillBarState();
}

class _AskodoxFillBarState extends ConsumerState<AskodoxFillBar> {
  String _status = '';
  bool _working = false;

  bool get _te => widget.lang == 'te';

  Future<void> _heard(String words) async {
    final fields = widget.fields();
    setState(() {
      _working = true;
      _status = _te ? 'అర్థం చేసుకుంటున్నాను…' : 'Understanding…';
    });
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).formFill([
        for (final f in fields) {'key': f.key, 'label': f.label, 'kind': f.kind, 'options': f.options}
      ], words, locale: widget.lang);
      final values = askodoxPosMap(out['values']);
      var filled = 0;
      for (final f in fields) {
        final value = values[f.key];
        if (value == null) continue;
        filled++;
        final text = '$value';
        if (f.controller != null) {
          f.controller!.text = text;
          f.controller!.selection = TextSelection.collapsed(offset: text.length);
        }
        f.apply?.call(text);
      }
      if (!mounted) return;
      setState(() => _status = filled == 0
          ? (_te ? 'ఏమి నింపాలో అర్థం కాలేదు. మళ్ళీ చెప్పండి లేదా టైప్ చేయండి.' : 'I could not tell what to fill. Say it again or type.')
          : (_te ? '$filled ఖాళీలు నింపాను — సరిచూసుకోండి.' : 'Filled $filled boxes — please check them.'));
      if (filled > 0) widget.onFilled?.call();
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _status = e.message(_te));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Material(
        elevation: 8,
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(_status, key: const Key('askodoxFillStatus'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_te ? 'నొక్కి చెప్పండి, ఖాళీలు నిండుతాయి' : 'Tap and speak: the boxes fill'),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: _working
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : AskodoxQuestionMic(key: const Key('askodoxFillMic'), lang: widget.lang, followCentre: false, onText: _heard),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
