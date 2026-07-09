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
        ],
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(_error != null ? 'Закрыть' : 'Позже'),
        ),
        FilledButton(
          onPressed: _installing ? null : _startInstall,
          child: Text(_installing
              ? (_progress == null ? 'Загрузка...' : '${(_progress! * 100).toInt()}%')
              : (_error != null ? 'Повторить' : 'Установить')),
        ),
      ],
    );
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
