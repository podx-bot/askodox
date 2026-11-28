import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import 'chat_attachment_service.dart';
import 'multimodal_capture_service.dart';

/// Camera / Photos / Video / Files -> real attachments (bytes + MIME).
/// Injectable so tests drive the same chat flow with real bytes.
abstract interface class AskodoxMediaPicker {
  /// [source]: camera | scan | photos | video | files. `scan` = the document scanner (papers: edges found, straightened,
  /// cleaned like a real scan); when it cannot open it falls back to the plain camera. Empty when cancelled.
  Future<List<ChatAttachment>> pick(String source);
}

class DeviceMediaPicker implements AskodoxMediaPicker {
  const DeviceMediaPicker();

  /// True when the last scan could not open at all (no Google Play services, web) -- the caller then uses the camera.
  static bool _scanFailed = false;

  Future<List<ChatAttachment>> _scanPages() async {
    _scanFailed = false;
    if (kIsWeb) {
      _scanFailed = true;
      return const [];
    }
    DocumentScanner? scanner;
    try {
      scanner = DocumentScanner(
          options: DocumentScannerOptions(documentFormats: {DocumentFormat.jpeg}, mode: ScannerMode.full, pageLimit: 3, isGalleryImport: true));
      final result = await scanner.scanDocument();
      final out = <ChatAttachment>[];
      final List<String>? images = result.images;
      for (final (i, path) in (images ?? const <String>[]).indexed) {
        out.add(ChatAttachment(name: 'scan-${i + 1}.jpg', bytes: await File(path).readAsBytes(), mimeType: 'image/jpeg'));
      }
      return out;
    } catch (e) {
      // Closed by the person = no pages; a real failure = use the camera instead.
      _scanFailed = !'$e'.toLowerCase().contains('cancel');
      return const [];
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}
    }
  }

  @override
  Future<List<ChatAttachment>> pick(String source) async {
    if (source == 'files') {
      final picked = await FilePicker.pickFiles();
      return [
        for (final file in picked)
          ChatAttachment(name: file.name, bytes: await file.readAsBytes()),
      ];
    }
    var way = source;
    if (way == 'scan') {
      final pages = await _scanPages();
      if (pages.isNotEmpty || !_scanFailed) return pages;
      way = 'camera';
    }
    final capture = MultimodalCaptureService();
    if (way == 'photos') {
      // Multi-select: every chosen photo becomes its own attachment.
      return [
        for (final file in await capture.chooseGalleryMulti())
          ChatAttachment(name: file.name, bytes: await file.readAsBytes(), mimeType: file.mimeType),
      ];
    }
    final file = switch (way) {
      'camera' => await capture.captureCamera(),
      'video' => await capture.chooseVideo(),
      _ => await capture.chooseGallery(),
    };
    if (file == null) return const [];
    return [ChatAttachment(name: file.name, bytes: await file.readAsBytes(), mimeType: file.mimeType)];
  }
}

final askodoxMediaPickerProvider = Provider<AskodoxMediaPicker>((ref) => const DeviceMediaPicker());
