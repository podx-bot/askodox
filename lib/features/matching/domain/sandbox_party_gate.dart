enum SandboxPartySide { partyA, partyB }

class SandboxPartyGateState {
  const SandboxPartyGateState({
    required this.dealId,
    required this.matchId,
    this.partyAAccepted = false,
    this.partyBAccepted = false,
  });

  final String dealId;
  final String matchId;
  final bool partyAAccepted;
  final bool partyBAccepted;

  bool get conversationReady => partyAAccepted && partyBAccepted;
  bool get contactSharingAllowed => conversationReady;

  SandboxPartyGateState copyWith({
    bool? partyAAccepted,
    bool? partyBAccepted,
  }) =>
      SandboxPartyGateState(
        dealId: dealId,
        matchId: matchId,
        partyAAccepted: partyAAccepted ?? this.partyAAccepted,
        partyBAccepted: partyBAccepted ?? this.partyBAccepted,
      );
}

class SandboxPartyGateStore {
  final Map<String, SandboxPartyGateState> _states =
      <String, SandboxPartyGateState>{};

  String _key(String dealId, String matchId) => '$dealId::$matchId';

  SandboxPartyGateState stateFor({
    required String dealId,
    required String matchId,
  }) =>
      _states[_key(dealId, matchId)] ??
      SandboxPartyGateState(dealId: dealId, matchId: matchId);

  SandboxPartyGateState accept({
    required String dealId,
    required String matchId,
    required SandboxPartySide side,
  }) {
    final current = stateFor(dealId: dealId, matchId: matchId);
    final next = switch (side) {
      SandboxPartySide.partyA => current.copyWith(partyAAccepted: true),
      SandboxPartySide.partyB => current.copyWith(partyBAccepted: true),
    };
    _states[_key(dealId, matchId)] = next;
    return next;
  }

  bool canOpenConversation({required String dealId, required String matchId}) =>
      stateFor(dealId: dealId, matchId: matchId).conversationReady;

  bool canShareContact({required String dealId, required String matchId}) =>
      stateFor(dealId: dealId, matchId: matchId).contactSharingAllowed;

  void clear({required String dealId, required String matchId}) {
    _states.remove(_key(dealId, matchId));
  }
}
