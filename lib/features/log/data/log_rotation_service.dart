import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_rotation_service.g.dart';

/// v0.0.45 fix: использует [logPathResolverProvider] вместо getExternalStorageDirectory().
/// Прежде ротация проверяла Android/data/.../ (external), но hiddify-core пишет
/// app.log + box.log во внутренний рабочий каталог (appDirectoriesProvider.workingDir).
/// Теперь пути синхронизированы — ротация срабатывает корректно.
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

      // v0.0.45 fix: берём workingDir через logPathResolverProvider
      // — тот же путь что hiddify-core использует для записи логов.
      final resolver = ref.read(logPathResolverProvider);

      final filesToCheck = [
        resolver.appFile(),
        resolver.coreFile(),
      ];

      for (final file in filesToCheck) {
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size > limitBytes) {
          await _truncateOldHalf(file, size);
          if (kDebugMode) {
            debugPrint('[LogRotation] rotated ${file.path}: was ${size ~/ 1024} KB');
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
