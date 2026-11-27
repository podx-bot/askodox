import '../../../config/theme/askodox_look.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/ui_switches.dart';
import '../../home/presentation/question_mic.dart';
import '../domain/step_logic.dart';

// The 3-step page kit (owner 2026-11-22, design artifact RGYB6de8vhoNeDwY3DBG9z "3 స్టెప్స్"): every second page has
// only three pieces -- (1) one big question or one big number on top, (2) big tiles or one list in the middle,
// (3) one big button + a mic at the bottom -- and every job is done in three steps (1·2·3 bar on top, a big ✓ at the
// end). Phone-app models: dialer keypad, camera, contacts, incoming call, call log, settings.

const askodoxStepInk = Color(0xFFF7F9FC);
const askodoxStepMuted = Color(0xFFB9C5D5);
const askodoxStepLine = Color(0xFF4A526B);
const askodoxStepGreen = Color(0xFF77D49F);
const askodoxStepGreenDark = Color(0xFF92DAB0);
const askodoxStepGreenSoft = Color(0xFF1C3428);
const askodoxStepGreenTint = Color(0xFF2A513E);
const askodoxStepDone = Color(0xFF66CA82);
const askodoxStepWarn = Color(0xFFFEA56F);
const askodoxStepBad = Color(0xFFFEA89B);
const askodoxStepInfo = Color(0xFFACC6FE);

/// One choice in the header's "⋮" (the full old page, help ...): everything that is not the one job lives here.
class AskodoxStepMore {
  const AskodoxStepMore(this.key, this.label, this.icon, this.onTap);
  final String key;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// The page: back (one step back, or out on step 1) · title · ⋮, the 1·2·3 bar, the big question, the middle, the
/// bottom bar. [step] 0 = a page with no steps (a glance page or a finished job).
class AskodoxStepScaffold extends StatelessWidget {
  const AskodoxStepScaffold({
    super.key,
    required this.title,
    this.sub = '',
    this.step = 0,
    this.total = 3,
    this.question,
    this.hint,
    required this.body,
    this.bottom,
    this.onBack,
    this.more = const [],
    this.color = askodoxStepGreen,
    this.background = AskodoxLook.sheet,
  });

  final String title;
  final String sub;
  final int step;
  final int total;
  final String? question;
  final String? hint;
  final Widget body;
  final Widget? bottom;

  /// Called for back on steps 2 and 3 (go one step back). Null -> back leaves the page.
  final VoidCallback? onBack;
  final List<AskodoxStepMore> more;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 56,
              child: Row(children: [
                IconButton(
                  key: const Key('askodoxStepBack'),
                  tooltip: te ? 'వెనక్కి' : 'Back',
                  icon: const Icon(Icons.arrow_back_rounded, color: askodoxStepInk, size: 26),
                  onPressed: () => onBack != null ? onBack!() : Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: askodoxStepInk)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
                  ]),
                ),
                if (more.isNotEmpty)
                  PopupMenuButton<int>(
                    key: const Key('askodoxStepMore'),
                    tooltip: te ? 'ఇంకా' : 'More',
                    icon: const Icon(Icons.more_vert_rounded, color: askodoxStepInk),
                    onSelected: (i) => more[i].onTap(),
                    itemBuilder: (_) => [
                      for (var i = 0; i < more.length; i++)
                        PopupMenuItem<int>(
                          key: Key(more[i].key),
                          value: i,
                          child: Row(children: [
                            Icon(more[i].icon, size: 20, color: askodoxStepInk),
                            const SizedBox(width: 10),
                            Flexible(child: Text(more[i].label)),
                          ]),
                        ),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ]),
            ),
            if (step > 0) AskodoxStepBar(step: step, total: total, color: color),
            if (question != null) AskodoxStepQuestion(question!, hint: hint),
            Expanded(child: body),
            if (bottom != null) bottom!,
          ]),
        ),
      ),
    );
  }
}

