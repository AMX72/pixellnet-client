import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
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
      launchAtStartup.setup(
        appName: appInfo.name,
        appPath: Platform.resolvedExecutable,
        packageName: "Pixellnet.PixellnetVPN",
      );
      final isEnabled = await launchAtStartup.isEnabled();
      loggy.info("desktop auto start is [${isEnabled ? "Enabled" : "Disabled"}]");
      _startTimer();
      ref.onDispose(() => _timer?.cancel());
      return isEnabled;
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

  Future<bool> updateStatus() async {
    if (!PlatformUtils.isDesktop) return state.valueOrNull ?? false;
    final isEnabled = await launchAtStartup.isEnabled();
    state = AsyncValue.data(isEnabled);
    return isEnabled;
  }

  Future<void> enable() async {
    loggy.debug("enabling auto start");
    if (PlatformUtils.isDesktop) {
      await launchAtStartup.enable();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    }
    state = const AsyncValue.data(true);
  }

  Future<void> disable() async {
    loggy.debug("disabling auto start");
    if (PlatformUtils.isDesktop) {
      await launchAtStartup.disable();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, false);
    }
    state = const AsyncValue.data(false);
  }

  /// Read persisted mobile preference without activating the full notifier
  /// (used at app bootstrap before provider graph is up).
  static Future<bool> isMobileAutoConnectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }
}
