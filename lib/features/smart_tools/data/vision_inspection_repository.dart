import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../services/chat_attachment_service.dart';

/// Evidence-tiered photo inspection (`POST /api/vision/inspect`). The
/// backend owns the domain list, the never-claim rules and the cost bounds;
/// this side only sends photos and renders the report as given.
class AskodoxInspectionFinding {
  const AskodoxInspectionFinding(this.finding, {this.detail, this.confidence = 0});
  final String finding;
  final String? detail; // region (observed) or basis (inferred)
  final double confidence;
}

class AskodoxInspectionQuantity {
  const AskodoxInspectionQuantity(
      {required this.name, required this.low, required this.high, required this.unit, this.basis, this.status = 'estimate'});
  final String name;
  final double low;
  final double high;
  final String unit;
  final String? basis;
  final String status; // estimate | experimental
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

List<String> _strings(Object? v) => v is List ? [for (final x in v) if ('$x'.trim().isNotEmpty) '$x'.trim()] : const [];

class AskodoxInspectionReport {
  const AskodoxInspectionReport({
    required this.domain,
    required this.mode,
    required this.status,
    this.subject,
    this.observed = const [],
    this.inferred = const [],
    this.notVerifiable = const [],
    this.recommendedChecks = const [],
    this.safetyWarnings = const [],
    this.quantities = const [],
    this.needsMoreEvidence = const [],
    this.limits = const [],
    this.visibleText,
    this.confidence = 0,
    this.cached = false,
    this.facts = '',
  });

  final String domain;
  final String mode;
  final String status; // ok | low_confidence | insufficient_evidence
  final String? subject;
  final List<AskodoxInspectionFinding> observed;
  final List<AskodoxInspectionFinding> inferred;
  final List<String> notVerifiable;
  final List<String> recommendedChecks;
  final List<String> safetyWarnings;
  final List<AskodoxInspectionQuantity> quantities;
  final List<String> needsMoreEvidence;
  final List<String> limits;
  final String? visibleText;
  final double confidence;
  final bool cached;

  /// Plain-text summary the backend made for the conversation context.
  final String facts;

  factory AskodoxInspectionReport.fromJson(Map<String, Object?> json, {String facts = ''}) {
    List<AskodoxInspectionFinding> findings(Object? v, String detailKey) => v is List
        ? [
            for (final item in v)
              if (item is Map && '${item['finding'] ?? ''}'.trim().isNotEmpty)
                AskodoxInspectionFinding('${item['finding']}'.trim(),
                    detail: item[detailKey] == null ? null : '${item[detailKey]}',
                    confidence: _d(item['confidence'])),
          ]
        : const [];
    final quantities = json['quantities'] is List
        ? [
            for (final q in json['quantities'] as List)
              if (q is Map)
                AskodoxInspectionQuantity(
                    name: '${q['name'] ?? ''}',
                    low: _d(q['low']),
                    high: _d(q['high']),
                    unit: '${q['unit'] ?? ''}',
                    basis: q['basis'] == null ? null : '${q['basis']}',
                    status: '${q['status'] ?? 'estimate'}'),
          ]
        : const <AskodoxInspectionQuantity>[];
    final cost = json['cost'];
    return AskodoxInspectionReport(
      domain: '${json['domain'] ?? 'general'}',
      mode: '${json['mode'] ?? 'quick'}',
      status: '${json['status'] ?? 'ok'}',
      subject: json['subject'] == null ? null : '${json['subject']}',
      observed: findings(json['observed'], 'region'),
      inferred: findings(json['inferred'], 'basis'),
      notVerifiable: _strings(json['not_verifiable']),
      recommendedChecks: _strings(json['recommended_checks']),
      safetyWarnings: _strings(json['safety_warnings']),
      quantities: quantities,
      needsMoreEvidence: _strings(json['needs_more_evidence']),
      limits: _strings(json['limits']),
      visibleText: json['visible_text'] == null ? null : '${json['visible_text']}',
      confidence: _d(json['confidence']),
      cached: cost is Map && cost['cached'] == true,
      facts: facts,
    );
  }
}

class AskodoxInspectionProfile {
  const AskodoxInspectionProfile(this.domain, this.label, this.guidance);
  final String domain;
  final String label;
  final List<String> guidance;
}

class AskodoxInspectionException implements Exception {
  const AskodoxInspectionException(this.code, {this.statusCode});

  /// unavailable | too_large | rate_limited | network | failed
  final String code;
  final int? statusCode;

  String message(bool te) => switch (code) {
        'unavailable' => te ? 'ఫోటో పరిశీలన ఇప్పుడు అందుబాటులో లేదు. కొద్దిసేపటి తర్వాత ప్రయత్నించండి.'
            : 'Photo inspection is not available right now. Please try again later.',
        'too_large' => te ? 'ఫోటో చాలా పెద్దది (గరిష్టం 12 MB).' : 'The photo is too large (max 12 MB).',
        'rate_limited' => te ? 'చాలా అభ్యర్థనలు. ఒక నిమిషం ఆగి ప్రయత్నించండి.' : 'Too many requests. Wait a minute and try again.',
        'network' => te ? 'ఇంటర్నెట్ కనెక్షన్ చూడండి.' : 'Check your internet connection.',
        _ => te ? 'పరిశీలన విఫలమైంది. మళ్ళీ ప్రయత్నించండి.' : 'The inspection failed. Please try again.',
      };

  @override
  String toString() => 'AskodoxInspectionException($code, $statusCode)';
}

class AskodoxVisionInspectionRepository {
  AskodoxVisionInspectionRepository(this._client);
  final ApiClient _client;

  Future<List<AskodoxInspectionProfile>> profiles(String language) async {
    final result = await _client.get<Map<String, Object?>>('/api/vision/profiles',
        options: ApiRequestOptions(query: {'language': language}));
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final rows = data['profiles'];
      if (rows is List) {
        return [
          for (final row in rows)
            if (row is Map)
              AskodoxInspectionProfile('${row['domain']}', '${row['label']}', _strings(row['guidance'])),
        ];
      }
    }
    return const [];
  }

  Future<AskodoxInspectionReport> inspect(
    List<ChatAttachment> photos, {
    required String domain,
    required String mode,
    required String language,
    String userText = '',
    String referenceObject = '',
  }) async {
    final images = [
      for (final p in photos)
        if (p.isImage) {'image_base64': base64Encode(p.bytes), 'mime_type': p.mimeType},
    ];
    if (images.isEmpty) throw const AskodoxInspectionException('failed');
    final result = await _client.post<Map<String, Object?>>(
      '/api/vision/inspect',
      body: {
        'images': images,
        'domain': domain,
        'mode': mode,
        'language': language,
        'user_text': userText,
        'reference_object': referenceObject,
      },
      options: const ApiRequestOptions(timeout: Duration(seconds: 90)),
    );
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final report = data['report'];
      if (report is Map) {
        return AskodoxInspectionReport.fromJson(Map<String, Object?>.from(report), facts: '${data['facts'] ?? ''}');
      }
      throw const AskodoxInspectionException('failed');
    }
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    final status = failure.statusCode;
    throw AskodoxInspectionException(
      switch (status) {
        502 || 503 => 'unavailable',
        413 => 'too_large',
        429 => 'rate_limited',
        null => 'network',
        _ => 'failed',
      },
      statusCode: status,
    );
  }
}

final askodoxVisionInspectionRepositoryProvider =
    Provider<AskodoxVisionInspectionRepository>((ref) => AskodoxVisionInspectionRepository(ref.watch(apiClientProvider)));
