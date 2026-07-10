import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_rotation_service.g.dart';

/// v0.0.37: Log rotation — проверяет размер app.log при старте и каждые 10 мин.
/// При превышении лимита (из logSizeLimitNotifierProvider) усекает старую половину.
///
/// Запускается через [LogRotationService.start] из bootstrap.dart.
class LogRotationService {
  LogRotationService._();
  static final instance = LogRotationService._();

  Timer? _timer;

  /// Запускает фоновую проверку. Вызывается один раз после bootstrap.
  void start(Ref ref) {
    _checkAndRotate(ref);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _checkAndRotate(ref));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkAndRotate(Ref ref) async {
    try {
      final limitMb = ref.read(logSizeLimitNotifierProvider);
      final limitBytes = limitMb * 1024 * 1024;

      final dir = await getExternalStorageDirectory();
      final workingDir = dir?.path ?? '/tmp';

      for (final name in ['app.log', 'box.log']) {
        final file = File('$workingDir/$name');
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size > limitBytes) {
          await _truncateOldHalf(file, size);
          if (kDebugMode) {
            debugPrint('[LogRotation] rotated $name: was ${size ~/ 1024} KB');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LogRotation] error: $e');
    }
  }

  /// Удаляет первую половину файла, оставляя последние [size/2] байт.
  /// UTF-8-safe: начало берётся с ближайшей ascii/multi-byte boundary.
  Future<void> _truncateOldHalf(File file, int size) async {
    final bytes = await file.readAsBytes();
    var start = bytes.length ~/ 2;
    // Сдвигаем вперёд до валидной UTF-8 границы
    while (start < bytes.length && (bytes[start] & 0xC0) == 0x80) {
      start++;
    }
    final header =
        '... (старые логи удалены при ротации ${DateTime.now().toIso8601String()})\n'
            .codeUnits;
    final newContent = [...header, ...bytes.sublist(start)];
    await file.writeAsBytes(newContent);
  }
}

/// Провайдер-сервис, инициализируется при первом чтении.
/// Вызывай из bootstrap: `container.read(logRotationServiceProvider)`.
@Riverpod(keepAlive: true)
LogRotationService logRotationService(Ref ref) {
  final svc = LogRotationService.instance;
  svc.start(ref);
  ref.onDispose(svc.dispose);
  return svc;
}
