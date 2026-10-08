import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Assistant replies with light structure (APK 1312: raw "**" showed in
/// Telugu answers). One dependency-free renderer for every reply in any
/// language: headings, paragraphs, bullet / numbered points, **bold**,
/// simple | tables | and [links](https://...). A reply without any markup
/// stays ONE plain Text (unchanged look, unchanged tests).

final _inlineMarkup = RegExp(r'\*\*|__|\[[^\]]+\]\(https?://[^)\s]+\)|^\s{0,3}#{1,6}\s|^\s*([-*•]|\d{1,2}[.)])\s|^\s*\|',
    multiLine: true);

/// What a line MEANS, as marked by the assistant -- never guessed from
/// keywords: [ok] good / recommended, [caution] needs attention, [risk]
/// danger / do not. Untagged lines are neutral.
enum AskodoxSeverity { neutral, ok, caution, risk }

final _severityTag = RegExp(
    r'^\s*(?:\[(ok|good|caution|warning|risk|danger)\]|(✅|✔️|✔|⚠️|⚠|❌|🚫|⛔))\s*',
    caseSensitive: false);

/// The severity of [line] and the line without its tag.
(AskodoxSeverity, String) askodoxSeverityOf(String line) {
  final m = _severityTag.firstMatch(line);
  if (m == null) return (AskodoxSeverity.neutral, line);
  final tag = (m.group(1) ?? m.group(2) ?? '').toLowerCase();
  final severity = switch (tag) {
    'ok' || 'good' || '✅' || '✔️' || '✔' => AskodoxSeverity.ok,
    'caution' || 'warning' || '⚠️' || '⚠' => AskodoxSeverity.caution,
    _ => AskodoxSeverity.risk,
  };
  return (severity, line.substring(m.end));
}

bool _hasSeverity(String text) => text.split('\n').any((l) => _severityTag.hasMatch(l.replaceFirst(
    RegExp(r'^\s*([-*•]|\d{1,2}[.)])\s+'), '')));

/// Telugu (and other tall scripts) need more line height to stay readable.
bool askodoxNeedsTallLines(String text) => RegExp(r'[\u0C00-\u0C7F\u0900-\u097F\u0B00-\u0B7F]').hasMatch(text);

/// Colours for a severity that pass contrast in light and dark themes.
({Color fg, Color bg, IconData icon, String label}) askodoxSeverityStyle(AskodoxSeverity severity, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (severity) {
    AskodoxSeverity.ok => (
        fg: dark ? const Color(0xFF7EE2A8) : const Color(0xFF1B6E3C),
        bg: dark ? const Color(0xFF12301F) : const Color(0xFFE8F5EC),
        icon: Icons.check_circle_outline_rounded,
        label: 'Good'),
    AskodoxSeverity.caution => (
        fg: dark ? const Color(0xFFFFC27A) : const Color(0xFF9A4A00),
        bg: dark ? const Color(0xFF3A2A12) : const Color(0xFFFFF4E5),
        icon: Icons.warning_amber_rounded,
        label: 'Caution'),
    AskodoxSeverity.risk => (
        fg: dark ? const Color(0xFFFF9B94) : const Color(0xFFB42318),
        bg: dark ? const Color(0xFF3B1714) : const Color(0xFFFDECEC),
        icon: Icons.error_outline_rounded,
        label: 'Risk'),
    AskodoxSeverity.neutral => (
        fg: dark ? const Color(0xFFE6EAF2) : const Color(0xFF10204A),
        bg: const Color(0x00000000),
        icon: Icons.circle_outlined,
        label: ''),
  };
}

/// True when [text] carries markup worth rendering.
bool askodoxHasMarkup(String text) => _inlineMarkup.hasMatch(text) || _hasSeverity(text);

/// The reply as plain words for speech / history / search (no markers).
String askodoxPlainReply(String text) => text
    .replaceAll(RegExp(r'^(\s*(?:[-*•]|\d{1,2}[.)])?\s*)(?:\[(?:ok|good|caution|warning|risk|danger)\]|✅|✔️|✔|⚠️|⚠|❌|🚫|⛔)\s*',
        multiLine: true, caseSensitive: false), r'$1')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\((https?://[^)\s]+)\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'\*\*|__'), '')
    .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '• ')
    .replaceAll(RegExp(r'^\s*\|?\s*:?-{3,}.*$', multiLine: true), '')
    .replaceAll(RegExp(r'\s*\|\s*'), ' | ')
    .replaceAll(RegExp(r'^ \| | \| $', multiLine: true), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// One parsed block of a reply.
sealed class AskodoxReplyBlock {
  const AskodoxReplyBlock();
}

class AskodoxHeading extends AskodoxReplyBlock {
  const AskodoxHeading(this.text);
  final String text;
}

class AskodoxParagraph extends AskodoxReplyBlock {
  const AskodoxParagraph(this.text, {this.severity = AskodoxSeverity.neutral});
  final String text;
  final AskodoxSeverity severity;
}

class AskodoxListItem extends AskodoxReplyBlock {
  const AskodoxListItem(this.text, {this.number, this.severity = AskodoxSeverity.neutral});
  final String text;
  final String? number;
  final AskodoxSeverity severity;
}

class AskodoxTable extends AskodoxReplyBlock {
  const AskodoxTable(this.rows);
  final List<List<String>> rows;
}

/// Splits a reply into blocks. Separator rows of a table are dropped.
List<AskodoxReplyBlock> askodoxParseReply(String text) {
  final blocks = <AskodoxReplyBlock>[];
  final paragraph = <String>[];
  final table = <List<String>>[];
  void flush() {
    if (paragraph.isNotEmpty) {
      final (severity, first) = askodoxSeverityOf(paragraph.first);
      blocks.add(AskodoxParagraph([first, ...paragraph.skip(1)].join('\n'), severity: severity));
      paragraph.clear();
    }
    if (table.isNotEmpty) {
      blocks.add(AskodoxTable(List.of(table)));
      table.clear();
    }
  }

  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      if (paragraph.isNotEmpty) {
        blocks.add(AskodoxParagraph(paragraph.join('\n')));
        paragraph.clear();
      }
      if (RegExp(r'^\|?\s*:?-{3,}').hasMatch(trimmed)) continue;
      table.add([for (final cell in trimmed.replaceAll(RegExp(r'^\||\|$'), '').split('|')) cell.trim()]);
      continue;
    }
    if (table.isNotEmpty) flush();
    final heading = RegExp(r'^\s{0,3}#{1,6}\s+(.+)$').firstMatch(line);
    final bullet = RegExp(r'^\s*[-*•]\s+(.+)$').firstMatch(line);
    final numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.+)$').firstMatch(line);
    if (heading != null) {
      flush();
      blocks.add(AskodoxHeading(heading.group(1)!.replaceAll(RegExp(r'\*\*|__'), '').trim()));
    } else if (bullet != null) {
      flush();
      final (severity, rest) = askodoxSeverityOf(bullet.group(1)!);
      blocks.add(AskodoxListItem(rest, severity: severity));
    } else if (numbered != null) {
      flush();
      final (severity, rest) = askodoxSeverityOf(numbered.group(2)!);
      blocks.add(AskodoxListItem(rest, number: numbered.group(1), severity: severity));
    } else if (_severityTag.hasMatch(line)) {
      flush(); // a tagged line is its own block
      paragraph.add(line);
      flush();
    } else {
      paragraph.add(line);
    }
  }
  flush();
  return blocks;
}

