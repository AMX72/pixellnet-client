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

/// v0.1.31: OEM info для guided permission screen.
/// Возвращает {manufacturer, brand, model, sdk} — все lowercase.
/// Пустой Map если не Android или ошибка.
Future<Map<String, dynamic>> _oemInfo() async {
  if (!Platform.isAndroid) return const {};
  try {
    final json =
        await _platformChannel.invokeMethod<String>('oem_info') ?? '{}';
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

/// v0.1.31: Классифицирует устройство юзера по OEM для guided-подсказок.
/// Публичное API — виджет UpdateDialog вызывает перед показом install-диалога.
enum OemFamily { xiaomi, huawei, oppo, vivo, samsung, other }

Future<OemFamily> detectOemFamily() async {
  final info = await _oemInfo();
  final m = (info['manufacturer'] as String? ?? '').toLowerCase();
  final b = (info['brand'] as String? ?? '').toLowerCase();
  final tokens = '$m|$b';
  if (tokens.contains('xiaomi') ||
      tokens.contains('redmi') ||
      tokens.contains('poco')) return OemFamily.xiaomi;
  if (tokens.contains('huawei') || tokens.contains('honor')) {
    return OemFamily.huawei;
  }
  if (tokens.contains('oppo') || tokens.contains('realme')) {
    return OemFamily.oppo;
  }
  if (tokens.contains('vivo') || tokens.contains('iqoo')) return OemFamily.vivo;
  if (tokens.contains('samsung')) return OemFamily.samsung;
  return OemFamily.other;
}

/// v0.1.33: диагностика "нет вышки" vs "VPN сломан".
enum NetworkState {
  ok, // сеть работает нормально
  noCellSignal, // оператор выключил вышку (СВО в районе моста/нефтебазы)
  cellSignalButNoData, // вышка есть, packet не идёт (VPN сломан или DPI режет)
  wifiOnly, // только Wi-Fi
  unknown, // permission missing или API error
}

class NetworkDiagnostics {
  const NetworkDiagnostics({
    required this.state,
    required this.hasWifi,
    required this.hasCellular,
  });
  final NetworkState state;
  final bool hasWifi;
  final bool hasCellular;
}

Future<NetworkDiagnostics> collectNetworkDiagnostics() async {
  if (!Platform.isAndroid) {
    return const NetworkDiagnostics(
        state: NetworkState.unknown, hasWifi: false, hasCellular: false);
  }
  try {
    final json = await _platformChannel
            .invokeMethod<String>('network_diagnostics') ??
        '{}';
    final m = jsonDecode(json) as Map<String, dynamic>;
    final s = m['state'] as String? ?? 'unknown';
    return NetworkDiagnostics(
      state: switch (s) {
        'ok' => NetworkState.ok,
        'no_cell_signal' => NetworkState.noCellSignal,
        'cell_signal_but_no_data' => NetworkState.cellSignalButNoData,
        'wifi_only' => NetworkState.wifiOnly,
        _ => NetworkState.unknown,
      },
      hasWifi: m['has_wifi'] as bool? ?? false,
      hasCellular: m['has_cellular'] as bool? ?? false,
    );
  } catch (_) {
    return const NetworkDiagnostics(
        state: NetworkState.unknown, hasWifi: false, hasCellular: false);
  }
}

/// v0.1.31: notification прогресс-бар при download. Если permission не выдан
/// или fail — silent.
Future<void> _notifStart(String version) async {
  if (!Platform.isAndroid) return;
  try {
    await _platformChannel
        .invokeMethod('download_progress_start', {'version': version});
  } catch (_) {}
}

Future<void> _notifUpdate(String version, int percent) async {
  if (!Platform.isAndroid) return;
  try {
    await _platformChannel.invokeMethod(
        'download_progress_update', {'version': version, 'percent': percent});
  } catch (_) {}
}

Future<void> _notifDone() async {
  if (!Platform.isAndroid) return;
  try {
    await _platformChannel.invokeMethod('download_progress_done');
  } catch (_) {}
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

  /// v0.1.30: fallback-зеркала. Пробуем в порядке: primary → mirrors по очереди.
  /// РФ-юзеры на CF/GH ловят ТСПУ throttle 16 KB — mirror в РФ-DC даёт full speed.
  final List<String> mirrors;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    this.mirrors = const [],
  });

  /// Все URL: primary + mirrors без дубликатов, порядок сохраняется.
  List<String> get allSources {
    final seen = <String>{};
    return [downloadUrl, ...mirrors].where(seen.add).toList();
  }
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
    // v0.1.16: поддержка Windows (кроме Android) — качаем portable zip
    if (!Platform.isAndroid && !Platform.isWindows) return null;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_kPrefLastCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && (now - lastCheck) < _kCheckIntervalMs) return null;

    // v0.1.5: rollout manifest временно отключён — /updates.json пока отдаёт
    // mirror URL который 404. Идём напрямую на GH releases.
    // TODO: включить обратно когда pixellnet.com/download/ endpoint починен.
    // final rolloutInfo = await _checkRolloutManifest();
    // if (rolloutInfo != null) {
    //   await prefs.setInt(_kPrefLastCheck, now);
    //   return rolloutInfo;
    // }

    try {
      // v0.1.18: /releases/latest возвращает ТОЛЬКО что запушенный тег,
      // build которого может ещё не завершиться (нет assets). Итерируемся
      // по последним 10 releases и берём первый где есть подходящий asset —
      // так пропускаем незавершённые CI-релизы и находим последний рабочий.
      final response = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_kGithubRepo/releases?per_page=10'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      await prefs.setInt(_kPrefLastCheck, now);

      final releases = jsonDecode(response.body) as List<dynamic>;
      String? tagName;
      String? body;
      String? downloadUrl;

      for (final release in releases) {
        final r = release as Map<String, dynamic>;
        final assets = r['assets'] as List<dynamic>;
        if (assets.isEmpty) continue; // build ещё не завершился

        String? url;
        if (Platform.isWindows) {
          for (final asset in assets) {
            final name = asset['name'] as String;
            if (name.contains('windows') && name.endsWith('.zip')) {
              url = asset['browser_download_url'] as String;
              break;
            }
          }
        } else {
          for (final asset in assets) {
            final name = asset['name'] as String;
            if (name.contains('arm64') && name.endsWith('.apk')) {
              url = asset['browser_download_url'] as String;
              break;
            }
          }
        }
        if (url != null) {
          tagName = (r['tag_name'] as String).replaceFirst('v', '');
          body = r['body'] as String? ?? '';
          downloadUrl = url;
          break;
        }
      }

      if (downloadUrl == null || tagName == null) return null;
      final apkUrl = downloadUrl;

      final packageInfo = await PackageInfo.fromPlatform();
      final current = Version.parse(packageInfo.version.split('+').first);
      final latest = Version.parse(tagName);

      if (latest > current) {
        // v0.1.30/31: mirror-цепочка для обхода ТСПУ throttle 16 KB на CF/GH.
        //   primary: GH releases (upstream, всегда актуальный)
        //   #1: pixellnet.com/latest.apk (Netcup через CF proxy)
        //   #2: http://com.pixell.ru/pixellnet-<ver>-arm64.apk (Eurobyte MSK
        //       shared, HTTP т.к. self-signed cert; cleartext разрешён в
        //       network_security_config для этого домена)
        // При обрыве на mirror #N — cycle стирает частичный файл (разные
        // ETag = склеенный APK будет битым).
        final ghMirrors = Platform.isWindows
            ? <String>[] // Windows пока без mirror — zip на pixellnet.com/latest.zip нет
            : <String>[
                'https://pixellnet.com/latest.apk',
                'http://com.pixell.ru/pixellnet-$tagName-arm64.apk',
              ];
        return UpdateInfo(
          version: tagName,
          downloadUrl: apkUrl,
          changelog: body ?? '',
          mirrors: ghMirrors,
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
      // v0.1.30: apk_url_mirrors — fallback список для РФ (обход ТСПУ throttle
      // 16 KB на TCP → CF/Fastly). Порядок значим: primary = самый быстрый.
      final mirrors = (data['apk_url_mirrors'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];

      final packageInfo = await PackageInfo.fromPlatform();
      final current = Version.parse(packageInfo.version.split('+').first);
      final latest = Version.parse(version);

      if (latest > current) {
        return UpdateInfo(
          version: version,
          downloadUrl: apkUrl,
          changelog: changelog,
          mirrors: mirrors,
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
    if (Platform.isWindows) {
      return _downloadAndInstallWindows(info, onProgress: onProgress);
    }
    // v0.1.30: fallback dir. getExternalStorageDirectory() может вернуть null
    // на нестандартных Android (некоторые Xiaomi/HyperOS без external storage
    // разрешения). Documents dir всегда доступен + покрыт FileProvider (see
    // file_paths.xml files-path).
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/updates');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    final file = File('${downloadDir.path}/pixellnet-${info.version}.apk');

    // v0.1.15: чистим старые APK — не копим архив на диске.
    // Всё pixellnet-*.apk кроме файла текущей версии удаляется.
    try {
      await for (final entity in downloadDir.list()) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('pixellnet-') && name.endsWith('.apk') && entity.path != file.path) {
            try {
              await entity.delete();
              if (kDebugMode) debugPrint('[Updater] cleaned old APK: $name');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Updater] cleanup failed: $e');
    }

    // v0.1.30: НЕ удаляем существующий файл текущей версии — сохраняем для
    // resume между сессиями (если Android убил приложение OOM во время
    // download 120 МБ, при повторе Range докачивает без обрыва в начало).
    // Финальная проверка size ниже отловит битый файл.

    // Проверяем runtime permission REQUEST_INSTALL_PACKAGES (Android 8+).
    // Если нет — фейлимся заранее, не скачивая 119 МБ впустую.
    if (!await _canRequestPackageInstalls()) {
      throw InstallPermissionDeniedException();
    }

    // v0.1.30: multi-mirror loop. Перебираем primary + mirrors по очереди,
    // 3 retry на каждый mirror. При смене mirror стираем частичный файл
    // (разные ETag могут дать битый склеенный APK).
    // v0.1.31: notification-based progress — юзер может свернуть приложение,
    // download продолжается в фоне (notification удерживает процесс).
    final urls = info.allSources;
    Exception? lastError;
    int totalSize = 0;
    int lastNotifiedPercent = -1;
    void wrappedProgress(double p) {
      onProgress?.call(p);
      final percent = (p * 100).toInt();
      if (percent != lastNotifiedPercent) {
        lastNotifiedPercent = percent;
        _notifUpdate(info.version, percent);
      }
    }

    await _notifStart(info.version);
    try {
      for (int mirrorIdx = 0; mirrorIdx < urls.length; mirrorIdx++) {
        final url = urls[mirrorIdx];
        if (kDebugMode) debugPrint('[Updater] trying mirror #$mirrorIdx: $url');
        try {
          totalSize = await _downloadWithResume(
            url: url,
            file: file,
            onProgress: wrappedProgress,
          );
          lastError = null;
          break; // success
        } on Exception catch (e) {
          lastError = e;
          if (kDebugMode) debugPrint('[Updater] mirror #$mirrorIdx failed: $e');
          // Перед переключением на след. mirror стираем частичный файл —
          // разные origin могут отдавать байты с разным ETag, склейка = битый APK.
          if (mirrorIdx < urls.length - 1) {
            if (await file.exists()) await file.delete();
          }
        }
      }
    } finally {
      await _notifDone();
    }
    if (lastError != null) throw lastError;

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

    // v0.1.26: метка установки для post-update banner на Home.
    // Android install через PackageInstaller — юзер подтверждает вручную,
    // сохраняем ДО запуска (если откажется — сотрёт следующая проверка).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('update_last_installed_at', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('update_last_installed_version', info.version);

    final result = await OpenFile.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Не удалось открыть установщик: ${result.message}');
    }
  }

  /// v0.1.30: скачивает [url] в [file] с Range-resume и 3 retry.
  /// Возвращает `totalSize` от сервера (Content-Length при первом GET).
  /// Кидает Exception если 3 попытки провалились — caller ловит и пробует
  /// следующий mirror.
  ///
  /// Начинает с текущего размера файла (если файл был частично скачан
  /// в предыдущей сессии — докачивает через `Range: bytes=X-`).
  Future<int> _downloadWithResume({
    required String url,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    int totalSize = 0;
    int received = await file.exists() ? await file.length() : 0;

    for (int attempt = 0; attempt < 3; attempt++) {
      final client = http.Client();
      try {
        final headers = <String, String>{};
        if (received > 0) {
          headers['Range'] = 'bytes=$received-';
        }
        final request = http.Request('GET', Uri.parse(url))
          ..headers.addAll(headers);
        // v0.1.30: 15s handshake timeout (было 30s) — быстрее переключение
        // на следующий mirror при ТСПУ throttle.
        final response = await client.send(request).timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw Exception('Таймаут подключения к серверу обновлений'),
            );

        if (received == 0) {
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }
          totalSize = response.contentLength ?? 0;
        } else {
          if (response.statusCode != 206) {
            // Server не поддерживает Range → перекачиваем с нуля
            received = 0;
            if (await file.exists()) await file.delete();
            continue;
          }
          // 206 Partial — обновить totalSize из Content-Range. v0.1.32:
          // ВСЕГДА пересчитываем — mirror #2 может отдать другой файл
          // с другим размером; если оставим старый totalSize от mirror #1,
          // financial check в конце ошибочно скажет «файл повреждён».
          final cr = response.headers['content-range'];
          if (cr != null) {
            final m = RegExp(r'/(\d+)$').firstMatch(cr);
            if (m != null) {
              final crTotal = int.tryParse(m.group(1) ?? '') ?? 0;
              if (crTotal > 0) totalSize = crTotal;
            }
          }
        }

        final sink =
            file.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
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
        // v0.1.32: если сервер прислал больше чем totalSize (mirror
        // inconsistency, повторный chunk после Range, CDN edge с другим
        // файлом) — truncate до ожидаемого размера. APK — это ZIP, лишние
        // байты в хвосте это не «повредят» файл, но installer их не любит.
        if (totalSize > 0 && actual > totalSize) {
          final raf = await file.open(mode: FileMode.append);
          try {
            await raf.truncate(totalSize);
          } finally {
            await raf.close();
          }
        }
        return totalSize; // success
      } on Exception {
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
    return totalSize;
  }

  /// Windows: zero-config in-app update без открытия GitHub.
  ///
  /// 1. Скачивает release zip в %TEMP%\pixellnet-update\
  /// 2. Распаковывает через PowerShell Expand-Archive (нативно на Windows 10+)
  /// 3. Генерит updater.bat который ждёт закрытия pixellnet.exe → xcopy /Y
  ///    новые файлы поверх текущих → запускает pixellnet.exe → self-delete
  /// 4. Detached Process.start(updater.bat), затем exit(0) — Flutter закрывается
  /// 5. Bat пёстрит: 3 сек ожидания, копирование, restart
  Future<void> _downloadAndInstallWindows(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final tempBase = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? r'C:\Windows\Temp';
    final workDir = Directory('$tempBase\\pixellnet-update');
    if (await workDir.exists()) {
      try {
        await workDir.delete(recursive: true);
      } catch (_) {}
    }
    await workDir.create(recursive: true);

    final zipFile = File('${workDir.path}\\update.zip');
    final extractDir = Directory('${workDir.path}\\extracted');

    // v0.1.30: multi-mirror + resume через общий _downloadWithResume.
    final urls = info.allSources;
    Exception? lastError;
    for (int mirrorIdx = 0; mirrorIdx < urls.length; mirrorIdx++) {
      final url = urls[mirrorIdx];
      if (kDebugMode) debugPrint('[Updater/Win] trying mirror #$mirrorIdx: $url');
      try {
        await _downloadWithResume(
          url: url,
          file: zipFile,
          onProgress: onProgress,
        );
        lastError = null;
        break;
      } on Exception catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('[Updater/Win] mirror #$mirrorIdx failed: $e');
        if (mirrorIdx < urls.length - 1) {
          if (await zipFile.exists()) await zipFile.delete();
        }
      }
    }
    if (lastError != null) throw lastError;

    final actualSize = await zipFile.length();
    if (actualSize < 5 * 1024 * 1024) {
      throw Exception('Скачанный файл слишком мал ($actualSize байт). Проверь интернет.');
    }

    // Распаковка через PowerShell (нативная на Windows 10+, без зависимостей)
    final expand = await Process.run(
      'powershell.exe',
      [
        '-NoProfile', '-NonInteractive', '-Command',
        "Expand-Archive -Path '${zipFile.path}' -DestinationPath '${extractDir.path}' -Force"
      ],
      runInShell: false,
    );
    if (expand.exitCode != 0) {
      throw Exception('Не удалось распаковать zip: ${expand.stderr}');
    }

    // Определить директорию установки (где лежит текущий .exe)
    final currentExe = Platform.resolvedExecutable;
    final installDir = File(currentExe).parent.path;
    final exeName = currentExe.split('\\').last;

    // Найти папку с распакованными файлами — Flutter zip обычно содержит
    // подпапку Release/ или напрямую .exe в корне extracted/. Ищем .exe.
    String sourceRoot = extractDir.path;
    final rootEntries = await extractDir.list().toList();
    if (rootEntries.length == 1 && rootEntries.first is Directory) {
      sourceRoot = rootEntries.first.path;
    }

    // Пишем updater.bat
    final batFile = File('${workDir.path}\\updater.bat');
    // Не убиваем сами процесс — appExit() ниже сделает это.
    // Bat ждёт 3 сек чтобы файлы разлочились, потом копирует и запускает.
    final batContent = '''@echo off
chcp 65001 > nul
timeout /T 3 /NOBREAK > nul
xcopy /Y /E /Q /I "$sourceRoot\\*" "$installDir\\" > nul
if errorlevel 1 (
  echo Copy failed, aborting.
  pause
  exit /b 1
)
start "" "$installDir\\$exeName"
timeout /T 2 /NOBREAK > nul
rmdir /S /Q "${workDir.path}" > nul 2>&1
(goto) 2>nul & del "%~f0"
''';
    await batFile.writeAsString(batContent);

    // v0.1.26: сохраняем метку установки для post-update banner на Home
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('update_last_installed_at', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('update_last_installed_version', info.version);

    // Запускаем detached bat и выходим из приложения
    await Process.start(
      'cmd.exe',
      ['/C', 'start', '""', '/MIN', batFile.path],
      runInShell: false,
      mode: ProcessStartMode.detached,
    );

    // Дать Windows время подхватить detached процесс перед exit
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}
