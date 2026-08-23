import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class AskodoxUpdateInfo {
  const AskodoxUpdateInfo({required this.version, required this.buildNumber, required this.apkUrl, required this.notes, required this.mandatory});
  factory AskodoxUpdateInfo.fromJson(Map<String, dynamic> json) => AskodoxUpdateInfo(
        version: '${json['version'] ?? ''}',
        buildNumber: int.tryParse('${json['build_number'] ?? ''}') ?? 0,
        apkUrl: '${json['apk_url'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        mandatory: json['mandatory'] == true,
      );
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String notes;
  final bool mandatory;
}

class AskodoxUpdateService {
  const AskodoxUpdateService();

  static const enabled = bool.fromEnvironment('ASKODOX_ENABLE_UPDATES', defaultValue: false);
  static const currentBuildNumber = int.fromEnvironment('ASKODOX_BUILD_NUMBER', defaultValue: 1);
  static const manifestUrl = String.fromEnvironment(
    'ASKODOX_UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/podx-bot/podx/releases/download/askodox-latest/latest.json',
  );
  static const _channel = MethodChannel('com.askodox.app/update');

  Future<AskodoxUpdateInfo?> checkForUpdate() async {
    if (!enabled) return null;
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || !uri.hasScheme) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, dynamic>) return null;
      final info = AskodoxUpdateInfo.fromJson(decoded);
      return info.buildNumber > currentBuildNumber && info.apkUrl.isNotEmpty ? info : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAndInstall(AskodoxUpdateInfo info, {void Function(double progress)? onProgress}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final response = await (await client.getUrl(Uri.parse(info.apkUrl))).close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Update download failed');
      final dir = Directory('${Directory.systemTemp.path}/askodox_updates');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/askodox-${info.buildNumber}.apk');
      final sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      await _channel.invokeMethod<void>('installApk', {'path': file.path});
    } finally {
      client.close(force: true);
    }
  }
}
