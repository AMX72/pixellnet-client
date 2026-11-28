import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zero-config trial: при первом запуске автоматически создаёт trial-подписку
/// на 7 дней через `POST /api/trial` (pixellnet-api). Юзер не вводит ссылку.
///
/// Backend: `https://pixellnet.com/api/trial`. Сервер ищет пробный период по
/// `install_id` (случайный UUID, создаётся один раз при первом обращении и лежит
/// в SharedPreferences): повторный вызов с тем же `install_id` возвращает
/// существующую подписку. Защиту от повторных пробных периодов на одном
/// устройстве ведёт по `hw_id` (хеш Android ID / machine GUID Windows).
///
/// Поле `device_id` оставлено только для совместимости со старым сервером:
/// на Android это sha256 от `Build.ID`, одинаковый у всех телефонов одной
/// прошивки, поэтому опираться на него одного нельзя. Старый сервер лишние
/// поля игнорирует.
///
/// URL стабильный: при переходе trial → paid ссылка НЕ меняется.
class TrialService {
  TrialService._();
  static final instance = TrialService._();

  static const _apiBase = 'https://pixellnet.com/api';
  static const _kPrefTrialUrl = 'pixellnet.trial.subscription_url';
  static const _kPrefExpiresAt = 'pixellnet.trial.expires_at';
  static const _kPrefTrialId = 'pixellnet.trial.id';
  static const _kPrefDeviceId = 'pixellnet.device.id_hash';
  static const _kPrefInstallId = 'pixellnet.install_id';

  static const _platformChannel = MethodChannel('com.hiddify.app/platform');

