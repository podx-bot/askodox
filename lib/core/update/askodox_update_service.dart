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

  static const enabled = bool.fromEnvironment(
    'ASKODOX_ENABLE_UPDATES',
    defaultValue: false,
  );
  static const currentBuildNumber = int.fromEnvironment(
    'ASKODOX_BUILD_NUMBER',
    defaultValue: 1,
  );
  static const releaseApiUrl = String.fromEnvironment(
    'ASKODOX_UPDATE_RELEASE_API_URL',
    defaultValue:
        'https://api.github.com/repos/podx-bot/podx/releases/tags/askodox-latest',
  );
  static const manifestUrl = String.fromEnvironment(
    'ASKODOX_UPDATE_MANIFEST_URL',
    defaultValue:
        'https://github.com/podx-bot/podx/releases/download/askodox-latest/latest.json',
  );
  static const _channel = MethodChannel('com.askodox.app/update');

  Future<AskodoxUpdateInfo?> checkForUpdate() async {
    if (!enabled) return null;

    // Primary path: GitHub's release API. The release body carries the build
    // number and the APK is published with a build-specific filename, so this
    // path never depends on an overwritten/cached latest.json or APK asset.
    final releaseInfo = await _checkReleaseApi();
    if (releaseInfo != null) return releaseInfo;

    // Compatibility fallback for older channels/environments.
    return _checkManifest();
  }

  Future<AskodoxUpdateInfo?> _checkReleaseApi() async {
    final decoded = await _getJson(releaseApiUrl);
    if (decoded == null) return null;

    final body = '${decoded['body'] ?? ''}';
    final buildMatch = RegExp(r'ASKODOX_BUILD_NUMBER=(\d+)').firstMatch(body);
    final versionMatch = RegExp(r'ASKODOX_VERSION=([^\s]+)').firstMatch(body);
    final buildNumber = int.tryParse(buildMatch?.group(1) ?? '') ?? 0;
    if (buildNumber <= currentBuildNumber) return null;

    final assets = decoded['assets'];
    if (assets is! List) return null;

    String apkUrl = '';
    final expectedName = 'askodox-$buildNumber.apk';
    for (final raw in assets) {
      if (raw is! Map) continue;
      final asset = Map<String, dynamic>.from(raw);
      if ('${asset['name'] ?? ''}' == expectedName) {
        apkUrl = '${asset['browser_download_url'] ?? ''}';
        break;
      }
    }
    if (apkUrl.isEmpty) {
      for (final raw in assets) {
        if (raw is! Map) continue;
        final asset = Map<String, dynamic>.from(raw);
        if ('${asset['name'] ?? ''}' == 'askodox-latest.apk') {
          apkUrl = '${asset['browser_download_url'] ?? ''}';
          break;
        }
      }
    }
    if (apkUrl.isEmpty) return null;

    return AskodoxUpdateInfo(
      version: versionMatch?.group(1) ?? '1.0.$buildNumber',
      buildNumber: buildNumber,
      apkUrl: apkUrl,
      notes: 'Latest ASKODOX update',
      mandatory: false,
    );
  }

  Future<AskodoxUpdateInfo?> _checkManifest() async {
    final decoded = await _getJson(manifestUrl);
    if (decoded == null) return null;
    final info = AskodoxUpdateInfo.fromJson(decoded);
    return info.buildNumber > currentBuildNumber && info.apkUrl.isNotEmpty
        ? info
        : null;
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final baseUri = Uri.tryParse(url);
    if (baseUri == null || !baseUri.hasScheme) return null;

    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        '_askodox_check': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, max-age=0',
      );
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, max-age=0',
      );
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Update download failed');
      }
      final dir = Directory('${Directory.systemTemp.path}/askodox_updates');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/askodox-${info.buildNumber}.apk');
      final sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      await _channel.invokeMethod<void>('installApk', {'path': file.path});
    } finally {
      client.close(force: true);
    }
  }
}
