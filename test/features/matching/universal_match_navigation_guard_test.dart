import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match screen return action pops pushed screen before router fallback', () {
    final source = File(
      'lib/features/matching/presentation/universal_match_screen.dart',
    ).readAsStringSync();

    expect(source, contains('void _returnToSearch()'));
    expect(source, contains('Navigator.of(context).canPop()'));
    expect(source, contains('Navigator.of(context).pop()'));
    expect(source, contains("context.go('/search')"));

    final returnHelper = RegExp(
      r"void _returnToSearch\(\)\s*\{([\s\S]*?)context\.go\('/search'\);\s*\}",
    ).firstMatch(source)?.group(1);

    expect(returnHelper, isNotNull);
    expect(returnHelper, contains('Navigator.of(context).pop()'));
    expect(
      source.indexOf('Navigator.of(context).pop()', source.indexOf('void _returnToSearch()')),
      lessThan(source.indexOf("context.go('/search')", source.indexOf('void _returnToSearch()'))),
      reason: 'A pushed match screen must pop first; routing to the already-active /search route can be a no-op.',
    );
  });

  test('all incomplete/no-match actions use the guarded return helper', () {
    final source = File(
      'lib/features/matching/presentation/universal_match_screen.dart',
    ).readAsStringSync();

    expect(source, contains('onPressed: _returnToSearch'));
    expect(source, contains('onComplete: _returnToSearch'));
    expect(source, contains('return _NoMatches(onBroaden: _returnToSearch'));
  });
}
