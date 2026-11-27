import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// New-look guard (owner 2026-11-27): a file may never hold MORE hand-written colours (`Color(0x..)`, `Colors.x`) than
/// the baseline. New colours come from `AskodoxLook` / the theme. When you clean a file, lower its number in
/// test/fixtures/raw_colour_baseline.json (a file not listed = 0 allowed).
void main() {
  test('no file gains hand-written colours', () {
    final base = (jsonDecode(File('test/fixtures/raw_colour_baseline.json').readAsStringSync()) as Map).cast<String, num>();
    final pat = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)|Colors\.[a-zA-Z]+');
    final over = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final path = e.path.replaceAll('\\', '/');
      if (path.endsWith('config/theme/askodox_look.dart')) continue;
      final n = pat.allMatches(e.readAsStringSync()).length;
      final allowed = (base[path] ?? 0).toInt();
      if (n > allowed) over.add('$path: $n > $allowed');
    }
    expect(over, isEmpty, reason: 'Use AskodoxLook / theme colours, not new hand-written ones:\n${over.join('\n')}');
  });
}
