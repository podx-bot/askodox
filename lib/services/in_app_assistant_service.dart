import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class InAppAssistantTurn {
  const InAppAssistantTurn({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class InAppAssistantDecision {
  const InAppAssistantDecision({
    required this.reply,
    required this.domain,
    required this.transactional,
    required this.action,
    required this.confidence,
    required this.source,
    this.entities = const <String, Object?>{},
  });

  final String reply;
  final String domain;
  final bool transactional;
  final String action;
  final double confidence;
  final String source;

  /// Semantic facts extracted by the Universal AI layer. These are deliberately
  /// separate from the natural reply so deterministic business modules can use
  /// meaning directly instead of re-parsing keyword-prefixed text.
  final Map<String, Object?> entities;

  bool get usable => source == 'universal_ai' && reply.trim().isNotEmpty;

  factory InAppAssistantDecision.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    final entities = <String, Object?>{};
    if (rawEntities is Map) {
      for (final entry in rawEntities.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (key.isNotEmpty && entry.value != null) {
          entities[key] = entry.value;
        }
      }
    }

    return InAppAssistantDecision(
      reply: (json['reply'] ?? '').toString(),
      domain: (json['domain'] ?? 'UNKNOWN').toString().toUpperCase(),
      transactional: json['transactional'] == true,
      action: (json['action'] ?? '').toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      source: (json['source'] ?? 'fallback').toString(),
      entities: Map.unmodifiable(entities),
    );
  }

  String? entityText(String key) {
    final value = entities[key.trim().toLowerCase()];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  num? entityNumber(String key) {
    final value = entities[key.trim().toLowerCase()];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

class InAppAssistantService {
  const InAppAssistantService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl =
      'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client? _client;

  Future<InAppAssistantDecision?> decide({
    required String message,
    required String locale,
    required List<InAppAssistantTurn> history,
    String? location,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) return null;
    final cleanLocation = location?.trim();

    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/assistant'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': clean,
              'locale': locale,
              'history': history.takeLast(12).map((turn) => turn.toJson()).toList(),
              if (cleanLocation != null && cleanLocation.isNotEmpty) 'location': cleanLocation,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return InAppAssistantDecision.fromJson(decoded);
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    } finally {
      if (ownClient) client.close();
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    if (count <= 0) return const Iterable.empty();
    final list = toList(growable: false);
    if (list.length <= count) return list;
    return list.skip(list.length - count);
  }
}
