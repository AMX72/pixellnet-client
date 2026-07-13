import 'package:flutter/foundation.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.1.38: контроллер тихого авто-обновления прокси-профилей при boot.
///
/// Флоу:
/// 1. При запуске приложения (delay 8 сек, после auto-update check) —
///    проверяет `profileRefreshMode`.
///    - `auto` (0)   → обновляет все remote-профили тихо (force upsertRemote)
///    - `ask` (1)    → показывает bottom sheet с предложением обновить
///    - `manual` (2) → ничего не делает
/// 2. Throttle: если `lastRefresh > now - 20h` → skip
/// 3. Preferred hour: если `now.hour < profileRefreshHour` → skip
/// 4. State: [AutoProfileRefreshState] — Home/Settings слушают.
///
/// Метод refreshNow() — ручной триггер из Settings.
final autoProfileRefreshProvider =
    NotifierProvider<AutoProfileRefreshNotifier, AutoProfileRefreshState>(
        AutoProfileRefreshNotifier.new);

class AutoProfileRefreshState {
  const AutoProfileRefreshState({
    this.isRefreshing = false,
    this.lastRefreshedAt = 0,
    this.newChannelsCount = 0,
    this.pendingAsk = false,
    this.lastError,
  });

  /// true пока идёт сетевой upsertRemote
  final bool isRefreshing;

  /// timestamp последнего успешного refresh (ms)
  final int lastRefreshedAt;

  /// Сколько каналов добавилось/изменилось в последнем refresh
  final int newChannelsCount;

  /// true если mode==ask и ждём ответа юзера
  final bool pendingAsk;

  /// Ошибка последнего refresh (или null)
  final String? lastError;

  bool get hasRefreshed => lastRefreshedAt > 0;

  AutoProfileRefreshState copyWith({
    bool? isRefreshing,
    int? lastRefreshedAt,
    int? newChannelsCount,
    bool? pendingAsk,
    Object? lastError = _sentinel,
  }) =>
      AutoProfileRefreshState(
        isRefreshing: isRefreshing ?? this.isRefreshing,
        lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
        newChannelsCount: newChannelsCount ?? this.newChannelsCount,
        pendingAsk: pendingAsk ?? this.pendingAsk,
        lastError: identical(lastError, _sentinel)
            ? this.lastError
            : lastError as String?,
      );
}

const _sentinel = Object();

/// SharedPreferences key — throttle timestamp.
const _kPrefLastRefresh = 'pixellnet.profile_refresh.last_refresh_at';

/// 20 часов — не беспокоить юзера чаще чем раз в сутки.
const _kThrottleMs = 20 * 60 * 60 * 1000;

class AutoProfileRefreshNotifier extends Notifier<AutoProfileRefreshState> {
  @override
  AutoProfileRefreshState build() {
    _kickoff();
    return const AutoProfileRefreshState();
  }

  Future<void> _kickoff() async {
    // Восстанавливаем timestamp из SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final lastRefresh = prefs.getInt(_kPrefLastRefresh) ?? 0;
    state = state.copyWith(lastRefreshedAt: lastRefresh);

    // Delay: даём UI подняться + auto-update notifier отстреляться
    await Future.delayed(const Duration(seconds: 8));

    final mode = ref.read(Preferences.profileRefreshMode);
    if (mode == 2) {
      DiagnosticsService.instance
          .event('auto_profile_refresh.skip', {'reason': 'manual'});
      return;
    }

    // Throttle: не чаще чем раз в 20 часов
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - lastRefresh) < _kThrottleMs) {
      DiagnosticsService.instance
          .event('auto_profile_refresh.skip', {'reason': 'throttle'});
      return;
    }

    // Preferred hour
    final preferredHour = ref.read(Preferences.profileRefreshHour);
    final nowHour = DateTime.now().hour;
    final anyHour = preferredHour >= 24;
    if (!anyHour && nowHour < preferredHour) {
      DiagnosticsService.instance.event('auto_profile_refresh.skip',
          {'reason': 'wait_hour', 'now': nowHour, 'want': preferredHour});
      return;
    }

    if (mode == 1) {
      // ask — выставляем флаг, Home/Settings покажут bottom sheet
      state = state.copyWith(pendingAsk: true);
      DiagnosticsService.instance
          .event('auto_profile_refresh.pending_ask');
      return;
    }

    // mode == 0 → тихое автообновление
    await _doRefresh(silent: true);
  }

  /// Юзер принял предложение из bottom sheet (mode=ask).
  Future<void> confirmRefresh() async {
    state = state.copyWith(pendingAsk: false);
    await _doRefresh(silent: false);
  }

  /// Юзер отклонил bottom sheet.
  void dismissAsk() {
    state = state.copyWith(pendingAsk: false);
  }

  /// Ручной триггер из Settings «Проверить прокси сейчас».
  Future<void> refreshNow() async {
    await _doRefresh(silent: false, force: true);
  }

  Future<void> _doRefresh({required bool silent, bool force = false}) async {
    if (state.isRefreshing) return;

    state = state.copyWith(isRefreshing: true, lastError: null);
    DiagnosticsService.instance
        .event('auto_profile_refresh.start', {'silent': silent});

    try {
      final profileRepo =
          ref.read(profileRepositoryProvider).requireValue;

      // Получаем все remote-профили
      final remoteProfiles = await profileRepo
          .watchAll()
          .map(
            (event) => event.getOrElse((_) => <ProfileEntity>[]).whereType<RemoteProfileEntity>().toList(),
          )
          .first;

      if (remoteProfiles.isEmpty) {
        DiagnosticsService.instance
            .event('auto_profile_refresh.skip', {'reason': 'no_remote_profiles'});
        state = state.copyWith(isRefreshing: false);
        return;
      }

      int refreshed = 0;
      int errors = 0;

      for (final profile in remoteProfiles) {
        final result =
            await profileRepo.upsertRemote(profile.url).run();
        result.fold(
          (failure) {
            errors++;
            if (kDebugMode) {
              debugPrint(
                  '[AutoProfileRefresh] error updating ${profile.name}: $failure');
            }
          },
          (_) {
            refreshed++;
          },
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPrefLastRefresh, now);

      DiagnosticsService.instance.event('auto_profile_refresh.done',
          {'refreshed': refreshed, 'errors': errors});

      state = state.copyWith(
        isRefreshing: false,
        lastRefreshedAt: now,
        newChannelsCount: refreshed,
        lastError: errors > 0 ? 'Обновлено $refreshed из ${remoteProfiles.length}' : null,
      );

      // Показываем non-intrusive уведомление
      if (!silent || refreshed > 0) {
        final notif = ref.read(inAppNotificationControllerProvider);
        if (errors == 0) {
          notif.showSuccessToast(
              'Обновились прокси-каналы: $refreshed');
        } else {
          notif.showErrorToast(
              'Обновлено $refreshed из ${remoteProfiles.length}, ошибок: $errors');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AutoProfileRefresh] error: $e');
      DiagnosticsService.instance
          .event('auto_profile_refresh.error', {'error': e.toString()});
      state = state.copyWith(
        isRefreshing: false,
        lastError: e.toString(),
      );
    }
  }
}
