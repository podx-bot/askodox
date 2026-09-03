import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:podx/services/vision_api_service.dart';

void main() {
  test('vision client sends image payload and returns structured analysis', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/vision/analyze');
      expect(request.headers['content-type'], contains('application/json'));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['mime_type'], 'image/png');
      expect(body['user_text'], 'find this nearby');
      expect(body['language'], 'en');
      expect(base64Decode(body['image_base64'] as String), [1, 2, 3, 4]);

      return http.Response(
        jsonEncode({
          'status': 'success',
          'analysis': {
            'summary': 'A blue shoe is visible.',
            'deal_hints': {
              'subject': 'shoe',
              'variant': 'blue',
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = VisionApiService(client: client);
    final image = XFile.fromData(
      Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'image/png',
      name: 'shoe.png',
    );

    final analysis = await service.analyze(
      image: image,
      userText: 'find this nearby',
      language: 'en',
    );

    expect(analysis?['summary'], 'A blue shoe is visible.');
    expect((analysis?['deal_hints'] as Map?)?['subject'], 'shoe');
  });

  test('vision client fails softly when backend does not return success', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({'status': 'not_configured'}),
          200,
          headers: {'content-type': 'application/json'},
        ));

    final service = VisionApiService(client: client);
    final image = XFile.fromData(
      Uint8List.fromList([7, 8, 9]),
      mimeType: 'image/jpeg',
      name: 'item.jpg',
    );

    final analysis = await service.analyze(
      image: image,
      userText: 'what is this',
      language: 'te',
    );

    expect(analysis, isNull);
  });
}
