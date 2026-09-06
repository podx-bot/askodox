import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class DocumentIntelligenceResult {
  const DocumentIntelligenceResult({
    required this.filename,
    required this.analysis,
  });

  final String filename;
  final Map<String, dynamic> analysis;

  String conversationSeed() {
    final parts = <String>[];
    void add(Object? value) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        parts.add(text);
      }
    }

    add(analysis['summary']);
    add(analysis['text']);
    add(analysis['visible_text']);

    final pages = analysis['pages'];
    if (pages is List) {
      for (final page in pages.take(8)) {
        if (page is Map) add(page['text']);
      }
    }

    final sheets = analysis['sheets'];
    if (sheets is List) {
      for (final sheet in sheets.take(4)) {
        if (sheet is! Map) continue;
        add(sheet['name']);
        final rows = sheet['rows'];
        if (rows is List) {
          for (final row in rows.take(20)) {
            if (row is List) add(row.join(' | '));
          }
        }
      }
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      final normalized = part.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      unique.add(normalized);
    }
    return unique.join('\n').trim();
  }
}

class DocumentIntelligenceService {
  const DocumentIntelligenceService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl =
      'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client? _client;

  Future<DocumentIntelligenceResult?> pickAndAnalyze() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'xlsx', 'csv', 'txt', 'json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return null;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return null;
      return analyzeBytes(
        bytes: bytes,
        filename: file.name,
        mimeType: _mimeType(file.extension),
      );
    } catch (_) {
      return null;
    }
  }

  Future<DocumentIntelligenceResult?> analyzeBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (bytes.isEmpty || filename.trim().isEmpty) return null;
    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    try {
      final response = await client
          .post(
            Uri.parse('${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/documents/analyze'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'file_base64': base64Encode(bytes),
              'filename': filename.trim(),
              'mime_type': mimeType.trim().isEmpty
                  ? 'application/octet-stream'
                  : mimeType.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != 'success') {
        return null;
      }
      final analysis = decoded['analysis'];
      if (analysis is! Map) return null;
      return DocumentIntelligenceResult(
        filename: filename.trim(),
        analysis: Map<String, dynamic>.from(analysis),
      );
    } catch (_) {
      return null;
    } finally {
      if (ownsClient) client.close();
    }
  }

  static String _mimeType(String? extension) {
    return switch ((extension ?? '').toLowerCase()) {
      'pdf' => 'application/pdf',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      'json' => 'application/json',
      _ => 'application/octet-stream',
    };
  }
}