/// The 1·2·3 bar: where am I in this job.
class AskodoxStepBar extends StatelessWidget {
  const AskodoxStepBar({super.key, required this.step, this.total = 3, this.color = askodoxStepGreen});
  final int step;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Semantics(
        label: te ? 'స్టెప్ $step / $total' : 'Step $step of $total',
        child: Row(key: const Key('askodoxStepBar'), children: [
          for (var i = 1; i <= total; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 5,
                decoration: BoxDecoration(
                    color: i <= step ? color : const Color(0xFF4A526B), borderRadius: BorderRadius.circular(3)),
              ),
            ),
            if (i < total) const SizedBox(width: 6),
          ],
          const SizedBox(width: 8),
          Text('$step/$total', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: askodoxStepMuted)),
        ]),
      ),
    );
  }
}

/// The one big question of a step ("How was it paid?").
class AskodoxStepQuestion extends StatelessWidget {
  const AskodoxStepQuestion(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text,
              key: const Key('askodoxStepQuestion'),
              style: const TextStyle(fontSize: 26, height: 1.3, fontWeight: FontWeight.w900, color: askodoxStepInk)),
          if (hint != null && hint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!, style: const TextStyle(fontSize: 13, height: 1.4, color: askodoxStepMuted)),
            ),
        ]),
      );
}

/// The bottom bar: the mic (when the step listens) + ONE big button.
class AskodoxStepBottom extends StatelessWidget {
  const AskodoxStepBottom({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.buttonKey,
    this.outline = false,
    this.onSpoken,
    this.color = askodoxStepGreen,
    this.busy = false,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final bool outline;

  /// The mic's words; null = no mic on this step.
  final ValueChanged<String>? onSpoken;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final text = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(label ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 22)],
    ]);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    final child = busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AskodoxLook.sheet)) : text;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(color: AskodoxLook.sheet, border: Border(top: BorderSide(color: Color(0xFF1F2432)))),
      child: Row(children: [
        if (onSpoken != null && askodoxPageMicsOn) ...[
          Container(
            key: const Key('askodoxStepMic'),
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: askodoxStepGreenTint, borderRadius: BorderRadius.circular(29)),
            alignment: Alignment.center,
            child: IconTheme.merge(
              data: const IconThemeData(size: 28, color: askodoxStepGreenDark),
              child: AskodoxQuestionMic(lang: te ? 'te' : 'en', followCentre: false, onText: onSpoken!),
            ),
          ),
          if (label != null) const SizedBox(width: 10),
        ],
        if (label != null)
          Expanded(
            child: SizedBox(
              height: 58,
              child: outline
                  ? OutlinedButton(
                      key: buttonKey,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: color, side: BorderSide(color: color, width: 2), shape: shape),
                      onPressed: busy ? null : onPressed,
                      child: busy ? CircularProgressIndicator(strokeWidth: 2.4, color: color) : text,
                    )
                  : FilledButton(
                      key: buttonKey,
                      style: FilledButton.styleFrom(
                          backgroundColor: color, disabledBackgroundColor: const Color(0xFF4A526B), shape: shape),
                      onPressed: busy ? null : onPressed,
                      child: child,
                    ),
            ),
          ),
        if (label == null && onSpoken != null)
          Expanded(
            child: Text(te ? 'నొక్కి చెప్పండి' : 'Tap and speak',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: askodoxStepMuted)),
          ),
      ]),
    );
  }
}

/// One big number with its label above ("23 people owe" / "₹18,450").
class AskodoxStepBigNumber extends StatelessWidget {
  const AskodoxStepBigNumber(this.value, {super.key, this.label, this.color = askodoxStepInk, this.size = 44});
  final String value;
  final String? label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (label != null && label!.isNotEmpty)
          Text(label!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: askodoxStepMuted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              key: const Key('askodoxStepBigNumber'),
              style: TextStyle(fontSize: size, height: 1.2, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
        ),
      ]);
}

