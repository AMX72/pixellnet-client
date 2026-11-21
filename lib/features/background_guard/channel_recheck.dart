// v0.1.101: быстрая перепроверка каналов, пока приложение открыто.
//
// Ядро само проверяет каналы раз в 10 мин (monitoring.interval). После короткого сбоя сети
// (2026-11-21: окно 06:55–07:07, когда из домашней сети не было связи со входом) все каналы
// ещё до 10 мин числились мёртвыми, и помогала только кнопка «Проверить пинг»
// (CHANGELOG 2026-11-21 part 42). Теперь:
//  * человек открыл приложение, а прошлая проверка была больше минуты назад → проверяем сразу;
//  * активный канал не отвечает → повторяем через 20, 40, 80 с, дальше раз в 2 мин, пока не оживёт.
// В фоне (экран выключен, приложение свёрнуто) ничего не делаем: ночью процессор не тратим —
// MIUI закрывает приложения, которые при выключенном экране едят больше 2% CPU.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final channelRecheckProvider = Provider<void>((ref) {
  final r = _ChannelRecheck(ref);
  ref.onDispose(r.dispose);
  r.start();
});

class _ChannelRecheck with WidgetsBindingObserver, AppLogger {
  _ChannelRecheck(this.ref);

  final Ref ref;

  static const _backoffSec = [20, 40, 80, 120];
  static const _mainGroup = 'select'; // главный переключатель каналов в конфиге ядра

  Timer? _timer;
  int _step = 0;
  bool _foreground = true;
  bool _dead = false;
  bool _testing = false;
  DateTime _lastTest = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final s = WidgetsBinding.instance.lifecycleState;
    _foreground = s == null || _isForeground(s);
    ref.listen<AsyncValue<OutboundInfo>>(
      activeProxyNotifierProvider,
      (_, next) => _onActive(next.valueOrNull),
      fireImmediately: true,
    );
    ref.listen<bool>(serviceRunningProvider, (_, running) {
      if (!running) _reset();
    });
  }

  bool _isForeground(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) return true;
    // на компьютере окно может быть видно, но без фокуса
    return !(Platform.isAndroid || Platform.isIOS) && s == AppLifecycleState.inactive;
  }

  void _onActive(OutboundInfo? info) {
    if (info == null) return;
    final d = info.urlTestDelay;
    if (d > 0 && d < 65000) {
      if (_dead) loggy.info('channels respond again');
      _reset();
    } else if (d >= 65000) {
      if (!_dead) loggy.info('active channel does not respond, fast recheck');
      _dead = true;
      _schedule();
    }
  }

  void _schedule() {
    if (!_foreground || !_dead || _timer != null) return;
    final sec = _backoffSec[_step.clamp(0, _backoffSec.length - 1)];
    _timer = Timer(Duration(seconds: sec), _fire);
  }

  Future<void> _fire() async {
    _timer = null;
    if (!_foreground || !_dead) return;
    await _test('channel does not respond');
    if (_step < _backoffSec.length - 1) _step++;
    _schedule();
  }

  Future<void> _test(String why) async {
    if (_testing || !ref.read(serviceRunningProvider)) return;
    _testing = true;
    _lastTest = DateTime.now();
    loggy.info('url test: $why');
    try {
      await ref.read(proxyRepositoryProvider).urlTest(_mainGroup).run();
    } catch (_) {
      // ядро ещё не готово — следующая попытка по расписанию
    } finally {
      _testing = false;
    }
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _step = 0;
    _dead = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = _isForeground(state);
    if (fg == _foreground) return;
    _foreground = fg;
    if (!fg) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (DateTime.now().difference(_lastTest) > const Duration(seconds: 60)) {
      // onResume заново подключается к ядру — даём ему пару секунд
      Future<void>.delayed(const Duration(seconds: 2), () => _test('app opened'));
    }
    _schedule();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }
}
