// Build 1264 regression: the phone sent real bytes to
// /api/attachments/analyze, but production (still on main) answered 404 and
// every attachment showed "could not be analyzed". These tests push ACTUAL
// file bytes through the real RestApiClient (HTTP layer mocked, not the
// picker or the service) and check what the backend receives and what the
// chat gets back.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/services/chat_attachment_service.dart';

// Real file signatures (JPEG SOI/APP0, PNG, PDF, MP4 ftyp) + payload.
final _jpeg = Uint8List.fromList(
    [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, ...List.filled(2048, 7), 0xFF, 0xD9]);
final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(512, 3)]);
final _pdf = Uint8List.fromList(utf8.encode('%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\nTotal 500\n%%EOF'));
final _mp4 =
    Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32, ...List.filled(4096, 1)]);

http.Response _res(String body, int status) =>
    http.Response(body, status, headers: {'content-type': 'application/json; charset=utf-8'});

class _Backend {
  _Backend({this.unified = true, this.status = const {}});

  final bool unified;
  final Map<String, int> status;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  late final client = RestApiClient(
    baseUrl: Uri.parse('https://api.test'),
    httpClient: MockClient((request) async {
      return _handle(request);
    }),
  );
  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    calls.add(path);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies[path] = body;
    expect(request.headers['Content-Type'], startsWith('application/json'));
    if (status[path] != null) {
      return _res(jsonEncode({'detail': 'server said no'}), status[path]!);
    }
    if (path == '/api/attachments/analyze') {
      if (!unified) return _res(jsonEncode({'detail': 'Not Found'}), 404);
      final bytes = base64Decode(body['file_base64'] as String);
      return _res(
          jsonEncode({
            'status': 'success',
            'attachment': {'id': 'att-1', 'kind': 'image', 'size': bytes.length},
            'analysis': {'subject': 'mixer grinder'},
            'facts': 'Shows: mixer grinder (${bytes.length} bytes)',
          }),
          200);
    }
    if (path == '/vision/analyze') {
      final bytes = base64Decode(body['image_base64'] as String);
      expect(bytes.isNotEmpty, isTrue);
      return _res(
          jsonEncode({
            'status': 'success',
            'analysis': {
              'subject': 'Preethi mixer grinder',
              'brand': 'Preethi',
              'visible_text': 'null',
              'side': 'NEED'
            },
          }),
          200);
    }
    if (path == '/vision/analyze-video') {
      return _res(
          jsonEncode({
            'status': 'success',
            'analysis': {'visual_summary': 'a leaking kitchen tap', 'spoken_transcript': 'ఇది రిపేర్ చేయాలి'},
          }),
          200);
    }
    if (path == '/documents/analyze') {
      final text = utf8.decode(base64Decode(body['file_base64'] as String), allowMalformed: true);
      return _res(
          jsonEncode({
            'status': 'success',
            'analysis': {
              'summary': 'invoice',
              'pages': [
                {'text': text.contains('Total 500') ? 'Total 500' : ''}
              ]
            },
          }),
          200);
    }
    return _res('{}', 404);
  }
}

