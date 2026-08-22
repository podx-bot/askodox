import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class AskodoxUpdateInfo {
  const AskodoxUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.notes,
    required this.mandatory,
  });

  factory AskodoxUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AskodoxUpdateInfo(
      version: (json['version'] ?? '').toString(),
      buildNumber: int.tryParse((json['build_number'] ?? '').toString()) ?? 0,
      apkUrl: (json['apk_url'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      mandatory: json['mandatory'] == true,
    );
  }

  final String version;
  final int buildNumber;
  final String apkUrl;
  final String notes;
  final bool mandatory;
}

class AskodoxUpdateService {
  const AskodoxUpdateService();

  static const enabled = bool.fromEnvironment(
    'ASKODOX_ENABLE_UPDATES',
    defaultValue: false,
  );
  static const currentBuildNumber = int.fromEnvironment(
    'ASKODOX_BUILD_NUMBER',
    defaultValue: 1,
  );
  static const manifestUrl = String.fromEnvironment(
    'ASKODOX_UPDATE_MANIFEST_URL',
    defaultValue:
        'https://github.com/podx-bot/podx/releases/download/askodox-latest/latest.json',
  );

  static const MethodChannel _channel = MethodChannel('com.askodox.app/update');

  Future<AskodoxUpdateInfo?> checkForUpdate() async {
    if (!enabled) return null;

    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final info = AskodoxUpdateInfo.fromJson(decoded);
      if (info.buildNumber <= currentBuildNumber || info.apkUrl.isEmpty) {
        return null;
      }
      return info;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAndInstall(
    AskodoxUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse(info.apkUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('APK download failed with HTTP ${response.statusCode}.');
      }

      final directory = Directory('${Directory.systemTemp.path}/askodox_updates');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File('${directory.path}/askodox-update-${info.buildNumber}.apk');
      final sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      if (!await file.exists() || await file.length() == 0) {
        throw const FileSystemException('Downloaded APK is empty.');
      }

      await _channel.invokeMethod<void>('installApk', {'path': file.path});
    } finally {
      client.close(force: true);
    }
  }
}
