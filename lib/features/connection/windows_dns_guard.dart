// v0.1.102 Windows: пока VPN включён, все DNS-запросы Windows идут только через VPN (правило NRPT).
//
// 2026-11-23 (CHANGELOG part 46): на ПК, где роутер раздаёт IPv6, каждый новый сайт ждал ~11 с.
// Ядро (ipv4_only) отвечает на AAAA «нет записей»; DNS-клиент Windows после отрицательного
// ответа перестаёт спрашивать tun0 и идёт к DNS других адаптеров (Wi-Fi), а strict_route
// глушит порт 53 мимо tun0 (WFP) → Windows ждёт полный цикл таймаутов. Правило NRPT «.»
// отправляет ВСЕ запросы Windows только на указанные серверы, отрицательный ответ окончательный.
//
// Серверы в правиле — публичные (77.88.8.8, 8.8.8.8), а не адрес TUN: пока VPN включён, пакеты
// к ним идут в tun0 и их перехватывает ядро (hijack-dns) — отвечает наш DNS с правилами .ru и т. д.
// Если приложение упало и правило осталось, эти серверы отвечают сами — интернет без VPN работает.
// Правило снимаем при отключении, при выходе, при старте (хвост прошлого запуска) и в деинсталляторе
// (installer/pixellnet.iss, [UninstallRun]).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final windowsDnsGuardProvider = Provider<WindowsDnsGuard?>((ref) {
  if (!Platform.isWindows) return null;
  final guard = WindowsDnsGuard._(ref);
  ref.onDispose(guard._dispose);
  guard._start();
  return guard;
});

class WindowsDnsGuard with AppLogger {
  WindowsDnsGuard._(this.ref);

  final Ref ref;

  // Comment правила — «PIXELLNET»; снимаем всё, что начинается с него (и ручное «PIXELLNET-test»).
  static const _applyScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Get-DnsClientNrptRule | Where-Object { $_.Comment -like 'PIXELLNET*' } | Remove-DnsClientNrptRule -Force
Add-DnsClientNrptRule -Namespace '.' -NameServers '77.88.8.8','8.8.8.8' -Comment 'PIXELLNET' -DisplayName 'PIXELLNET DNS via VPN'
Clear-DnsClientCache
Write-Output 'nrpt-ok'
''';

  static const _removeScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$r = @(Get-DnsClientNrptRule | Where-Object { $_.Comment -like 'PIXELLNET*' })
if ($r.Count -gt 0) { $r | Remove-DnsClientNrptRule -Force; Clear-DnsClientCache }
Write-Output "nrpt-ok removed=$($r.Count)"
''';

  Future<void> _queue = Future<void>.value();

  /// null — неизвестно (после старта могло остаться правило от прошлого запуска).
  bool? _applied;
  Timer? _offTimer;
  bool _shutdown = false;

  void _start() {
    _enqueue(false, 'startup cleanup');
    ref.listen<AsyncValue<ConnectionStatus>>(
      connectionNotifierProvider,
      (_, next) => _onStatus(next.valueOrNull),
      fireImmediately: true,
    );
  }

  void _onStatus(ConnectionStatus? status) {
    if (_shutdown) return;
    switch (status) {
      case Connected():
        _offTimer?.cancel();
        final tun = ref.read(ConfigOptions.serviceMode) == ServiceMode.tun;
        _enqueue(tun, tun ? 'connected' : 'connected, not TUN mode');
      case Disconnected():
        // Статус может на 1–2 с «моргнуть» отключением (поток статуса переоткрывается) —
        // снимаем, только если через 3 с VPN так и не вернулся.
        _offTimer?.cancel();
        _offTimer = Timer(const Duration(seconds: 3), () {
          if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) {
            _enqueue(false, 'disconnected');
          }
        });
      default:
    }
  }

  /// Выход из приложения: снять правило и дождаться (вызывает WindowNotifier.exit).
  Future<void> shutdown() {
    _shutdown = true;
    _offTimer?.cancel();
    _enqueue(false, 'exit', force: true);
    return _queue;
  }

  void _dispose() {
    _offTimer?.cancel();
  }

  void _enqueue(bool on, String reason, {bool force = false}) {
    _queue = _queue.then((_) async {
      if (!force && _applied == on) return;
      final sw = Stopwatch()..start();
      final res = await _runPowerShell(on ? _applyScript : _removeScript);
      final ok = res != null && res.out.contains('nrpt-ok');
      if (ok) _applied = on;
      final state = on ? 'ON' : 'OFF';
      if (ok) {
        loggy.info('dns policy $state ($reason) in ${sw.elapsedMilliseconds} ms: ${_short(res.out)}');
      } else {
        loggy.warning(
          'dns policy $state ($reason) FAILED in ${sw.elapsedMilliseconds} ms: '
          '${_short(res?.out ?? '')} ${_short(res?.err ?? '')}',
        );
      }
    }).catchError((Object e) {
      loggy.warning('dns policy error: $e');
    });
  }

  /// PowerShell без окна консоли (detached) — обычный Process.run из оконного приложения
  /// на миг показывает чёрное окно. Скрипт — через -EncodedCommand (UTF-16LE base64), без кавычек.
  Future<({String out, String err})?> _runPowerShell(String script) async {
    try {
      final process = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _encode(script)],
        mode: ProcessStartMode.detachedWithStdio,
      );
      unawaited(process.stdin.close().catchError((Object _) {}));
      final err = process.stderr.transform(latin1.decoder).join();
      final out = await process.stdout.transform(latin1.decoder).join().timeout(const Duration(seconds: 20));
      final errText = await err.timeout(const Duration(seconds: 2), onTimeout: () => '');
      return (out: out, err: errText);
    } catch (e) {
      loggy.warning('dns policy: powershell failed: $e');
      return null;
    }
  }

  static String _short(String s) {
    final one = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return one.length > 300 ? one.substring(0, 300) : one;
  }

  static String _encode(String script) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[2 * i] = units[i] & 0xff;
      bytes[2 * i + 1] = units[i] >> 8;
    }
    return base64.encode(bytes);
  }
}