  /// Случайный UUID v4 этой установки. Создаётся один раз и хранится в
  /// SharedPreferences. Без пакета uuid: 16 байт из Random.secure().
  Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kPrefInstallId);
    if (cached != null && cached.isNotEmpty) return cached;

    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // версия 4
    b[8] = (b[8] & 0x3f) | 0x80; // вариант RFC 4122
    String h(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final id = '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
    await prefs.setString(_kPrefInstallId, id);
    return id;
  }

  /// sha256 от аппаратного идентификатора: Android — Settings.Secure.ANDROID_ID
  /// (через нативный метод `getAndroidId`), Windows — machine GUID (тот же
  /// исходник, что и у `device_id`). null, если получить не удалось: тогда
  /// поле `hw_id` в запрос не кладём.
  Future<String?> _hwIdHash() async {
    try {
      String? raw;
      if (Platform.isAndroid) {
        raw = await _platformChannel.invokeMethod<String>('getAndroidId').timeout(const Duration(seconds: 3));
      } else if (Platform.isWindows) {
        raw = (await DeviceInfoPlugin().windowsInfo).deviceId;
      }
      if (raw == null || raw.trim().isEmpty) return null;
      return sha256.convert(utf8.encode(raw)).toString();
    } catch (e) {
      if (kDebugMode) debugPrint('[TrialService] hw_id unavailable: $e');
      return null;
    }
  }

  Future<String> _deviceModel() async {
    try {
      if (Platform.isAndroid) {
        final model = (await DeviceInfoPlugin().androidInfo).model;
        if (model.trim().isNotEmpty) return model;
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Future<String> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  /// Поля, которые идут в тело `POST /api/trial` вместе с `device_id`.
  Future<Map<String, dynamic>> _identityFields() async {
    final hwId = await _hwIdHash();
    return {
      'install_id': await _installId(),
      if (hwId != null) 'hw_id': hwId,
      'os': Platform.operatingSystem, // android | windows | ios | ...
      'app_version': await _appVersion(),
      'device_model': await _deviceModel(),
    };
  }

  /// SHA-256 от стабильного device id (Android ID / Windows machine GUID).
  /// Хранится в SharedPreferences после первой генерации — чтобы фактори-ресет
  /// или переустановка НЕ приводили к сбросу trial (в пределах одного OS install).
  Future<String> _deviceIdHash() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kPrefDeviceId);
    if (cached != null && cached.isNotEmpty) return cached;

    String raw;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        raw = (await plugin.androidInfo).id;
      } else if (Platform.isIOS) {
        raw = (await plugin.iosInfo).identifierForVendor ?? '';
      } else if (Platform.isWindows) {
        raw = (await plugin.windowsInfo).deviceId;
      } else if (Platform.isMacOS) {
        raw = (await plugin.macOsInfo).systemGUID ?? '';
      } else if (Platform.isLinux) {
        raw = (await plugin.linuxInfo).machineId ?? '';
      } else {
        raw = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      raw = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (raw.isEmpty) {
      raw = 'empty_${DateTime.now().millisecondsSinceEpoch}';
    }
    final hash = sha256.convert(utf8.encode(raw)).toString();
    await prefs.setString(_kPrefDeviceId, hash);
    return hash;
  }

  /// Локальный кеш активного trial. null если ещё не был получен.
  Future<TrialInfo?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kPrefTrialUrl);
    final exp = prefs.getString(_kPrefExpiresAt);
    final id = prefs.getString(_kPrefTrialId);
    if (url == null || exp == null) return null;
    return TrialInfo(
      subscriptionUrl: url,
      expiresAt: DateTime.tryParse(exp) ?? DateTime.now().add(const Duration(days: 7)),
      trialId: id ?? '',
    );
  }

  /// Основной вызов: получает (или создаёт) trial-подписку.
  /// Идемпотентен — можно вызывать многократно.
  Future<TrialInfo> obtainTrial() async {
    final deviceId = await _deviceIdHash();
    DiagnosticsService.instance.event('trial.request', {'device_id': deviceId.substring(0, 8)});

    final resp = await http
        .post(
          Uri.parse('$_apiBase/trial'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId, // старый сервер: только это поле
            ...await _identityFields(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      DiagnosticsService.instance.event('trial.error', {'status': resp.statusCode});
      // 410 Gone = trial уже был использован на этом устройстве (antifraud).
      // Не показываем «Повторить» — переключаемся на TrialExpiredPage.
      if (resp.statusCode == 410) {
        // Persist флаг чтобы при следующем запуске сразу показать TrialExpiredPage
        // без лишнего запроса к серверу (экономит трафик + быстрый UX).
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pixellnet.trial.expired', true);
        throw const TrialException(
          'trial already used on this device',
          isExpired: true,
        );
      }
      throw TrialException('server returned ${resp.statusCode}', kind: TrialFailure.server, detail: '${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = data['sub_url'] as String?;
    final expires = data['expires_at'] as String?;
    final tid = data['trial_id']?.toString() ?? '';
    if (url == null || expires == null) {
      throw const TrialException('empty server response', kind: TrialFailure.emptyResponse);
    }

    final info = TrialInfo(
      subscriptionUrl: url,
      expiresAt: DateTime.parse(expires),
      trialId: tid,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefTrialUrl, info.subscriptionUrl);
    await prefs.setString(_kPrefExpiresAt, info.expiresAt.toIso8601String());
    await prefs.setString(_kPrefTrialId, info.trialId);

    DiagnosticsService.instance.event('trial.obtained', {
      'days_left': info.daysLeft,
      'trial_id': info.trialId,
    });
    return info;
  }

  /// Проверить статус существующего trial на сервере (для баннера).
  Future<TrialStatus?> checkStatus() async {
    try {
      final deviceId = await _deviceIdHash();
      final installId = await _installId();
      final resp = await http
          .get(Uri.parse('$_apiBase/trial/status?device_id=$deviceId&install_id=$installId'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return TrialStatus(
        active: data['active'] as bool? ?? false,
        daysLeft: (data['days_left'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? ''),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[TrialService] checkStatus error: $e');
      return null;
    }
  }
}

class TrialInfo {
  const TrialInfo({
    required this.subscriptionUrl,
    required this.expiresAt,
    required this.trialId,
  });

  final String subscriptionUrl;
  final DateTime expiresAt;
  final String trialId;

  int get daysLeft {
    final diff = expiresAt.difference(DateTime.now()).inHours;
    return (diff / 24).ceil().clamp(0, 999);
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class TrialStatus {
  const TrialStatus({required this.active, required this.daysLeft, this.expiresAt});
  final bool active;
  final int daysLeft;
  final DateTime? expiresAt;
}

/// Причина сбоя пробного периода: по ней экран выбирает текст на языке приложения.
enum TrialFailure { server, emptyResponse, importFailed }

class TrialException implements Exception {
  const TrialException(this.message, {this.isExpired = false, this.kind, this.detail});

  /// Служебное сообщение для журнала; людям не показывается (для них — текст по `kind`).
  final String message;
  final TrialFailure? kind;

  /// Код ответа сервера или текст ошибки — подставляется в текст для людей.
  final String? detail;
  /// true когда сервер вернул 410 Gone — trial уже использован на этом устройстве.
  /// UI должен показать TrialExpiredPage вместо generic error.
  final bool isExpired;
  @override
  String toString() => message;
}
