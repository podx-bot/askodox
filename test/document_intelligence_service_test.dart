import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/document_intelligence_service.dart';

void main() {
  test('posts document payload and parses structured analysis', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/documents/analyze');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'analysis': {
            'kind': 'text',
            'text': 'Invoice total 1200',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = DocumentIntelligenceService(client: client);
    final result = await service.analyzeBytes(
      bytes: Uint8List.fromList(utf8.encode('Invoice total 1200')),
      filename: 'invoice.txt',
      mimeType: 'text/plain',
    );

    expect(result, isNotNull);
    expect(requestBody['filename'], 'invoice.txt');
    expect(requestBody['mime_type'], 'text/plain');
    expect(base64Decode(requestBody['file_base64'] as String),
        utf8.encode('Invoice total 1200'));
    expect(result!.analysis['text'], 'Invoice total 1200');
  });

  test('conversationSeed combines document text and spreadsheet rows', () {
    const result = DocumentIntelligenceResult(
      filename: 'report.xlsx',
      analysis: {
        'summary': 'Monthly sales report',
        'sheets': [
          {
            'name': 'August',
            'rows': [
              ['Item', 'Amount'],
              ['Chicken', 1200],
            ],
          },
        ],
      },
    );

    final seed = result.conversationSeed();
    expect(seed, contains('Monthly sales report'));
    expect(seed, contains('August'));
    expect(seed, contains('Chicken | 1200'));
  });
}
