import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of handing a conversation to ASKODOX Support.
class AskodoxSupportCase {
  const AskodoxSupportCase({
    required this.caseId,
    this.whatsappUrl,
    this.callUri,
  });

  final String caseId;

  /// Present only when WhatsApp Support is configured on the backend.
  final String? whatsappUrl;

  /// Present only when phone Support is configured on the backend.
  final String? callUri;
}

/// Escalates to ASKODOX Support with the full context (issue, AI
/// conversation, requirement, deal id, counterpart, what was tried, status)
/// via `POST /api/in-app/support/escalate`, so the user never re-explains.
class SupportEscalationService {
  const SupportEscalationService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  Future<AskodoxSupportCase?> escalate({
    required String issue,
    required String category,
    required bool critical,
    required List<Map<String, String>> conversation,
    Map<String, Object?> requirement = const {},
    String? dealId,
    String? counterpart,
    List<String> actionsTried = const [],
    String status = '',
    String activeRole = '',
    String locale = '',
    String? authToken,
  }) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/support/escalate'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              if (authToken != null && authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({
              'issue': issue,
              'category': category,
              'critical': critical,
              'conversation': conversation,
              'requirement': requirement,
              'deal_id': dealId,
              'counterpart': counterpart,
              'actions_tried': actionsTried,
              'status': status,
              'active_role': activeRole,
              'locale': locale,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['case_id'] == null) return null;
      final channels = decoded['channels'] is Map ? decoded['channels'] as Map : const {};
      return AskodoxSupportCase(
        caseId: '${decoded['case_id']}',
        whatsappUrl: channels['whatsapp_url']?.toString(),
        callUri: channels['call_uri']?.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