/// The dialer-style number pad (1-9, 00, 0, ⌫). [onKey] gets "0"-"9", "00" or "del".
class AskodoxStepKeypad extends StatelessWidget {
  const AskodoxStepKeypad({super.key, required this.onKey, this.keyHeight = 56});
  final ValueChanged<String> onKey;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', 'del'],
    ];
    Widget cell(String k) => Expanded(
          child: SizedBox(
            height: keyHeight,
            child: Material(
              color: const Color(0xFF1F2432),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: Key('askodoxStepKey-$k'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => onKey(k),
                child: Center(
                  child: k == 'del'
                      ? Semantics(
                          label: te ? 'తీసేయి' : 'Delete',
                          child: const Icon(Icons.backspace_outlined, size: 26, color: askodoxStepInk))
                      : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: askodoxStepInk)),
                ),
              ),
            ),
          ),
        );
    return Column(key: const Key('askodoxStepKeypad'), mainAxisSize: MainAxisSize.min, children: [
      for (var r = 0; r < rows.length; r++) ...[
        Row(children: [
          for (var i = 0; i < rows[r].length; i++) ...[
            cell(rows[r][i]),
            if (i < rows[r].length - 1) const SizedBox(width: 8),
          ],
        ]),
        if (r < rows.length - 1) const SizedBox(height: 8),
      ],
    ]);
  }
}

/// A keypad amount box: the big typed rupees + quick amounts + the pad. [value] is whole rupees as typed.
class AskodoxStepAmountPad extends StatelessWidget {
  const AskodoxStepAmountPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.quick = const [],
    this.color = askodoxStepInk,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  /// (chip text, rupees as typed) -- the first one is drawn as the suggestion.
  final List<(String, String)> quick;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        AskodoxStepBigNumber(askodoxStepRupees(askodoxKeypadPaise(value)), label: label, color: color, size: 50),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < quick.length; i++)
              ChoiceChip(
                key: Key('askodoxStepQuick-${quick[i].$2}'),
                label: Text(quick[i].$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: value == quick[i].$2,
                onSelected: (_) => onChanged(quick[i].$2),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        AskodoxStepKeypad(onKey: (k) => onChanged(askodoxKeypadPress(value, k))),
      ]);
}

/// A big choice card ("Cash / Online / Due"): icon square, a big word, one line under it.
class AskodoxStepChoice extends StatelessWidget {
  const AskodoxStepChoice({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
    this.selected = false,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  final bool selected;

  /// A small tag on the card ("you said this").
  final String? badge;

  @override
  Widget build(BuildContext context) => Material(
        color: AskodoxLook.sheet,
        borderRadius: BorderRadius.circular(22),
        elevation: selected ? 2 : 0.5,
        shadowColor: const Color(0x22000000),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? color : askodoxStepLine, width: selected ? 2.5 : 1.5),
            ),
            child: Row(children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, color: AskodoxLook.sheet, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(title,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: askodoxStepInk)),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(10)),
                        child: Text(badge!,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: askodoxStepGreenDark)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: askodoxStepMuted),
            ]),
          ),
        ),
      );
}

/// The big ✓ of a finished job.
class AskodoxStepDoneMark extends StatelessWidget {
  const AskodoxStepDoneMark({super.key, this.size = 120, this.color = askodoxStepDone});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxStepDone'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.14), spreadRadius: 14),
            BoxShadow(color: color.withValues(alpha: 0.07), spreadRadius: 28),
          ],
        ),
        child: Icon(Icons.check_rounded, color: AskodoxLook.sheet, size: size * 0.55),
      );
}

/// A round action under a finished job (WhatsApp / Print / QR).
class AskodoxStepRoundAction extends StatelessWidget {
  const AskodoxStepRoundAction({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: AskodoxLook.sheet, size: 28),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: askodoxStepInk)),
          ]),
        ),
      );
}

