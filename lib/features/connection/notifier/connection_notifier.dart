import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        Future.microtask(() => ref.read(Preferences.startedByUser.notifier).update(false));
      }
      loggy.info("connection status: ${event.format()}");
    });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  Future<void> toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      DiagnosticsService.instance.event('vpn.toggle', {'from': 'error'});
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          DiagnosticsService.instance.event('vpn.toggle', {'from': 'disconnected'});
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          DiagnosticsService.instance.event('vpn.toggle', {'from': 'connected'});
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  /// v0.1.91: смена ключа сохраняет состояние VPN. Был подключён (или подключался) —
  /// переподключаемся на новый ключ; был отключён — ничего не делаем.
  /// Не in-place reconnect ядра: на Android он даёт `configure tun interface:
  /// permission denied` (старый TUN ещё не отпущен, см. откат v0.1.87) и VPN
  /// оставался «Не подключено». Полный цикл: отключить → дождаться Disconnected →
  /// пауза, чтобы Android освободил TUN → подключить с новым активным ключом.
  Future<void> reconnect(ProfileEntity? profile) async {
    final wasActive = switch (state) {
      AsyncData(value: Connected() || Connecting()) => true,
      _ => false,
    };
    if (!wasActive) return;
    if (profile == null) {
      loggy.info("no active profile, disconnecting");
      return _disconnect();
    }
    loggy.info("active profile changed, reconnecting (stop -> wait -> start)");
    DiagnosticsService.instance.event('vpn.profile_switch', {'to': profile.id});
    await ref.read(Preferences.startedByUser.notifier).update(true);
    await _disconnect();
    await _waitForDisconnected(const Duration(seconds: 10));
    // v0.1.93: Dart видит Disconnected раньше, чем Android-сервис закроет старое ядро
    // (Mobile.close) — 500 мс не хватало (createService). Плюс повторы setup в BoxService.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _connect();
  }

  Future<void> _waitForDisconnected(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (state case AsyncData(value: Disconnected())) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    loggy.warning("disconnect did not finish within $timeout, connecting anyway");
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      loggy.warning(err);
      if (err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  Future<void> _disconnect() async {
    await _connectionRepo.disconnect().mapLeft((err) {
      loggy.warning("error disconnecting", err);
      ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      state = AsyncError(err, StackTrace.current);
    }).run();
  }
}

@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