/// Inline **bold** and [label](url) spans; everything else is plain text.
List<InlineSpan> askodoxInlineSpans(String text, TextStyle base, {Color? linkColor}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\[([^\]]+)\]\((https?://[^)\s]+)\)');
  var at = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
    final bold = match.group(1) ?? match.group(2);
    if (bold != null) {
      spans.add(TextSpan(text: bold, style: base.copyWith(fontWeight: FontWeight.w800)));
    } else {
      final url = Uri.tryParse(match.group(4)!);
      spans.add(TextSpan(
        text: match.group(3),
        style: base.copyWith(color: linkColor ?? Colors.blue.shade700, decoration: TextDecoration.underline),
        recognizer: url == null
            ? null
            : (TapGestureRecognizer()..onTap = () => launchUrl(url, mode: LaunchMode.externalApplication)),
      ));
    }
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// Renders an assistant reply. Plain text -> one Text, as before.
class AskodoxRichReply extends StatelessWidget {
  const AskodoxRichReply(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  /// A tagged block: coloured bar + tint + icon + a screen-reader label, so
  /// the meaning never depends on colour alone.
  Widget _marked(BuildContext context, AskodoxSeverity severity, Widget child) {
    if (severity == AskodoxSeverity.neutral) return child;
    final look = askodoxSeverityStyle(severity, Theme.of(context).brightness);
    return Semantics(
      label: look.label,
      container: true,
      child: Container(
        key: ValueKey('askodoxSeverity-${severity.name}'),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: look.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: look.fg, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(look.icon, size: 16, color: look.fg),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tall = askodoxNeedsTallLines(text);
    final style = tall && (this.style.height ?? 1.0) < 1.5 ? this.style.copyWith(height: 1.5) : this.style;
    if (!askodoxHasMarkup(text)) return Text(text, style: style);
    final blocks = askodoxParseReply(text);
    Widget inline(String value, [TextStyle? s]) =>
        Text.rich(TextSpan(style: s ?? style, children: askodoxInlineSpans(value, s ?? style)));
    return Column(
      key: const Key('askodoxRichReply'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : (block is AskodoxListItem ? 3 : 8)),
            child: switch (block) {
              AskodoxHeading(:final text) =>
                inline(text, style.copyWith(fontWeight: FontWeight.w800, fontSize: (style.fontSize ?? 14) + 1)),
              AskodoxParagraph(:final text, :final severity) => _marked(context, severity, inline(text)),
              AskodoxListItem(:final text, :final number, :final severity) => _marked(
                  context,
                  severity,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: number == null ? 16 : 22,
                        child:
                            Text(number == null ? '•' : '$number.', style: style.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Expanded(child: inline(text)),
                    ],
                  ),
                ),
              AskodoxTable(:final rows) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    border: TableBorder.all(color: const Color(0xFFDDE5F0)),
                    children: [
                      for (final (r, row) in rows.indexed)
                        TableRow(children: [
                          for (var c = 0; c < rows.map((x) => x.length).reduce((a, b) => a > b ? a : b); c++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: inline(c < row.length ? row[c] : '',
                                  r == 0 ? style.copyWith(fontWeight: FontWeight.w800) : null),
                            ),
                        ]),
                    ],
                  ),
                ),
            },
          ),
      ],
    );
  }
}
