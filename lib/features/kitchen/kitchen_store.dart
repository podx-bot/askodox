import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kitchen_logic.dart';

/// The person's kitchen, on this phone only (account-scoped, see `askodoxAccountScopedKeys`).
const askodoxKitchenPrefsKey = 'askodox.kitchen.v1';

final askodoxKitchenClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AskodoxKitchenState {
  const AskodoxKitchenState({this.loaded = false, this.book = const AskodoxKitchenBook()});
  final bool loaded;
  final AskodoxKitchenBook book;
}

class AskodoxKitchenController extends StateNotifier<AskodoxKitchenState> {
  AskodoxKitchenController() : super(const AskodoxKitchenState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = AskodoxKitchenState(loaded: true, book: askodoxKitchenDecode(prefs.getString(askodoxKitchenPrefsKey)));
    } catch (_) {
      if (mounted) state = const AskodoxKitchenState(loaded: true);
    }
  }

  Future<void> _put(AskodoxKitchenBook book) async {
    state = AskodoxKitchenState(loaded: true, book: book);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxKitchenPrefsKey, askodoxKitchenEncode(book));
    } catch (_) {
      // Stays on screen; saved with the next change.
    }
  }

  /// A new item, or the same one again (same id).
  Future<void> saveItem(AskodoxKitchenItem item) async {
    final rest = [for (final i in state.book.items) if (i.id != item.id) i];
    final all = [...rest, item];
    await _put(AskodoxKitchenBook(
        items: all.length > askodoxKitchenMaxItems ? all.sublist(all.length - askodoxKitchenMaxItems) : all, spends: state.book.spends));
  }

  Future<void> removeItem(String id) =>
      _put(AskodoxKitchenBook(items: [for (final i in state.book.items) if (i.id != id) i], spends: state.book.spends));

  /// Moves what is left by [deltaMilli] (never below zero); anything left means it is no longer "finished".
  Future<void> adjust(String id, int deltaMilli) async {
    for (final i in state.book.items) {
      if (i.id != id) continue;
      final next = (i.milli + deltaMilli) < 0 ? 0 : i.milli + deltaMilli;
      await saveItem(i.copyWith(milli: next, finished: next == 0 ? i.finished : false));
    }
  }

  /// "It is finished": nothing left, on the buy list.
  Future<void> finish(String id) async {
    for (final i in state.book.items) {
      if (i.id == id) await saveItem(i.copyWith(milli: 0, finished: true));
    }
  }

  Future<void> addSpend(AskodoxKitchenSpend s) async {
    final all = [...state.book.spends, s];
    await _put(AskodoxKitchenBook(
        items: state.book.items, spends: all.length > askodoxKitchenMaxSpends ? all.sublist(all.length - askodoxKitchenMaxSpends) : all));
  }
}

final askodoxKitchenProvider = StateNotifierProvider<AskodoxKitchenController, AskodoxKitchenState>((ref) => AskodoxKitchenController());
