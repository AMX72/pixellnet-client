import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Собирает box.log + app.log + метаданные устройства в текстовый bundle
/// и загружает на pixellnet.com/api/diagnostics/upload. Возвращает
/// короткий код (напр. `A7K2P`) который юзер даёт разработчику.
class DiagnosticUploader {
  DiagnosticUploader._();
  static final instance = DiagnosticUploader._();

  static const _endpoint = 'https://pixellnet.com/api/diagnostics/upload';

  Future<String> uploadDiagnostic() async {
    final dir = await getExternalStorageDirectory();
    final workingDir = dir?.path ?? '/tmp';
    final boxLog = File('$workingDir/box.log');
    final appLog = File('$workingDir/app.log');

    final packageInfo = await PackageInfo.fromPlatform();
    String deviceModel = 'unknown';
    String androidVersion = 'unknown';
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      deviceModel = '${info.brand} ${info.model} (${info.device})';
      androidVersion = 'Android ${info.version.release} SDK ${info.version.sdkInt}';
    }

    final buffer = StringBuffer();
    buffer.writeln('=' * 60);
    buffer.writeln('PIXELLNET DIAGNOSTIC BUNDLE');
    buffer.writeln('=' * 60);
    buffer.writeln('Generated at: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('App version:  ${packageInfo.version}+${packageInfo.buildNumber}');
    buffer.writeln('Device:       $deviceModel');
    buffer.writeln('OS:           $androidVersion');
    buffer.writeln();

    buffer.writeln('=' * 60);
    buffer.writeln('APP LOG (${appLog.path})');
    buffer.writeln('=' * 60);
    if (await appLog.exists()) {
      final content = await appLog.readAsString();
      buffer.write(_tail(content, 200 * 1024)); // last 200 KB
    } else {
      buffer.writeln('(файл не существует)');
    }
    buffer.writeln();

    buffer.writeln('=' * 60);
    buffer.writeln('BOX LOG (sing-box core, ${boxLog.path})');
    buffer.writeln('=' * 60);
    if (await boxLog.exists()) {
      final content = await boxLog.readAsString();
      buffer.write(_tail(content, 200 * 1024));
    } else {
      buffer.writeln('(файл не существует)');
    }

    final bundleBytes = utf8.encode(buffer.toString());

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bundleBytes,
        filename: 'diag-${packageInfo.version}.txt',
      ))
      ..fields['device_model'] = deviceModel
      ..fields['android_version'] = androidVersion
      ..fields['app_version'] = packageInfo.version;

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Сервер вернул HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['code'] as String;
  }

  /// Returns last [maxBytes] of string (UTF-8 safe boundary).
  String _tail(String s, int maxBytes) {
    final bytes = utf8.encode(s);
    if (bytes.length <= maxBytes) return s;
    var start = bytes.length - maxBytes;
    // Move forward until valid UTF-8 boundary
    while (start < bytes.length && (bytes[start] & 0xC0) == 0x80) {
      start++;
    }
    return '... (обрезано до последних $maxBytes байт)\n${utf8.decode(bytes.sublist(start))}';
  }
}
