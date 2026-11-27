import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'yield_math.dart';

/// The yield books of the person's shops, on this phone only for now (account-scoped, see
/// `askodoxAccountScopedKeys`). The last [askodoxYieldKeep] lots and day closes of a shop are kept.
const askodoxYieldPrefsKey = 'askodox.yield.v1';
const askodoxYieldKeep = 400;

final askodoxYieldClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AskodoxYieldState {
  const AskodoxYieldState({this.loaded = false, this.books = const {}});
  final bool loaded;
  final Map<String, AskodoxYieldBook> books;

  AskodoxYieldBook book(String shop) => books[shop] ?? const AskodoxYieldBook();
}

class AskodoxYieldController extends StateNotifier<AskodoxYieldState> {
  AskodoxYieldController() : super(const AskodoxYieldState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = AskodoxYieldState(loaded: true, books: askodoxYieldDecode(prefs.getString(askodoxYieldPrefsKey)));
    } catch (_) {
      if (mounted) state = const AskodoxYieldState(loaded: true);
    }
  }

  Future<void> _put(String shop, AskodoxYieldBook book) async {
    state = AskodoxYieldState(loaded: true, books: {...state.books, shop: book});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxYieldPrefsKey, askodoxYieldEncode(state.books));
    } catch (_) {
      // Stays on screen; saved with the next change.
    }
  }

  List<T> _kept<T>(List<T> rows) => rows.length > askodoxYieldKeep ? rows.sublist(rows.length - askodoxYieldKeep) : rows;

  /// A new lot, or the same lot again with its later numbers (same id).
  Future<void> saveBatch(String shop, AskodoxYieldBatch batch) async {
    final book = state.book(shop);
    final rest = [for (final b in book.batches) if (b.id != batch.id) b];
    await _put(shop, AskodoxYieldBook(batches: _kept([...rest, batch]), days: book.days, minProfit: book.minProfit));
  }

  Future<void> saveDay(String shop, AskodoxYieldDay day) async {
    final book = state.book(shop);
    final rest = [for (final d in book.days) if (d.item != day.item || d.day != day.day) d];
    await _put(shop, AskodoxYieldBook(batches: book.batches, days: _kept([...rest, day]), minProfit: book.minProfit));
  }

  Future<void> setMinProfit(String shop, String item, int paise) async {
    final book = state.book(shop);
    await _put(shop,
        AskodoxYieldBook(batches: book.batches, days: book.days, minProfit: {...book.minProfit, item: paise < 0 ? 0 : paise}));
  }
}

final askodoxYieldProvider =
    StateNotifierProvider<AskodoxYieldController, AskodoxYieldState>((ref) => AskodoxYieldController());
