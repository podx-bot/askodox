/// The Result Board: an OPTIONAL visual layer above the conversation, never
/// its replacement. One lifecycle and one sizing rule for every category,
/// role and language (docs/UNIVERSAL_DEVELOPMENT_RULE.md) -- the screen asks
/// these pure functions instead of re-deciding in widgets.
library;

/// Where the board is in its lifecycle.
enum AskodoxBoardState {
  /// No results belong to this conversation (ordinary chat, advice, ...).
  hidden,

  /// Results are being refreshed (new place / new details) -- old cards dim.
  loading,

  /// Results are visible above the conversation.
  expanded,

  /// Folded into its one-line pill by the customer (or because the screen is
  /// too short right now); one tap restores it.
  minimized,

  /// The cards answer earlier details; refresh pending.
  stale,

  /// Retired by a topic change: only a small "Earlier results" chip remains.
  archived,
}

/// The board's state from the screen's facts. [selected] (a pinned option)
/// is orthogonal: it travels with the expanded board and the pill.
AskodoxBoardState askodoxBoardStateOf({
  required bool hasDeck,
  required bool retired,
  required bool minimized,
  bool refreshing = false,
  bool outdated = false,
}) {
  if (!hasDeck) return AskodoxBoardState.hidden;
  if (retired) return AskodoxBoardState.archived;
  if (minimized) return AskodoxBoardState.minimized;
  if (refreshing) return AskodoxBoardState.loading;
  if (outdated) return AskodoxBoardState.stale;
  return AskodoxBoardState.expanded;
}

/// Room the conversation always keeps below the board: the input row plus
/// at least the latest assistant lines (logical pixels).
const double askodoxComposerReserve = 76;
const double askodoxConversationMinimum = 150;

/// The board's smallest useful height: a header line plus one card row.
const double askodoxBoardMinimum = 104;

/// The tallest the WHOLE board (notices + cards + minimize row) may be,
/// from the height actually available to the Home column (below the app
/// header, above the nav, minus the keyboard). Null = there is no room for
/// a useful board right now: show its pill instead (the customer's own
/// minimize / restore choice is untouched).
double? askodoxBoardMaxHeight(double available, {required bool keyboard, bool expanded = false}) {
  if (!available.isFinite || available <= 0) return null;
  final share = keyboard ? (expanded ? .30 : .24) : (expanded ? .44 : .34);
  final leftForChat = available - askodoxComposerReserve - askodoxConversationMinimum;
  final height = (available * share).clamp(0.0, leftForChat < 0 ? 0.0 : leftForChat);
  return height < askodoxBoardMinimum ? null : height;
}
