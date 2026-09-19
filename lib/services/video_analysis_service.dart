/// Shared evidence contract for short-video requests.
///
/// A video may contribute visual evidence and spoken evidence independently.
/// This helper combines only evidence that was actually produced; it never
/// invents a description when a frame or transcript is unavailable.
class VideoAnalysisService {
  const VideoAnalysisService();

  String combinedRequest({
    required String userText,
    String? visualSummary,
    String? spokenTranscript,
  }) {
    final parts = <String>[userText.trim()];
    final visual = visualSummary?.trim();
    final spoken = spokenTranscript?.trim();
    if (visual != null && visual.isNotEmpty) {
      parts.add('Video visual evidence: $visual');
    }
    if (spoken != null && spoken.isNotEmpty) {
      parts.add('Video spoken evidence: $spoken');
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }
}
