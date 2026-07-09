import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ── Config ───────────────────────────────────────────────────────────────────

/// v0.0.35: real pixellnet-api задеплоен на https://pixellnet.com/api/trial
/// (проверено curl → возвращает валидный sub_url). Mock отключён.
const bool useMockActivationApi = false;

const _kMockSubUrl =
    'https://pixellnet.com/sub/cHhuX1pHVlgzX1ZROTVDLDE3ODM1ODI1ODUvFbGqXSy4_/sing-box';

// ── Model ────────────────────────────────────────────────────────────────────

class TrialResult {
  final String subUrl;
  final DateTime expiresAt;

  const TrialResult({required this.subUrl, required this.expiresAt});
}

class ActivationResult {
  final String subUrl;
  final DateTime expiresAt;
  final String planCode;

  const ActivationResult({
    required this.subUrl,
    required this.expiresAt,
    required this.planCode,
  });
}

class UserStatus {
  final String status; // 'active' | 'expired' | 'trial'
  final DateTime expiresAt;
  final String planCode;
  final int dataUsedBytes;

  const UserStatus({
    required this.status,
    required this.expiresAt,
    required this.planCode,
    required this.dataUsedBytes,
  });

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isTrial => planCode == 'trial';
  int get daysLeft => expiresAt.difference(DateTime.now()).inDays.clamp(0, 9999);
}

// ── Interface ────────────────────────────────────────────────────────────────

abstract class ActivationApi {
  Future<TrialResult> startTrial();
  Future<UserStatus?> getStatus(String token);
  Future<ActivationResult> activatePromo(String code);
}

// ── Mock implementation ───────────────────────────────────────────────────────

class ActivationApiMock implements ActivationApi {
  @override
  Future<TrialResult> startTrial() async {
    await Future.delayed(const Duration(milliseconds: 1800)); // имитируем сеть
    return TrialResult(
      subUrl: _kMockSubUrl,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
  }

  @override
  Future<UserStatus?> getStatus(String token) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return UserStatus(
      status: 'trial',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      planCode: 'trial',
      dataUsedBytes: 0,
    );
  }

  @override
  Future<ActivationResult> activatePromo(String code) async {
    await Future.delayed(const Duration(milliseconds: 1000));
    return ActivationResult(
      subUrl: _kMockSubUrl,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      planCode: 'basic_1m',
    );
  }
}

// ── HTTP implementation ───────────────────────────────────────────────────────

class ActivationApiHttp implements ActivationApi {
  /// v0.0.35: реальный endpoint без /v1 префикса (совпадает с pixellnet-api routes).
  static const _baseUrl = 'https://pixellnet.com/api';

  final Dio _dio;

  ActivationApiHttp()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            contentType: 'application/json',
          ),
        );

  @override
  Future<TrialResult> startTrial() async {
    final fingerprint = await _buildFingerprint();
    final deviceModel = await _buildDeviceModel();
    final response = await _dio.post<Map<String, dynamic>>(
      '/trial',
      data: {
        'device_id': fingerprint,
        'os': 'android',
        'app_version': '0.0.35',
        'device_model': deviceModel,
      },
    );
    final data = response.data!;
    return TrialResult(
      subUrl: data['sub_url'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  @override
  Future<UserStatus?> getStatus(String token) async {
    // v0.0.35: /api/trial/status?device_id=xxx returns simple active/expires_at.
    try {
      final fingerprint = await _buildFingerprint();
      final response = await _dio.get<Map<String, dynamic>>(
        '/trial/status',
        queryParameters: {'device_id': fingerprint},
      );
      final data = response.data!;
      final active = data['active'] as bool;
      if (!active) return null;
      return UserStatus(
        status: 'trial',
        expiresAt: DateTime.parse(data['expires_at'] as String),
        planCode: 'trial',
        dataUsedBytes: 0,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<ActivationResult> activatePromo(String code) async {
    // Использует existing /api/activate endpoint (ключи).
    final response = await _dio.post<Map<String, dynamic>>(
      '/activate',
      data: {'key': code},
    );
    final data = response.data!;
    return ActivationResult(
      subUrl: data['sub_url'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
      planCode: data['plan'] as String,
    );
  }

  Future<String> _buildFingerprint() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      // ANDROID_ID может меняться при factory reset — но стабильный между запусками.
      // Комбинируем с serial где возможно (нужно permission — упрощаем).
      final raw = '${android.id}|${android.brand}|${android.model}|${android.device}';
      final bytes = utf8.encode(raw);
      return sha256.convert(bytes).toString();
    } catch (_) {
      return 'unknown-device-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<String> _buildDeviceModel() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      return '${android.brand} ${android.model}';
    } catch (_) {
      return 'unknown';
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final activationApiProvider = Provider<ActivationApi>((ref) {
  // v0.0.35: real API работает — но оставляем возможность переключиться на mock
  // через флаг useMockActivationApi (для offline dev).
  if (useMockActivationApi) {
    return ActivationApiMock();
  }
  return ActivationApiHttp();
});
