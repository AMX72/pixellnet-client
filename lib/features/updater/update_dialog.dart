import 'package:flutter/material.dart';
import 'package:hiddify/features/updater/updater_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  bool _installing = false;
  String? _error;
  OemFamily _oem = OemFamily.other;

  @override
  void initState() {
    super.initState();
    // v0.1.31: определяем OEM для guided hint. Если Xiaomi/HyperOS — покажем
    // подсказку что при установке будет доп. диалог MIUI Security.
    detectOemFamily().then((f) {
      if (mounted) setState(() => _oem = f);
    });
  }

  String? get _oemHint {
    switch (_oem) {
      case OemFamily.xiaomi:
        return 'MIUI/HyperOS покажет: «Приложение содержит риски». '
            'Нажми «Установить всё равно» → «Готово».';
      case OemFamily.huawei:
        return 'EMUI спросит подтверждение установки. '
            'Отмечай «Разрешить» на всех запросах.';
      case OemFamily.oppo:
        return 'ColorOS/PurityScan может флажить как «риск». '
            'Нажми «Установить всё равно».';
      case OemFamily.vivo:
      case OemFamily.samsung:
      case OemFamily.other:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Обрезаем changelog до первых 200 символов + без markdown-мусора.
    final changelog = widget.info.changelog
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.contains('Full Changelog'))
        .take(5)
        .join('\n');

    return AlertDialog(
      title: const Text('Доступно обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версия ${widget.info.version}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (changelog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              changelog.length > 200 ? '${changelog.substring(0, 200)}...' : changelog,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_installing) ...[
            const SizedBox(height: 16),
            // Indeterminate когда прогресс ещё не пошёл (первый HTTP handshake).
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 6),
            Text(
              _progress == null
                  ? 'Подключаемся к серверу...'
                  : 'Скачано ${(_progress! * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          if (_oemHint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _oemHint!,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(_error != null ? 'Закрыть' : 'Не сейчас'),
        ),
        if (_needsPermission)
          FilledButton(
            onPressed: _installing ? null : _openSettings,
            child: const Text('Открыть настройки'),
          )
        else
          FilledButton(
            onPressed: _installing ? null : _startInstall,
            child: Text(_installing
                ? (_progress == null
                    ? 'Скачиваем…'
                    : '${(_progress! * 100).toInt()}%')
                : (_error != null ? 'Ещё раз' : 'Обновить')),
          ),
      ],
    );
  }

  bool get _needsPermission =>
      _error != null && _error!.contains('Разреши установку');

  Future<void> _openSettings() async {
    await openInstallUnknownAppsSettings();
    if (mounted) {
      setState(() {
        _error = 'Разреши установку → вернись → Повторить';
      });
    }
  }

  Future<void> _startInstall() async {
    setState(() {
      _installing = true;
      _error = null;
      _progress = null;
    });
    try {
      await UpdaterService.instance.downloadAndInstall(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Success — Android installer открылся, закрываем диалог.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}
