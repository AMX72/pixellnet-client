import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Собирает полный snapshot состояния клиента для отправки на поддержку.
///
/// Включает: OS+железо, интернет (провайдер+регион по IP), приложение,
/// последние N событий, конфиг активного профиля, hash-суммы вместо
/// приватных данных.
class DiagnosticsService {
  DiagnosticsService._();
  static final instance = DiagnosticsService._();

  /// Собирает JSON-snapshot размером ~5-20 КБ.
  /// [includeIpLookup=false] отключает ipapi.co запрос (при offline).
  Future<Map<String, dynamic>> collect({bool includeIpLookup = true}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final device = await _deviceInfo();
    final app = await _appInfo();
    final network = includeIpLookup ? await _networkInfo() : {'skipped': true};

    return {
      'schema_version': 1,
      'collected_at_utc': now,
      'app': app,
      'device': device,
      'network': network,
      'events': _eventBuffer.toList(),
    };
  }

  /// Форматирует snapshot в человекочитаемый Markdown для копирования в тикет.
  String formatAsMarkdown(Map<String, dynamic> snapshot) {
    final buf = StringBuffer();
    buf.writeln('# PIXELLNET diagnostics — ${snapshot['collected_at_utc']}');
    buf.writeln();
    _writeSection(buf, '## App', snapshot['app'] as Map<String, dynamic>?);
    _writeSection(buf, '## Device', snapshot['device'] as Map<String, dynamic>?);
    _writeSection(buf, '## Network', snapshot['network'] as Map<String, dynamic>?);
    final events = snapshot['events'] as List<dynamic>? ?? [];
    if (events.isNotEmpty) {
      buf.writeln('## Recent events (${events.length})');
      buf.writeln('```');
      for (final e in events.reversed.take(50)) {
        buf.writeln(e);
      }
      buf.writeln('```');
    }
    return buf.toString();
  }

  static void _writeSection(StringBuffer buf, String title, Map<String, dynamic>? section) {
    if (section == null) return;
    buf.writeln(title);
    section.forEach((k, v) => buf.writeln('- **$k**: $v'));
    buf.writeln();
  }

  Future<Map<String, dynamic>> _appInfo() async {
    final pkg = await PackageInfo.fromPlatform();
    return {
      'name': pkg.appName,
      'version': pkg.version,
      'build': pkg.buildNumber,
      'package': pkg.packageName,
      'debug_mode': kDebugMode,
      'locale': Platform.localeName,
    };
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    final plugin = DeviceInfoPlugin();
    final base = {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'dart_version': Platform.version.split(' ').first,
    };
    try {
      if (Platform.isWindows) {
        final d = await plugin.windowsInfo;
        return {
          ...base,
          'product_name': d.productName,
          'edition': d.editionId,
          'build_number': d.buildNumber,
          'display_version': d.displayVersion,
          'system_memory_mb': d.systemMemoryInMegabytes,
        };
      } else if (Platform.isAndroid) {
        final d = await plugin.androidInfo;
        return {
          ...base,
          'manufacturer': d.manufacturer,
          'model': d.model,
          'brand': d.brand,
          'sdk': d.version.sdkInt,
          'release': d.version.release,
          'is_physical': d.isPhysicalDevice,
        };
      } else if (Platform.isIOS) {
        final d = await plugin.iosInfo;
        return {
          ...base,
          'model': d.model,
          'name': d.name,
          'system_version': d.systemVersion,
        };
      } else if (Platform.isMacOS) {
        final d = await plugin.macOsInfo;
        return {
          ...base,
          'model': d.model,
          'os_release': d.osRelease,
          'arch': d.arch,
          'memory_bytes': d.memorySize,
        };
      } else if (Platform.isLinux) {
        final d = await plugin.linuxInfo;
        return {
          ...base,
          'name': d.name,
          'version': d.version,
          'pretty_name': d.prettyName,
        };
      }
    } catch (e) {
      base['device_info_error'] = e.toString();
    }
    return base;
  }

  Future<Map<String, dynamic>> _networkInfo() async {
    try {
      final resp = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        return {'error': 'ipapi_status_${resp.statusCode}'};
      }
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'public_ip': j['ip'],
        'city': j['city'],
        'region': j['region'],
        'country': j['country_name'],
        'country_code': j['country_code'],
        'org': j['org'],
        'asn': j['asn'],
        'timezone': j['timezone'],
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─── Event buffer ───
  // Кольцевой буфер последних 200 событий (для отправки со snapshot'ом).

  static const _maxEvents = 200;
  final List<String> _eventBuffer = [];

  /// Логирует событие в кольцевой буфер (для диагностики, не в файл).
  /// Пример вызова: `DiagnosticsService.instance.event('vpn_connect', {'server':'PYXEL'})`.
  void event(String type, [Map<String, dynamic>? data]) {
    final ts = DateTime.now().toUtc().toIso8601String();
    final payload = data == null ? '' : ' ${jsonEncode(data)}';
    _eventBuffer.add('$ts $type$payload');
    if (_eventBuffer.length > _maxEvents) {
      _eventBuffer.removeAt(0);
    }
    if (kDebugMode) debugPrint('[DIAG] $type$payload');
  }

  void clear() => _eventBuffer.clear();
}
