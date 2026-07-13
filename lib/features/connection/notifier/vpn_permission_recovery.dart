// v0.1.34: VPN permission recovery — автодетект и авторелauncher системного
// диалога "Разрешить VPN?" без ручных действий юзера в системных настройках.
//
// Проблема: на Xiaomi POCO (MIUI/HyperOS) и других устройствах VPN-разрешение
// может быть отозвано когда другое VPN-приложение запускается, или после
// reset приватности. sing-box openTun() падает с "permission denied".
//
// Решение:
//   1. BoxService.notifyVpnPermissionRevoked() отправляет Alert.VpnPermissionRevoked
//   2. EventHandler пробрасывает его во Flutter как CoreAlert.requestVPNPermission
//   3. connection_notifier.dart видит MissingVpnPermission failure
//   4. vpnPermissionRecoveryProvider переключается в needsPermission=true
//   5. HomePage показывает inline banner (не диалог — чтобы не блокировать)
//   6. Авто-recover: провайдер сразу вызывает requestVpnPermission() без клика
//   7. MainActivity.requestVpnPermissionAndRetry() показывает системный диалог
//   8. После accept Android запускает сервис автоматически

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';

part 'vpn_permission_recovery.g.dart';

/// MethodChannel для VPN permission — часть существующего platform channel.
const _platformChannel = MethodChannel('com.hiddify.app/platform');

/// Вызывает MainActivity.requestVpnPermissionAndRetry() через MethodChannel.
/// Показывает системный диалог "Разрешить VPN?" и после accept стартует сервис.
/// Возвращает true если вызов принят (диалог показан или разрешение уже есть).
Future<bool> requestVpnPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final result = await _platformChannel.invokeMethod<bool>('vpn_request_permission');
    return result ?? false;
  } on PlatformException catch (_) {
    return false;
  }
}

/// Состояние VPN permission recovery.
enum VpnPermissionState {
  /// Нормальное состояние — разрешение есть или не Android.
  ok,
  /// Разрешение отозвано — показываем banner и ждём юзера.
  needsPermission,
  /// Идёт процесс запроса разрешения.
  requesting,
}

/// Провайдер следит за состоянием VPN permission.
///
/// Авто-recover срабатывает при первом детекте MissingVpnPermission:
/// сразу вызывает [requestVpnPermission()] без клика пользователя.
/// Если юзер отказал в системном диалоге — показываем banner с кнопкой
/// "Попробовать снова".
@Riverpod(keepAlive: true)
class VpnPermissionRecovery extends _$VpnPermissionRecovery {
  @override
  VpnPermissionState build() {
    if (!Platform.isAndroid) return VpnPermissionState.ok;

    // Слушаем connection status — при MissingVpnPermission авто-триггерим recovery.
    ref.listen<AsyncValue<ConnectionStatus>>(
      connectionNotifierProvider,
      (previous, next) {
        final status = next.valueOrNull;
        if (status is Disconnected) {
          final failure = status.connectionFailure;
          if (failure is MissingVpnPermission) {
            _onPermissionMissing();
          } else if (failure == null && state == VpnPermissionState.requesting) {
            // Успешно отключились без ошибки — сбрасываем состояние
            // (сервис перезапустится сам через prepareLauncher).
            state = VpnPermissionState.ok;
          }
        } else if (status is Connected) {
          // VPN поднялся — разрешение получено, сбрасываем banner.
          state = VpnPermissionState.ok;
        }
      },
    );

    return VpnPermissionState.ok;
  }

  void _onPermissionMissing() {
    if (state == VpnPermissionState.requesting) return;
    // Авто-recover: сразу показываем системный диалог без клика.
    state = VpnPermissionState.requesting;
    requestVpnPermission().then((ok) {
      if (!ok) {
        // Диалог не показался (activity недоступна) — переходим в needsPermission
        // чтобы показать ручную кнопку.
        state = VpnPermissionState.needsPermission;
      }
      // Если ok=true — диалог показан, ждём результата через connection status.
      // state остаётся requesting до Connected или следующей ошибки.
    });
  }

  /// Ручной retry — вызывается кнопкой "Переподключить" на HomePage.
  Future<void> retryPermission() async {
    state = VpnPermissionState.requesting;
    final ok = await requestVpnPermission();
    if (!ok) {
      state = VpnPermissionState.needsPermission;
    }
    // Если ok — ждём события Connected через listen выше.
  }

  /// Сброс состояния (например при переходе на другую страницу).
  void dismiss() {
    state = VpnPermissionState.ok;
  }
}
