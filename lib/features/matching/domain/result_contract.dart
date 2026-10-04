import 'package:flutter/foundation.dart';

/// The ONE canonical ASKODOX result contract (backend
/// `result_orchestrator.py`, `result_contract_version` >= 2): independent
/// sections the backend already classified, ordered and explained. The app
/// renders from it and never re-sorts across sections; a section that is
/// empty (a source down) never removes another one.
@immutable
class ResultSection {
  const ResultSection({required this.kind, required this.itemIds, this.requested = false, this.emptyReason});

  factory ResultSection.fromJson(Map<String, Object?> json) => ResultSection(
        kind: '${json['kind'] ?? ''}',
        itemIds: [for (final id in (json['item_ids'] as List? ?? const [])) '$id'],
        requested: json['requested'] == true,
        emptyReason: json['empty_reason']?.toString(),
      );

  final String kind;
  final List<String> itemIds;

  /// The customer asked for this group ("videos", "online links").
  final bool requested;

  /// Why an asked-for section is empty (e.g. "source unavailable right now").
  final String? emptyReason;
}

@immutable
class ResultContract {
  const ResultContract({
    required this.version,
    this.sections = const [],
    this.mayClaimResults = false,
    this.checked = const [],
    this.unavailable = const [],
    this.explicitConstraints = const {},
  });

  /// Null for an older backend (no sections): the app keeps its old order.
  static ResultContract? fromJson(Map<String, Object?> data) {
    final version = (data['result_contract_version'] as num?)?.toInt();
    final raw = data['sections'];
    if (version == null || version < 2 || raw is! List) return null;
    final answer = data['answer'] is Map ? Map<String, Object?>.from(data['answer'] as Map) : const <String, Object?>{};
    final state = data['conversation_state'] is Map
        ? Map<String, Object?>.from(data['conversation_state'] as Map)
        : const <String, Object?>{};
    final constraints = state['explicit_constraints'];
    return ResultContract(
      version: version,
      sections: [
        for (final s in raw)
          if (s is Map) ResultSection.fromJson(Map<String, Object?>.from(s)),
      ],
      mayClaimResults: answer['may_claim_results'] == true,
      checked: [for (final c in (answer['checked'] as List? ?? const [])) '$c'],
      unavailable: [for (final c in (answer['unavailable'] as List? ?? const [])) '$c'],
      explicitConstraints: constraints is Map ? {for (final e in constraints.entries) '${e.key}': e.value} : const {},
    );
  }

  final int version;
  final List<ResultSection> sections;

  /// The backend's verdict: the reply may say "here are options" only when true.
  final bool mayClaimResults;
  final List<String> checked;
  final List<String> unavailable;

  /// The customer's own constraints exactly as the backend kept them.
  final Map<String, Object?> explicitConstraints;

  List<String> get kinds => [for (final s in sections) s.kind];

  /// [rows] in contract order (section by section, item order inside each).
  /// Rows the contract does not list are kept at the end -- never dropped.
  List<T> order<T>(List<T> rows, String Function(T row) idOf) {
    final byId = <String, T>{};
    for (final row in rows) {
      byId.putIfAbsent(idOf(row), () => row);
    }
    final out = <T>[];
    final used = <String>{};
    for (final section in sections) {
      for (final id in section.itemIds) {
        final row = byId[id];
        if (row != null && used.add(id)) out.add(row);
      }
    }
    for (final row in rows) {
      if (used.add(idOf(row))) out.add(row);
    }
    return out;
  }
}
