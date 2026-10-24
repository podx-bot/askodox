import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _device = MethodChannel('com.askodox.app/device');

/// Writes [bytes] to the app cache (the only folder the share provider exposes) and
/// opens the Android share sheet; the person chooses where it goes. Returns false on
/// an app build without file sharing.
Future<bool> askodoxSharePdf(Uint8List bytes, {required String name, String folder = 'reports'}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/$folder');
  await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/${safe.isEmpty ? 'report' : safe}.pdf');
  await file.writeAsBytes(bytes, flush: true);
  try {
    return await _device.invokeMethod<bool>('shareFile', <String, Object?>{
          'path': file.path,
          'mime': 'application/pdf',
          'title': name,
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
