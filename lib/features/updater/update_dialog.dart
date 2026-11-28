import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
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

  /// Нет разрешения на установку приложений: вместо «Обновить» — кнопка «Открыть настройки».
  bool _needsPermission = false;

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
        return context.t.ui.update.hintXiaomi;
      case OemFamily.huawei:
        return context.t.ui.update.hintHuawei;
      case OemFamily.oppo:
        return context.t.ui.update.hintOppo;
      case OemFamily.vivo:
      case OemFamily.samsung:
      case OemFamily.other:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Обрезаем changelog до первых 200 символов + без markdown-мусора.
    final changelog = widget.info.changelog
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.contains('Full Changelog'))
        .take(5)
        .join('\n');

    return AlertDialog(
      title: Text(t.ui.update.available),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.ui.update.version(version: widget.info.version),
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
                  ? t.ui.update.connecting
                  : t.ui.update.downloaded(percent: (_progress! * 100).toInt()),
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
          child: Text(_error != null ? t.ui.common.close : t.ui.common.notNow),
        ),
        if (_needsPermission)
          FilledButton(
            onPressed: _installing ? null : _openSettings,
            child: Text(t.ui.update.openSettings),
          )
        else
          FilledButton(
            onPressed: _installing ? null : _startInstall,
            child: Text(_installing
                ? (_progress == null
                    ? t.ui.update.downloading
                    : '${(_progress! * 100).toInt()}%')
                : (_error != null ? t.ui.update.again : t.ui.common.update)),
          ),
      ],
    );
  }

  Future<void> _openSettings() async {
    await openInstallUnknownAppsSettings();
    if (mounted) {
      setState(() {
        _error = context.t.ui.update.allowInstall;
      });
    }
  }

  Future<void> _startInstall() async {
    setState(() {
      _installing = true;
      _error = null;
      _needsPermission = false;
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
      // v0.1.33: собираем сетевую диагностику — часто «файл повреждён»
      // это на самом деле «оператор выключил вышку в этом районе».
      final diag = await collectNetworkDiagnostics();
      if (mounted) {
        setState(() {
          _installing = false;
          _needsPermission = e is InstallPermissionDeniedException;
          _error = _errorText(e, diag);
        });
      }
    }
  }

  String _errorText(Object e, NetworkDiagnostics diag) {
    final t = context.t;
    if (diag.state == NetworkState.noCellSignal) {
      return t.ui.update.noCell;
    }
    if (diag.state == NetworkState.cellSignalButNoData) {
      return t.ui.update.noData;
    }
    if (e is InstallPermissionDeniedException) return t.ui.update.permissionNeeded;
    if (e is UpdateException) return e.present(t);
    return e.toString().replaceFirst('Exception: ', '');
  }
}