/// A small coloured note ("At the shop ✓ (40 m)").
class AskodoxStepPill extends StatelessWidget {
  const AskodoxStepPill(this.text, {super.key, this.kind = 'good'});
  final String text;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (kind) {
      'warn' => (askodoxStepWarn, const Color(0xFF402804)),
      'bad' => (askodoxStepBad, const Color(0xFF402623)),
      'info' => (askodoxStepInfo, const Color(0xFF222C4A)),
      'grey' => (const Color(0xFFC0CDE0), const Color(0xFF1F2432)),
      _ => (const Color(0xFF86D7A1), const Color(0xFF123624)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Three coloured blocks side by side (cash / online / due).
class AskodoxStepBlocks extends StatelessWidget {
  const AskodoxStepBlocks(this.blocks, {super.key});

  /// (label, value, colour)
  final List<(String, String, Color)> blocks;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < blocks.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(color: blocks[i].$3.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text(blocks[i].$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: blocks[i].$3)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(blocks[i].$2, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: blocks[i].$3)),
                ),
              ]),
            ),
          ),
          if (i < blocks.length - 1) const SizedBox(width: 8),
        ],
      ]);
}

/// A contacts-style row: letter circle, name + one line, the amount on the right.
class AskodoxStepPersonRow extends StatelessWidget {
  const AskodoxStepPersonRow({
    super.key,
    required this.name,
    required this.sub,
    required this.amount,
    required this.onTap,
    this.amountColor = askodoxStepWarn,
    this.photoUrl = '',
    this.action,
  });

  final String name;
  final String sub;
  final String amount;
  final VoidCallback onTap;
  final Color amountColor;

  /// The item's own photo in place of the letter circle (owner 2026-11-26: photos first); the letter stays if it fails.
  final String photoUrl;

  /// A small button before the amount (e.g. "Try it").
  final Widget? action;

  static const _palette = [
    (Color(0xFF222C4A), Color(0xFFACC6FE)),
    (Color(0xFF123624), Color(0xFF86D7A1)),
    (Color(0xFF402623), Color(0xFFFEA89B)),
    (Color(0xFF402804), Color(0xFFFEA56F)),
    (Color(0xFF332842), Color(0xFFCDBAFF)),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final (bg, fg) = _palette[name.hashCode.abs() % _palette.length];
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1F2432)))),
        child: Row(children: [
          if (photoUrl.isEmpty)
            CircleAvatar(
              radius: 25,
              backgroundColor: bg,
              child: Text(letter, style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w800)),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(photoUrl,
                  key: const Key('askodoxStepRowPhoto'),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => CircleAvatar(
                        radius: 25,
                        backgroundColor: bg,
                        child: Text(letter, style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w800)),
                      )),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: askodoxStepInk)),
              if (sub.isNotEmpty)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: askodoxStepMuted)),
            ]),
          ),
          const SizedBox(width: 8),
          if (action != null) ...[action!, const SizedBox(width: 4)],
          Text(amount, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: amountColor)),
        ]),
      ),
    );
  }
}

/// A rounded search box ("say / type a name").
class AskodoxStepSearch extends StatelessWidget {
  const AskodoxStepSearch({super.key, required this.controller, required this.hint, required this.onChanged, this.fieldKey});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: const Color(0xFF1F2432),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        ),
      );
}

/// A two-way switch drawn as one pill ("Cash | Online").
class AskodoxStepToggle extends StatelessWidget {
  const AskodoxStepToggle({super.key, required this.options, required this.value, required this.onChanged});

  /// (value, label)
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFF1F2432), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                key: Key('askodoxStepToggle-$v'),
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? AskodoxLook.sheet : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: v == value ? const [BoxShadow(color: Color(0x26000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: v == value ? askodoxStepInk : askodoxStepMuted)),
                ),
              ),
            ),
        ]),
      );
}

/// Reads a whole-rupee amount on a sheet with the big pad; null when closed without "OK".
Future<int?> askodoxAskAmount(BuildContext context, {required String title, int initialPaise = 0, String? okLabel}) {
  final te = Localizations.localeOf(context).languageCode == 'te';
  var typed = initialPaise > 0 ? '${initialPaise ~/ 100}' : '';
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setInner) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: askodoxStepInk)),
            const SizedBox(height: 8),
            AskodoxStepAmountPad(value: typed, onChanged: (v) => setInner(() => typed = v)),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('askodoxStepAmountOk'),
                style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen),
                onPressed: () => Navigator.of(sheet).pop(askodoxKeypadPaise(typed)),
                child: Text(okLabel ?? (te ? 'సరే' : 'OK'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
