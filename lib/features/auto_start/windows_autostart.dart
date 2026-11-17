import 'dart:io';
import 'dart:typed_data';

/// Автозапуск на Windows через Планировщик задач (v0.1.100).
///
/// pixellnet.exe собран с `requireAdministrator` (нужно для TUN). При включённом
/// UAC Windows молча НЕ запускает при входе программы, требующие повышения прав,
/// из `HKCU\...\CurrentVersion\Run` и из папки «Автозагрузка» — поэтому
/// `launch_at_startup` (ключ Run) и ярлык установщика у обычных пользователей
/// не работали. Задача «при входе» с `RunLevel=HighestAvailable` стартует
/// приложение с правами администратора без запроса UAC.
///
/// Плюс `launch_at_startup` 0.5.1 падал на ПК без раздела
/// `Explorer\StartupApproved\Run` (`Registry.openPath` бросает исключение) —
/// ползунок не включался. Здесь реестр не используется, кроме удаления старых записей.
class WindowsAutostart {
  WindowsAutostart._();

  static const taskName = 'PIXELLNET Autostart';

  /// Аргумент, с которым задача запускает приложение — по нему bootstrap
  /// понимает, что это автозапуск при входе, и подключает VPN сам.
  static const launchArg = '--autostart';

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  static Future<bool> isEnabled({String name = taskName}) async {
    final r = await Process.run('schtasks', ['/Query', '/TN', name]);
    return r.exitCode == 0;
  }

  /// Создаёт (или пересоздаёт) задачу автозапуска для текущего пользователя.
  static Future<void> enable(String exePath, {String name = taskName}) async {
    final dir = await Directory.systemTemp.createTemp('pxl-autostart');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}task.xml');
      // schtasks /XML принимает UTF-16 LE с BOM (как в объявлении encoding).
      await file.writeAsBytes(_utf16le(taskXml(exePath)), flush: true);
      final r = await Process.run('schtasks', ['/Create', '/TN', name, '/XML', file.path, '/F']);
      if (r.exitCode != 0) {
        throw ProcessException('schtasks', ['/Create', '/TN', name], '${r.stderr}${r.stdout}'.trim(), r.exitCode);
      }
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> disable({String name = taskName}) async {
    if (!await isEnabled(name: name)) return;
    final r = await Process.run('schtasks', ['/Delete', '/TN', name, '/F']);
    if (r.exitCode != 0) {
      throw ProcessException('schtasks', ['/Delete', '/TN', name], '${r.stderr}${r.stdout}'.trim(), r.exitCode);
    }
  }

  /// Старые записи автозапуска: значение в `Run` (launch_at_startup) или
  /// ярлык в «Автозагрузке» (галка установщика до v0.1.100).
  static Future<bool> hasLegacy(String appName) async {
    final r = await Process.run('reg', ['query', _runKey, '/v', appName]);
    return r.exitCode == 0 || _startupShortcut(appName).existsSync();
  }

  static Future<void> removeLegacy(String appName) async {
    await Process.run('reg', ['delete', _runKey, '/v', appName, '/f']);
    await Process.run('reg', ['delete', _approvedKey, '/v', appName, '/f']);
    final lnk = _startupShortcut(appName);
    if (lnk.existsSync()) {
      try {
        lnk.deleteSync();
      } catch (_) {}
    }
  }

  static File _startupShortcut(String appName) => File(
    '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\$appName.lnk',
  );

  static String? _currentUser() {
    final user = Platform.environment['USERNAME'];
    if (user == null || user.isEmpty) return null;
    final domain = Platform.environment['USERDOMAIN'];
    return (domain == null || domain.isEmpty) ? user : '$domain\\$user';
  }

  static String taskXml(String exePath) {
    final user = _currentUser();
    final userId = user != null ? '<UserId>${_esc(user)}</UserId>' : '';
    final workDir = File(exePath).parent.path;
    return '''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>PIXELLNET</Author>
    <Description>Запуск PIXELLNET VPN при входе в Windows</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      $userId
      <Delay>PT10S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      $userId
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>5</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${_esc(exePath)}"</Command>
      <Arguments>$launchArg</Arguments>
      <WorkingDirectory>${_esc(workDir)}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
''';
  }

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static Uint8List _utf16le(String s) {
    final units = s.codeUnits;
    final bytes = Uint8List(2 + units.length * 2);
    bytes[0] = 0xFF;
    bytes[1] = 0xFE;
    for (var i = 0; i < units.length; i++) {
      bytes[2 + i * 2] = units[i] & 0xFF;
      bytes[3 + i * 2] = (units[i] >> 8) & 0xFF;
    }
    return bytes;
  }
}
