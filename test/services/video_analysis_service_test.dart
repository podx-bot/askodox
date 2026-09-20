import 'package:flutter_test/flutter_test.dart';
import 'package:podx/services/video_analysis_service.dart';

void main() {
  const service = VideoAnalysisService();

  test('combines user text, visual evidence and spoken evidence', () {
    final request = service.combinedRequest(
      userText: 'Help me with this item',
      visualSummary: 'A damaged blue phone is visible',
      spokenTranscript: 'It stopped charging yesterday',
    );

    expect(request, contains('Help me with this item'));
    expect(request, contains('Video visual evidence: A damaged blue phone is visible'));
    expect(request, contains('Video spoken evidence: It stopped charging yesterday'));
  });

  test('does not invent missing video evidence', () {
    expect(
      service.combinedRequest(userText: 'Please inspect this video.'),
      'Please inspect this video.',
    );
  });
}
