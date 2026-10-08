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

/// True when [text] carries markup worth rendering.
bool askodoxHasMarkup(String text) => _inlineMarkup.hasMatch(text);

/// The reply as plain words for speech / history / search (no markers).
String askodoxPlainReply(String text) => text
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
  const AskodoxParagraph(this.text);
  final String text;
}

class AskodoxListItem extends AskodoxReplyBlock {
  const AskodoxListItem(this.text, {this.number});
  final String text;
  final String? number;
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
      blocks.add(AskodoxParagraph(paragraph.join('\n')));
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
      blocks.add(AskodoxListItem(bullet.group(1)!));
    } else if (numbered != null) {
      flush();
      blocks.add(AskodoxListItem(numbered.group(2)!, number: numbered.group(1)));
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

  @override
  Widget build(BuildContext context) {
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
              AskodoxParagraph(:final text) => inline(text),
              AskodoxListItem(:final text, :final number) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: number == null ? 16 : 22,
                      child: Text(number == null ? '•' : '$number.', style: style.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Expanded(child: inline(text)),
                  ],
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
