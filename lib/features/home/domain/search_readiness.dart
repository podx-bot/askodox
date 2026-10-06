/// THE one search-readiness gate. Every path that can start a retrieval
/// (local sellers, nearby, online, affiliate, deals, used, videos) asks it
/// first; the presentation layer never searches on its own.
///
/// Who decides, in order:
/// 1. the user explicitly asked to see options now ("show me", videos) --
///    a direct instruction always wins;
/// 2. the Conversation Decision Brain (backend AI with the whole
///    conversation) -- `searchReady` true / false for THIS turn;
/// 3. only when the brain gave no readiness (AI unavailable, older
///    backend): the offline rule (the request's schema slots are filled,
///    or the same question would loop).
library;

enum AskodoxSearchGateSource { user, brain, offlineSchema, offlineLoop, none }

class AskodoxSearchGate {
  const AskodoxSearchGate(this.allowed, this.source, this.reason);

  final bool allowed;
  final AskodoxSearchGateSource source;

  /// Short machine-readable reason (diagnostics trace).
  final String reason;

  @override
  String toString() => '${allowed ? 'search' : 'hold'} (${source.name}: $reason)';
}

AskodoxSearchGate askodoxSearchGate({
  required bool hasSubject,
  required bool? brainReady,
  required bool userAskedNow,
  required bool schemaReady,
  bool repeating = false,
  String brainReason = '',
}) {
  if (brainReady != null) {
    if (userAskedNow && hasSubject) {
      return const AskodoxSearchGate(true, AskodoxSearchGateSource.user, 'user asked to see options now');
    }
    if (brainReady && (hasSubject || schemaReady)) {
      return AskodoxSearchGate(true, AskodoxSearchGateSource.brain,
          brainReason.isEmpty ? 'brain: enough is known' : 'brain: $brainReason');
    }
    return AskodoxSearchGate(false, AskodoxSearchGateSource.brain,
        brainReason.isEmpty ? 'brain: decision-critical details still unknown' : 'brain: $brainReason');
  }
  if (schemaReady) {
    return const AskodoxSearchGate(true, AskodoxSearchGateSource.offlineSchema, 'offline: required slots filled');
  }
  if (userAskedNow && hasSubject) {
    return const AskodoxSearchGate(true, AskodoxSearchGateSource.user, 'user asked to see options now');
  }
  if (repeating && hasSubject) {
    return const AskodoxSearchGate(true, AskodoxSearchGateSource.offlineLoop, 'offline: question would repeat');
  }
  return const AskodoxSearchGate(false, AskodoxSearchGateSource.none, 'not enough known yet');
}
