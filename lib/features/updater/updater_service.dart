import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kGithubRepo = 'AMX72/pixellnet-client';
const _kPrefAutoUpdate = 'pixellnet.updater.auto_update_enabled';
const _kPrefLastCheck = 'pixellnet.updater.last_check';
const _kCheckIntervalMs = 4 * 60 * 60 * 1000; // 4 часа

// ── Providers ─────────────────────────────────────────────────────────────────

final autoUpdateEnabledProvider =
    StateNotifierProvider<AutoUpdateNotifier, bool>((ref) {
  return AutoUpdateNotifier();
});

class AutoUpdateNotifier extends StateNotifier<bool> {
  AutoUpdateNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kPrefAutoUpdate) ?? true;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefAutoUpdate, value);
  }
}

// ── Model ──────────────────────────────────────────────────────────────────────

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class UpdaterService {
  UpdaterService._();
  static final instance = UpdaterService._();

  /// Возвращает [UpdateInfo] если доступна новая версия, иначе null.
  /// Throttled: пропускает сетевой вызов если проверка была менее 4 часов назад.
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!Platform.isAndroid) return null;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_kPrefLastCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && (now - lastCheck) < _kCheckIntervalMs) return null;

    try {
      final response = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_kGithubRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      await prefs.setInt(_kPrefLastCheck, now);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String).replaceFirst('v', '');
      final body = data['body'] as String? ?? '';

      final assets = data['assets'] as List<dynamic>;
      String? apkUrl;
      for (final asset in assets) {
        final name = asset['name'] as String;
        if (name.contains('arm64') && name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String;
          break;
        }
      }
      apkUrl ??= assets
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (a) => (a['name'] as String).endsWith('.apk'),
            orElse: () => {},
          )['browser_download_url'] as String?;

      if (apkUrl == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final current = Version.parse(packageInfo.version.split('+').first);
      final latest = Version.parse(tagName);

      if (latest > current) {
        return UpdateInfo(
          version: tagName,
          downloadUrl: apkUrl,
          changelog: body,
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[UpdaterService] checkForUpdate error: $e');
      return null;
    }
  }

  /// Скачивает APK и запускает Android installer.
  /// Кидает Exception если download / open провалились — UI показывает ошибку.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    // Use app-specific external cache directory — не требует MANAGE_EXTERNAL_STORAGE.
    // FileProvider (см. AndroidManifest) уже знает про external-cache-path.
    final dir = await getExternalStorageDirectory();
    if (dir == null) {
      throw Exception('Не удалось получить директорию для загрузки');
    }
    final downloadDir = Directory('${dir.path}/updates');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    final file = File('${downloadDir.path}/pixellnet-${info.version}.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request).timeout(
            const Duration(seconds: 60),
            onTimeout: () =>
                throw Exception('Таймаут при подключении к серверу обновлений'),
          );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} от сервера обновлений');
      }
      final total = response.contentLength ?? 0;
      int received = 0;

      final sink = file.openWrite();
      await response.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        return chunk;
      }).pipe(sink);
      await sink.close();
    } finally {
      client.close();
    }

    final result = await OpenFile.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Не удалось открыть установщик: ${result.message}');
    }
  }
}
