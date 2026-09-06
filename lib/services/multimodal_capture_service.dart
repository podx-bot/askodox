import 'package:image_picker/image_picker.dart';

/// Shared device-media capture path for ASKODOX multimodal requests.
///
/// Keeps camera/gallery acquisition separate from reasoning so every captured
/// image can be sent through the same Vision API -> ASKODOX deal/OASAT flow.
class MultimodalCaptureService {
  MultimodalCaptureService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<XFile?> captureCamera() => _pick(ImageSource.camera);

  Future<XFile?> chooseGallery() => _pick(ImageSource.gallery);

  Future<XFile?> _pick(ImageSource source) async {
    try {
      return await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
    } catch (_) {
      return null;
    }
  }
}
