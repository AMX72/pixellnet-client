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
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:win32/win32.dart' as w32;

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
  // Результат — код выхода: 10 = поставлено, 10 + N = снято N правил, 1 = ошибка.
  static const _applyScript = r'''
$ProgressPreference = 'SilentlyContinue'
try {
  Get-DnsClientNrptRule | Where-Object { $_.Comment -like 'PIXELLNET*' } | Remove-DnsClientNrptRule -Force -ErrorAction Stop
  Add-DnsClientNrptRule -Namespace '.' -NameServers '77.88.8.8','8.8.8.8' -Comment 'PIXELLNET' -DisplayName 'PIXELLNET DNS via VPN' -ErrorAction Stop
  Clear-DnsClientCache
  exit 10
} catch { exit 1 }
''';

  static const _removeScript = r'''
$ProgressPreference = 'SilentlyContinue'
try {
  $r = @(Get-DnsClientNrptRule | Where-Object { $_.Comment -like 'PIXELLNET*' })
  if ($r.Count -gt 0) { $r | Remove-DnsClientNrptRule -Force -ErrorAction Stop; Clear-DnsClientCache }
  exit (10 + $r.Count)
} catch { exit 1 }
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
      final code = await _runPowerShell(on ? _applyScript : _removeScript);
      final ok = code != null && code >= 10;
      if (ok) _applied = on;
      final state = on ? 'ON' : 'OFF';
      if (ok) {
        final removed = on ? '' : ', removed ${code - 10}';
        loggy.info('dns policy $state ($reason) in ${sw.elapsedMilliseconds} ms$removed');
      } else {
        loggy.warning('dns policy $state ($reason) FAILED in ${sw.elapsedMilliseconds} ms, exit code $code');
      }
    }).catchError((Object e) {
      loggy.warning('dns policy error: $e');
    });
  }

  /// PowerShell в скрытой консоли: CreateProcess + CREATE_NO_WINDOW, ожидание — в отдельном isolate.
  /// Process.run из оконного приложения на миг показывает чёрное окно консоли, а
  /// ProcessStartMode.detached* (DETACHED_PROCESS — совсем без консоли) PowerShell 5.1 не исполняет:
  /// на бете 0.1.102+177 процесс завершался за 60–100 мс без вывода (2026-11-24).
  Future<int?> _runPowerShell(String script) async {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final exe = '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final commandLine = '"$exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${_encode(script)}';
    try {
      return await _runHiddenInIsolate(commandLine);
    } catch (e) {
      loggy.warning('dns policy: launch failed: $e');
      return null;
    }
  }

  static Future<int?> _runHiddenInIsolate(String commandLine) => Isolate.run(() => _runHidden(commandLine, 20000));

  /// Код выхода процесса или null (не запустился / не уложился в таймаут).
  static int? _runHidden(String commandLine, int timeoutMs) {
    final si = calloc<w32.STARTUPINFO>();
    final pi = calloc<w32.PROCESS_INFORMATION>();
    final exitCode = calloc<Uint32>();
    final cmd = commandLine.toNativeUtf16();
    try {
      si.ref.cb = sizeOf<w32.STARTUPINFO>();
      final created = w32.CreateProcess(
        nullptr,
        cmd,
        nullptr,
        nullptr,
        w32.FALSE,
        w32.CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        si,
        pi,
      );
      if (created == 0) return null;
      try {
        if (w32.WaitForSingleObject(pi.ref.hProcess, timeoutMs) != w32.WAIT_OBJECT_0) return null;
        if (w32.GetExitCodeProcess(pi.ref.hProcess, exitCode) == 0) return null;
        return exitCode.value;
      } finally {
        w32.CloseHandle(pi.ref.hProcess);
        w32.CloseHandle(pi.ref.hThread);
      }
    } finally {
      calloc.free(si);
      calloc.free(pi);
      calloc.free(exitCode);
      malloc.free(cmd);
    }
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
