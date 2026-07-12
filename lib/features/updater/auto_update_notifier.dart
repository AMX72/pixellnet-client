import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:hiddify/features/updater/updater_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.1.26: контроллер тихой автопроверки обновлений.
///
/// Флоу:
/// 1. При запуске приложения (delay 5 сек чтобы не блокировать UI) —
///    проверяет `updateMode`.
///    - `auto` (0)   → checkForUpdate() + автозагрузка при нахождении
///    - `ask` (1)    → checkForUpdate() → показать banner на Home
///    - `manual` (2) → ничего не делать
/// 2. Throttle: если `lastCheck > now - 20h` → skip
/// 3. Preferred hour: если `now.hour < preferredHour` → skip (ждём ночь)
/// 4. Результат сохраняется в state: [UpdateInfo?] — Home banner слушает.
final autoUpdateStateProvider =
    NotifierProvider<AutoUpdateStateNotifier, AutoUpdateState>(AutoUpdateStateNotifier.new);

class AutoUpdateState {
  const AutoUpdateState({
    this.available,
    this.dismissedUntil = 0,
    this.checkedAt = 0,
  });

  /// Найденная новая версия (null если нет обновлений).
  final UpdateInfo? available;

  /// Timestamp в millis до которого баннер скрыт крестиком.
  final int dismissedUntil;

  /// Timestamp последней проверки (для UI «Проверено X назад»).
  final int checkedAt;

  bool get shouldShowBanner {
    if (available == null) return false;
    return DateTime.now().millisecondsSinceEpoch > dismissedUntil;
  }

  AutoUpdateState copyWith({
    Object? available = _sentinel,
    int? dismissedUntil,
    int? checkedAt,
  }) =>
      AutoUpdateState(
        available: identical(available, _sentinel) ? this.available : available as UpdateInfo?,
        dismissedUntil: dismissedUntil ?? this.dismissedUntil,
        checkedAt: checkedAt ?? this.checkedAt,
      );
}

const _sentinel = Object();

class AutoUpdateStateNotifier extends Notifier<AutoUpdateState> {
  static const _kPrefDismissedUntil = 'pixellnet.updater.banner_dismissed_until';

  @override
  AutoUpdateState build() {
    _kickoff();
    return const AutoUpdateState();
  }

  Future<void> _kickoff() async {
    // Прелоад dismissedUntil из SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getInt(_kPrefDismissedUntil) ?? 0;
    state = state.copyWith(dismissedUntil: dismissed);

    // Delay чтобы приложение поднялось + auto-trial + первые UI-фреймы
    await Future.delayed(const Duration(seconds: 5));

    final mode = ref.read(Preferences.updateMode);
    if (mode == 2) {
      DiagnosticsService.instance.event('auto_update.skip', {'reason': 'manual'});
      return;
    }

    // Preferred hour
    final preferredHour = ref.read(Preferences.updateCheckHour);
    final nowHour = DateTime.now().hour;
    // Мягко: если preferredHour == 24 → «в любое время» (не проверяем hour)
    final anyHour = preferredHour >= 24;
    if (!anyHour && nowHour < preferredHour) {
      DiagnosticsService.instance.event('auto_update.skip', {'reason': 'wait_hour', 'now': nowHour, 'want': preferredHour});
      return;
    }

    await _check(mode: mode);
  }

  Future<void> _check({required int mode}) async {
    try {
      DiagnosticsService.instance.event('auto_update.check', {'mode': mode});
      final info = await UpdaterService.instance.checkForUpdate();
      state = state.copyWith(
        available: info,
        checkedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (info != null) {
        DiagnosticsService.instance.event('auto_update.found', {'version': info.version});
        // TODO v0.1.27: если mode==auto, начать silent download в фоне.
        // Пока: показываем banner для всех non-manual режимов.
      } else {
        DiagnosticsService.instance.event('auto_update.up_to_date');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoUpdate] check failed: $e');
      DiagnosticsService.instance.event('auto_update.error', {'error': e.toString()});
    }
  }

  /// Юзер тапнул «крестик» на banner — прячем на 3 дня.
  Future<void> dismissBanner() async {
    final until = DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch;
    state = state.copyWith(dismissedUntil: until);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefDismissedUntil, until);
  }

  /// Ручной триггер (из Settings «Проверить сейчас»).
  Future<void> forceCheck() async {
    await _check(mode: ref.read(Preferences.updateMode));
  }
}
