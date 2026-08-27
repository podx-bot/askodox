import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AskodoxUpdateInfo {
  const AskodoxUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.notes,
    required this.mandatory,
  });

  factory AskodoxUpdateInfo.fromJson(Map<String, dynamic> json) =>
      AskodoxUpdateInfo(
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

class AskodoxUpdateCheckResult {
  const AskodoxUpdateCheckResult({
    required this.installedBuildNumber,
    required this.latestBuildNumber,
    required this.update,
  });

  final int installedBuildNumber;
  final int latestBuildNumber;
  final AskodoxUpdateInfo? update;

  bool get isUpToDate => update == null;
}

class AskodoxUpdateException implements Exception {
  const AskodoxUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AskodoxUpdateService {
  const AskodoxUpdateService();

  static const enabled = bool.fromEnvironment(
    'ASKODOX_ENABLE_UPDATES',
    defaultValue: false,
  );

  static const compiledBuildNumber = int.fromEnvironment(
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

  Future<int> installedBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final value = int.tryParse(info.buildNumber.trim());
      if (value != null && value > 0) return value;
    } catch (_) {}
    return compiledBuildNumber;
  }

  Future<AskodoxUpdateCheckResult> checkForUpdate() async {
    if (!enabled) {
      throw const AskodoxUpdateException(
        'In-app updates are not enabled in this build.',
      );
    }

    final installed = await installedBuildNumber();

    AskodoxUpdateInfo? releaseInfo;
    AskodoxUpdateInfo? manifestInfo;
    try {
      releaseInfo = await _readReleaseApi();
    } catch (_) {}
    try {
      manifestInfo = await _readManifest();
    } catch (_) {}

    final candidates = <AskodoxUpdateInfo>[
      if (releaseInfo != null) releaseInfo,
      if (manifestInfo != null) manifestInfo,
    ].where((info) => info.buildNumber > 0 && info.apkUrl.isNotEmpty).toList();

    if (candidates.isEmpty) {
      throw const AskodoxUpdateException(
        'Unable to verify the latest ASKODOX build. Check internet and retry.',
      );
    }

    candidates.sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
    final latest = candidates.first;

    return AskodoxUpdateCheckResult(
      installedBuildNumber: installed,
      latestBuildNumber: latest.buildNumber,
      update: latest.buildNumber > installed ? latest : null,
    );
  }

  Future<AskodoxUpdateInfo?> _readReleaseApi() async {
    final decoded = await _getJson(releaseApiUrl);
    if (decoded == null) return null;

    final body = '${decoded['body'] ?? ''}';
    final buildMatch = RegExp(r'ASKODOX_BUILD_NUMBER=(\d+)').firstMatch(body);
    final versionMatch = RegExp(r'ASKODOX_VERSION=([^\s]+)').firstMatch(body);
    var buildNumber = int.tryParse(buildMatch?.group(1) ?? '') ?? 0;

    final assets = decoded['assets'];
    if (assets is! List) return null;

    final assetUrls = <int, String>{};
    for (final raw in assets) {
      if (raw is! Map) continue;
      final asset = Map<String, dynamic>.from(raw);
      final name = '${asset['name'] ?? ''}';
      final match = RegExp(r'^askodox-(\d+)\.apk$').firstMatch(name);
      final candidate = int.tryParse(match?.group(1) ?? '') ?? 0;
      final url = '${asset['browser_download_url'] ?? ''}';
      if (candidate > 0 && url.isNotEmpty) {
        assetUrls[candidate] = url;
        if (candidate > buildNumber) buildNumber = candidate;
      }
    }

    if (buildNumber <= 0) return null;

    var apkUrl = assetUrls[buildNumber] ?? '';
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

    final releaseName = '${decoded['name'] ?? ''}';
    final releaseVersionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(releaseName);
    final version = versionMatch?.group(1) ??
        releaseVersionMatch?.group(1) ??
        '1.0.$buildNumber';

    return AskodoxUpdateInfo(
      version: version,
      buildNumber: buildNumber,
      apkUrl: apkUrl,
      notes: 'Latest ASKODOX update',
      mandatory: false,
    );
  }

  Future<AskodoxUpdateInfo?> _readManifest() async {
    final decoded = await _getJson(manifestUrl);
    if (decoded == null) return null;
    final info = AskodoxUpdateInfo.fromJson(decoded);
    return info.buildNumber > 0 && info.apkUrl.isNotEmpty ? info : null;
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

      // Android FileProvider is configured with <cache-path>. Use the app's
      // platform cache directory instead of Directory.systemTemp, which maps to
      // code_cache on some devices and cannot be shared by that FileProvider.
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory('${cacheDir.path}/askodox_updates');
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
