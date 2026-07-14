import 'dart:io';

import 'package:hiddify/utils/custom_loggers.dart';
import 'package:loggy/loggy.dart';

final Loggy<InfraLogger> _loggy = Loggy<InfraLogger>('TunCleanupService');

class TunCleanupService {
  static Future<bool> cleanupStaleWindowsTunAdapters() async {
    if (!Platform.isWindows) return false;

    const psScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.InterfaceDescription -like '*sing-tun*' -and
    $_.Name -ne 'happ-tun'
}
$removed = 0
foreach ($a in $adapters) {
    Write-Output "found $($a.Name) [$($a.InterfaceDescription)] status=$($a.Status)"
    try {
        Remove-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
        Write-Output "removed $($a.Name)"
        $removed++
    } catch {
        Write-Output "failed $($a.Name): $_"
    }
}
Write-Output "total-removed=$removed"
''';

    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          psScript,
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));

      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();

      _loggy.debug('ps exit=${result.exitCode} stdout=$stdout stderr=$stderr');

      final match = RegExp(r'total-removed=(\d+)').firstMatch(stdout);
      final removed = match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;

      if (removed > 0) {
        _loggy.warning('removed $removed stale sing-tun adapter(s)');
      }

      return removed > 0;
    } catch (e) {
      _loggy.warning('cleanup failed: $e');
      return false;
    }
  }
}
