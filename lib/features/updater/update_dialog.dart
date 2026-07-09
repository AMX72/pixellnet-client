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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Доступно обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версия ${widget.info.version}'),
          const SizedBox(height: 8),
          if (widget.info.changelog.isNotEmpty)
            Text(
              widget.info.changelog.length > 300
                  ? '${widget.info.changelog.substring(0, 300)}...'
                  : widget.info.changelog,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text('${(_progress! * 100).toInt()}%',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: _installing ? null : _startInstall,
          child: Text(_installing ? 'Загрузка...' : 'Установить'),
        ),
      ],
    );
  }

  Future<void> _startInstall() async {
    setState(() => _installing = true);
    await UpdaterService.instance.downloadAndInstall(
      widget.info,
      onProgress: (p) => setState(() => _progress = p),
    );
  }
}
