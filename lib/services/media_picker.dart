import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_attachment_service.dart';
import 'multimodal_capture_service.dart';

/// Camera / Photos / Video / Files -> real attachments (bytes + MIME).
/// Injectable so tests drive the same chat flow with real bytes.
abstract interface class AskodoxMediaPicker {
  /// [source]: camera | photos | video | files. Empty when cancelled.
  Future<List<ChatAttachment>> pick(String source);
}

class DeviceMediaPicker implements AskodoxMediaPicker {
  const DeviceMediaPicker();

  @override
  Future<List<ChatAttachment>> pick(String source) async {
    if (source == 'files') {
      final picked = await FilePicker.pickFiles();
      return [
        for (final file in picked)
          ChatAttachment(name: file.name, bytes: await file.readAsBytes()),
      ];
    }
    final capture = MultimodalCaptureService();
    final file = switch (source) {
      'camera' => await capture.captureCamera(),
      'video' => await capture.chooseVideo(),
      _ => await capture.chooseGallery(),
    };
    if (file == null) return const [];
    return [ChatAttachment(name: file.name, bytes: await file.readAsBytes(), mimeType: file.mimeType)];
  }
}

final askodoxMediaPickerProvider = Provider<AskodoxMediaPicker>((ref) => const DeviceMediaPicker());
