import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Zero-config trial: при первом запуске автоматически создаёт trial-подписку
/// на 7 дней через `POST /api/trial` (pixellnet-api). Юзер не вводит ссылку.
///
/// Backend: `https://pixellnet.com/api/trial` — идемпотентен по device_id,
/// повторный вызов с тем же device_id возвращает существующую подписку.
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
          body: jsonEncode({'device_id': deviceId}),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      DiagnosticsService.instance.event('trial.error', {'status': resp.statusCode});
      throw TrialException('Сервер вернул ${resp.statusCode}. Попробуй позже.');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = data['sub_url'] as String?;
    final expires = data['expires_at'] as String?;
    final tid = data['trial_id']?.toString() ?? '';
    if (url == null || expires == null) {
      throw TrialException('Пустой ответ сервера');
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
      final resp = await http
          .get(Uri.parse('$_apiBase/trial/status?device_id=$deviceId'))
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

class TrialException implements Exception {
  const TrialException(this.message);
  final String message;
  @override
  String toString() => message;
}
