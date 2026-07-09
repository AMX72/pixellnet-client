import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ── Config ───────────────────────────────────────────────────────────────────

/// true = mock mode (backend не готов). Переключить на false когда pixellnet-api задеплоен.
const bool useMockActivationApi = true;

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
  static const _baseUrl = 'https://pixellnet.com/api/v1';

  final Dio _dio;

  ActivationApiHttp()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: 'application/json',
          ),
        );

  @override
  Future<TrialResult> startTrial() async {
    final fingerprint = await _buildFingerprint();
    final response = await _dio.post<Map<String, dynamic>>(
      '/trial',
      data: {
        'device_id': fingerprint,
        'os': 'android',
        'app_version': '0.0.24',
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
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/user/$token');
      final data = response.data!;
      return UserStatus(
        status: data['status'] as String,
        expiresAt: DateTime.parse(data['expires_at'] as String),
        planCode: data['plan_code'] as String,
        dataUsedBytes: (data['data_used_bytes'] as num).toInt(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<ActivationResult> activatePromo(String code) async {
    final fingerprint = await _buildFingerprint();
    final response = await _dio.post<Map<String, dynamic>>(
      '/activate',
      data: {'promo_code': code, 'fingerprint': fingerprint},
    );
    final data = response.data!;
    return ActivationResult(
      subUrl: data['sub_url'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
      planCode: data['plan_code'] as String,
    );
  }

  Future<String> _buildFingerprint() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      final raw =
          '${android.id}|${android.manufacturer}|${android.model}';
      final bytes = utf8.encode(raw);
      return sha256.convert(bytes).toString();
    } catch (_) {
      return 'unknown-device';
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final activationApiProvider = Provider<ActivationApi>((ref) {
  if (useMockActivationApi || kReleaseMode == false) {
    return ActivationApiMock();
  }
  return ActivationApiHttp();
});
