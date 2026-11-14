import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _device = MethodChannel('com.askodox.app/device');

/// Writes a PNG to the app cache (the folder the share provider exposes) and
/// opens the Android share sheet. Returns false on a build without sharing.
/// [text] goes with the picture (a caption with a link, where the target app takes it).
Future<bool> askodoxShareImage(Uint8List bytes, {String name = 'askodox-photo', String? text}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/images');
  await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/${safe.isEmpty ? 'askodox-photo' : safe}.png');
  await file.writeAsBytes(bytes, flush: true);
  try {
    return await _device.invokeMethod<bool>('shareFile', <String, Object?>{
          'path': file.path,
          'mime': 'image/png',
          'title': name,
          if (text != null) 'text': text,
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Saves a picture into the phone's gallery (Pictures/ASKODOX). Returns false when the phone
/// cannot (Android 9 or older, or a build without the method) -- then offer [askodoxShareImage].
Future<bool> askodoxSaveImageToGallery(Uint8List bytes, {String name = 'askodox-photo', String mime = 'image/png'}) async {
  // First the bytes straight into the gallery (no file path); older builds without it use the file route below.
  final cleanName = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  try {
    final saved = await _device.invokeMethod<bool>('saveImageBytes', <String, Object?>{
      'bytes': bytes,
      'mime': mime,
      'name': '${cleanName.isEmpty ? 'askodox-photo' : cleanName}-${DateTime.now().millisecondsSinceEpoch}'
          '.${mime == 'image/jpeg' ? 'jpg' : 'png'}',
    });
    if (saved == true) return true;
  } on MissingPluginException {
    // an older build: fall through to the file route
  } on PlatformException {
    // fall through to the file route
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}/images');
  await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final ext = mime == 'image/jpeg' ? 'jpg' : 'png';
  final file = File('${dir.path}/${safe.isEmpty ? 'askodox-photo' : safe}.$ext');
  await file.writeAsBytes(bytes, flush: true);
  try {
    return await _device.invokeMethod<bool>('saveImageToGallery', <String, Object?>{
          'path': file.path,
          'mime': mime,
          'name': '${safe.isEmpty ? 'askodox-photo' : safe}.$ext',
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
