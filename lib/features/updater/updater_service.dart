import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when Android REQUEST_INSTALL_PACKAGES permission is missing.
/// UI catches this specifically to show «Открыть настройки» button.
class InstallPermissionDeniedException implements Exception {
  @override
  String toString() =>
      'Разреши установку приложений из этого источника в настройках Android';
}

const _platformChannel = MethodChannel('com.hiddify.app/platform');

Future<bool> _canRequestPackageInstalls() async {
  if (!Platform.isAndroid) return true;
  try {
    return (await _platformChannel
            .invokeMethod<bool>('can_request_package_installs')) ??
        false;
  } catch (_) {
    return false;
  }
}

Future<void> openInstallUnknownAppsSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await _platformChannel.invokeMethod('open_install_unknown_apps_settings');
  } catch (e) {
    if (kDebugMode) debugPrint('[Updater] openSettings failed: $e');
  }
}

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
  ///
  /// v0.0.37: сначала пробует pixellnet.com/updates.json (superadmin rollout
  /// channel), fallback на GitHub API если rollout ещё не опубликован.
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!Platform.isAndroid) return null;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_kPrefLastCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && (now - lastCheck) < _kCheckIntervalMs) return null;

    // v0.0.37: Try pixellnet.com/updates.json first (rollout channel).
    final rolloutInfo = await _checkRolloutManifest();
    if (rolloutInfo != null) {
      await prefs.setInt(_kPrefLastCheck, now);
      return rolloutInfo;
    }

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

      // v0.0.33: заменяем GitHub URL на pixellnet.com/download mirror.
      // Причина: Yota/РФ операторы обрывают download release-assets.githubusercontent.com
      // с SocketException errno 103. Наш mirror через Cloudflare + Netcup стабильнее.
      final mirrorUrl =
          'https://pixellnet.com/download/pixellnet-$tagName-arm64.apk';

      final packageInfo = await PackageInfo.fromPlatform();
      final current = Version.parse(packageInfo.version.split('+').first);
      final latest = Version.parse(tagName);

      if (latest > current) {
        return UpdateInfo(
          version: tagName,
          downloadUrl: mirrorUrl,
          changelog: body,
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[UpdaterService] checkForUpdate error: $e');
      return null;
    }
  }

  /// v0.0.37: rollout manifest check — superadmin promotes version via
  /// /api/admin/rollout/apply, users pull latest via /updates.json.
  /// Returns UpdateInfo if newer than current, null otherwise (fallback to GH).
  Future<UpdateInfo?> _checkRolloutManifest() async {
    try {
      final response = await http
          .get(Uri.parse('https://pixellnet.com/updates.json?channel=stable'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final version = (data['version'] as String).replaceFirst('v', '');
      final apkUrl = data['apk_url'] as String;
      final changelog = data['changelog'] as String? ?? '';

      final packageInfo = await PackageInfo.fromPlatform();
      final current = Version.parse(packageInfo.version.split('+').first);
      final latest = Version.parse(version);

      if (latest > current) {
        return UpdateInfo(
          version: version,
          downloadUrl: apkUrl,
          changelog: changelog,
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Updater] rollout manifest check failed: $e');
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

    // Проверяем runtime permission REQUEST_INSTALL_PACKAGES (Android 8+).
    // Если нет — фейлимся заранее, не скачивая 119 МБ впустую.
    if (!await _canRequestPackageInstalls()) {
      throw InstallPermissionDeniedException();
    }

    // v0.0.33: retry с Range headers если Yota/CGNAT рвёт stream.
    // errno 103 «Software caused connection abort» = TCP RST от middlebox.
    int totalSize = 0;
    int received = 0;
    for (int attempt = 0; attempt < 3; attempt++) {
      final client = http.Client();
      try {
        final headers = <String, String>{};
        if (received > 0) {
          headers['Range'] = 'bytes=$received-';
        }
        final request = http.Request('GET', Uri.parse(info.downloadUrl))
          ..headers.addAll(headers);
        final response = await client.send(request).timeout(
              const Duration(seconds: 30),
              onTimeout: () =>
                  throw Exception('Таймаут подключения к серверу обновлений'),
            );

        if (received == 0) {
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode} от сервера');
          }
          totalSize = response.contentLength ?? 0;
        } else {
          if (response.statusCode != 206) {
            // Server не поддерживает Range → перекачиваем с нуля
            received = 0;
            if (await file.exists()) await file.delete();
            continue;
          }
        }

        final sink = file.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
        try {
          await response.stream.map((chunk) {
            received += chunk.length;
            if (totalSize > 0) onProgress?.call(received / totalSize);
            return chunk;
          }).pipe(sink);
        } finally {
          await sink.close();
        }

        // Verify size — если не докачали, следующая итерация докачает через Range.
        final actual = await file.length();
        if (totalSize > 0 && actual < totalSize) {
          received = actual;
          continue;
        }
        break; // success
      } on Exception catch (e) {
        // Обрыв стрима — сохраняем позицию, retry с Range.
        received = await file.exists() ? await file.length() : 0;
        if (attempt == 2) {
          rethrow;
        }
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        client.close();
      }
    }

    // Финальная проверка размера — если APK truncated, install даст
    // «Приложение не установлено, конфликтует с другим пакетом».
    final actualSize = await file.length();
    if (totalSize > 0 && actualSize != totalSize) {
      await file.delete();
      throw Exception('Скачано $actualSize байт из $totalSize. Файл повреждён, попробуй снова.');
    }
    if (actualSize < 10 * 1024 * 1024) {
      // < 10 МБ = точно не наш APK (~120 МБ)
      await file.delete();
      throw Exception('Скачанный файл слишком мал ($actualSize байт). Проверь интернет.');
    }

    final result = await OpenFile.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Не удалось открыть установщик: ${result.message}');
    }
  }
}
