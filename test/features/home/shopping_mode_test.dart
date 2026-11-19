import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/shopping_mode.dart';

void main() {
  test('shopping mode is OFF when the app opens and one flip turns it ON, another OFF', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(askodoxShoppingModeProvider), isFalse);
    container.read(askodoxShoppingModeProvider.notifier).state = !container.read(askodoxShoppingModeProvider);
    expect(container.read(askodoxShoppingModeProvider), isTrue);
    container.read(askodoxShoppingModeProvider.notifier).state = !container.read(askodoxShoppingModeProvider);
    expect(container.read(askodoxShoppingModeProvider), isFalse);
  });

  test('a new container (a new app start) is OFF again', () {
    final first = ProviderContainer();
    first.read(askodoxShoppingModeProvider.notifier).state = true;
    first.dispose();
    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(second.read(askodoxShoppingModeProvider), isFalse);
  });
}