void main() {
  test('unified route: the real bytes, filename and MIME reach the backend', () async {
    final backend = _Backend();
    final service = ApiChatAttachmentService(backend.client);
    final result = await service.analyze(ChatAttachment(name: 'camera_123.jpg', bytes: _jpeg, mimeType: 'image/jpeg'),
        userText: 'what is this', language: 'te');
    final sent = backend.bodies['/api/attachments/analyze']!;
    expect(base64Decode(sent['file_base64'] as String), _jpeg);
    expect(sent['filename'], 'camera_123.jpg');
    expect(sent['mime_type'], 'image/jpeg');
    expect(sent['language'], 'te');
    expect(result.facts, 'Shows: mixer grinder (${_jpeg.length} bytes)');
    expect(result.id, 'att-1');
  });

  test('backend without the unified route (production 1264) falls back to /vision/analyze with the same bytes',
      () async {
    final backend = _Backend(unified: false);
    final service = ApiChatAttachmentService(backend.client);
    final result = await service.analyze(ChatAttachment(name: 'IMG_0042.jpg', bytes: _jpeg, mimeType: 'image/jpeg'),
        userText: '', language: 'te');
    expect(backend.calls, ['/api/attachments/analyze', '/vision/analyze']);
    final sent = backend.bodies['/vision/analyze']!;
    expect(base64Decode(sent['image_base64'] as String), _jpeg);
    expect(sent['mime_type'], 'image/jpeg');
    expect(result.kind, 'image');
    expect(result.facts, contains('Shows: Preethi mixer grinder'));
    expect(result.facts, contains('The customer seems to: want this'));
    expect(result.facts, isNot(contains('null')));
    expect(result.analysis['brand'], 'Preethi');

    // A gallery PNG with no declared MIME: resolved from the extension; the
    // missing unified route is remembered (no second 404).
    await service.analyze(ChatAttachment(name: 'Screenshot.png', bytes: _png, mimeType: 'application/octet-stream'),
        userText: '', language: 'en');
    expect(backend.calls.skip(2), ['/vision/analyze']);
    expect(backend.bodies['/vision/analyze']!['mime_type'], 'image/png');
    expect(base64Decode(backend.bodies['/vision/analyze']!['image_base64'] as String), _png);
  });

  test('fallback: PDF goes to /documents/analyze and video to /vision/analyze-video', () async {
    final backend = _Backend(unified: false);
    final service = ApiChatAttachmentService(backend.client);
    final pdf = await service.analyze(ChatAttachment(name: 'bill.pdf', bytes: _pdf), userText: '', language: 'en');
    final sent = backend.bodies['/documents/analyze']!;
    expect(sent['filename'], 'bill.pdf');
    expect(sent['mime_type'], 'application/pdf');
    expect(base64Decode(sent['file_base64'] as String), _pdf);
    expect(pdf.kind, 'document');
    expect(pdf.facts, 'Summary: invoice\nTotal 500');

    final video = await service.analyze(ChatAttachment(name: 'tap.mp4', bytes: _mp4), userText: 'fix', language: 'te');
    expect(base64Decode(backend.bodies['/vision/analyze-video']!['video_base64'] as String), _mp4);
    expect(backend.bodies['/vision/analyze-video']!['mime_type'], 'video/mp4');
    expect(video.facts, 'Video shows: a leaking kitchen tap\nSaid in the video: ఇది రిపేర్ చేయాలి');
  });

  test('failures carry a safe diagnostic (code + HTTP status), never the body', () async {
    final backend = _Backend(status: {'/api/attachments/analyze': 502});
    final service = ApiChatAttachmentService(backend.client);
    final error = await service
        .analyze(ChatAttachment(name: 'a.jpg', bytes: _jpeg), userText: '', language: 'en')
        .then<ChatAttachmentException?>((_) => null, onError: (Object e) => e as ChatAttachmentException);
    expect(error!.code, 'failed');
    expect(error.statusCode, 502);
    expect(error.diagnostic, 'failed · HTTP 502 · unified');
    expect(error.diagnostic, isNot(contains('server said no')));
    expect(error.retryable, isTrue);
    expect(backend.calls, ['/api/attachments/analyze'], reason: 'only 404/405 fall back');

    final legacy = _Backend(unified: false, status: {'/vision/analyze': 422});
    final notUnderstood = await ApiChatAttachmentService(legacy.client)
        .analyze(ChatAttachment(name: 'a.jpg', bytes: _jpeg), userText: '', language: 'en')
        .then<ChatAttachmentException?>((_) => null, onError: (Object e) => e as ChatAttachmentException);
    expect(notUnderstood!.code, 'not_understood');
    expect(notUnderstood.diagnostic, 'not_understood · HTTP 422 · legacy');
  });

  test('network failure and empty bytes are reported, not hidden', () async {
    final offline = RestApiClient(
        baseUrl: Uri.parse('https://api.test'),
        httpClient: MockClient((_) async => throw http.ClientException('connection reset')));
    final error = await ApiChatAttachmentService(offline)
        .analyze(ChatAttachment(name: 'a.jpg', bytes: _jpeg), userText: '', language: 'en')
        .then<ChatAttachmentException?>((_) => null, onError: (Object e) => e as ChatAttachmentException);
    expect(error!.code, 'network');
    expect(error.statusCode, isNull);
    expect(error.retryable, isTrue);

    final backend = _Backend();
    await expectLater(
        ApiChatAttachmentService(backend.client)
            .analyze(ChatAttachment(name: 'a.jpg', bytes: Uint8List(0)), userText: '', language: 'en'),
        throwsA(isA<ChatAttachmentException>().having((e) => e.code, 'code', 'failed')));
    expect(backend.calls, isEmpty);
  });

  test('facts match backend attachment_facts.py for the same analysis', () {
    expect(askodoxAttachmentFacts('image', {'subject': 'mixer grinder', 'brand': null, 'visible_text': 'null'}),
        'Shows: mixer grinder');
    expect(askodoxAttachmentFacts('image', {}), '');
    expect(
        askodoxAttachmentFacts('document', {
          'summary': 'invoice',
          'pages': [
            {'text': 'Total 500'}
          ]
        }),
        contains('Summary: invoice'));
    expect(
        askodoxAttachmentFacts(
            'image', {'subject': 'rice', 'quantity': 5, 'unit': 'kg', 'price': 300, 'currency': 'INR'}),
        'Shows: rice\nQuantity: 5 kg\nPrice visible: INR 300');
  });
}
