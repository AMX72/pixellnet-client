import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/auto_start/windows_autostart.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auto_start_notifier.g.dart';

/// Desktop: OS-level launch at startup (login item / registry run key).
/// Mobile: persisted preference — AppStartupAutoConnect reads it and
/// starts the VPN when the user opens the app with an active profile.
@Riverpod(keepAlive: true)
class AutoStartNotifier extends _$AutoStartNotifier with InfraLogger {
  Timer? _timer;
  static const _prefKey = "auto_connect_on_app_start";

  @override
  Future<bool> build() async {
    if (PlatformUtils.isDesktop) {
      final appInfo = ref.watch(appInfoProvider).requireValue;
      _startTimer();
      ref.onDispose(() => _timer?.cancel());
      if (Platform.isWindows) return _buildWindows(appInfo.name);
      launchAtStartup.setup(
        appName: appInfo.name,
        appPath: Platform.resolvedExecutable,
        packageName: "Pixellnet.PixellnetVPN",
      );
      try {
        final isEnabled = await launchAtStartup.isEnabled();
        loggy.info("desktop auto start is [${isEnabled ? "Enabled" : "Disabled"}]");
        return isEnabled;
      } catch (e, st) {
        loggy.warning("desktop auto start check failed", e, st);
        return false;
      }
    }
    // Mobile: read saved preference
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefKey) ?? false;
    loggy.info("mobile auto-connect preference: [$enabled]");
    return enabled;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (timer) => updateStatus());
  }

  /// v0.1.100: Windows — задача Планировщика вместо ключа Run (см. WindowsAutostart).
  /// Старую запись (Run / ярлык в «Автозагрузке») переносим в задачу: желание юзера
  /// сохраняется, двойного запуска на ПК без UAC не будет.
  Future<bool> _buildWindows(String appName) async {
    try {
      if (await WindowsAutostart.hasLegacy(appName)) {
        loggy.info("migrating legacy auto start (Run/Startup shortcut) to scheduled task");
        if (!await WindowsAutostart.isEnabled()) {
          await WindowsAutostart.enable(Platform.resolvedExecutable);
        }
        await WindowsAutostart.removeLegacy(appName);
      }
      final isEnabled = await WindowsAutostart.isEnabled();
      loggy.info("windows auto start (scheduled task) is [${isEnabled ? "Enabled" : "Disabled"}]");
      return isEnabled;
    } catch (e, st) {
      loggy.warning("windows auto start check failed", e, st);
      return false;
    }
  }

  Future<bool> _isEnabledDesktop() =>
      Platform.isWindows ? WindowsAutostart.isEnabled() : launchAtStartup.isEnabled();

  Future<bool> updateStatus() async {
    if (!PlatformUtils.isDesktop) return state.valueOrNull ?? false;
    try {
      final isEnabled = await _isEnabledDesktop();
      state = AsyncValue.data(isEnabled);
      return isEnabled;
    } catch (e, st) {
      loggy.warning("auto start status check failed", e, st);
      return state.valueOrNull ?? false;
    }
  }

  /// Бросает исключение, если включить не удалось — UI показывает ошибку
  /// (раньше исключение терялось и ползунок молча оставался выключенным).
  Future<void> enable() async {
    loggy.debug("enabling auto start");
    if (PlatformUtils.isDesktop) {
      try {
        if (Platform.isWindows) {
          await WindowsAutostart.enable(Platform.resolvedExecutable);
          await WindowsAutostart.removeLegacy(ref.read(appInfoProvider).requireValue.name);
        } else {
          await launchAtStartup.enable();
        }
      } catch (e, st) {
        loggy.warning("enable auto start failed", e, st);
        await updateStatus();
        rethrow;
      }
      await updateStatus();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    state = const AsyncValue.data(true);
  }

  Future<void> disable() async {
    loggy.debug("disabling auto start");
    if (PlatformUtils.isDesktop) {
      try {
        if (Platform.isWindows) {
          await WindowsAutostart.disable();
          await WindowsAutostart.removeLegacy(ref.read(appInfoProvider).requireValue.name);
        } else {
          await launchAtStartup.disable();
        }
      } catch (e, st) {
        loggy.warning("disable auto start failed", e, st);
        await updateStatus();
        rethrow;
      }
      await updateStatus();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    state = const AsyncValue.data(false);
  }

  /// Read persisted mobile preference without activating the full notifier
  /// (used at app bootstrap before provider graph is up).
  static Future<bool> isMobileAutoConnectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }
}
