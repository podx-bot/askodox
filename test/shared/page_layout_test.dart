import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/page_layout.dart';

void main() {
  test('saved order first, new buttons at the end, removed ones ignored (owner 2026-11-19)', () {
    const layout = AskodoxSectionLayout(order: ['c', 'gone', 'a']);
    expect(askodoxArrangedIds(['a', 'b', 'c', 'd'], layout), ['c', 'a', 'b', 'd']);
    expect(askodoxArrangedIds(['a', 'b'], const AskodoxSectionLayout()), ['a', 'b']);
  });

  test('names are labels only; empty names / titles fall back to the shipped ones', () {
    final layout = AskodoxSectionLayout.fromJson({
      'title': '  ',
      'order': ['b', 'a'],
      'hidden': ['a'],
      'names': {'b': 'Bills', 'a': ' '},
    });
    expect(layout.title, isNull);
    expect(layout.names, {'b': 'Bills'});
    expect(layout.hidden, {'a'});
    expect(AskodoxSectionLayout.fromJson(layout.toJson()).order, ['b', 'a']);
    expect(const AskodoxSectionLayout().isDefault, isTrue);
  });
}
