import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/features/log/data/diagnostic_uploader.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class LogsPage extends HookConsumerWidget with PresLogger {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final state = ref.watch(logsOverviewNotifierProvider);
    final notifier = ref.watch(logsOverviewNotifierProvider.notifier);

    final debug = ref.watch(debugModeNotifierProvider);
    final pathResolver = ref.watch(logPathResolverProvider);

    final filterController = useTextEditingController(text: state.filter);

    // v0.0.37: кнопка «Отправить» вынесена в FAB (prominent CTA).
    // Код больше не показывается юзеру — только сообщение об успехе.
    // В PopupMenu остались только share-файлы (для advanced users).
    final List<PopupMenuEntry> popupButtons = [
      PopupMenuItem(
        child: Text(t.pages.logs.shareCoreLogs),
        onTap: () async {
          await UriUtils.tryShareOrLaunchFile(
            Uri.parse(pathResolver.coreFile().path),
            fileOrDir: pathResolver.directory.uri,
          );
        },
      ),
      PopupMenuItem(
        child: Text(t.pages.logs.shareAppLogs),
        onTap: () async {
          await UriUtils.tryShareOrLaunchFile(
            Uri.parse(pathResolver.appFile().path),
            fileOrDir: pathResolver.directory.uri,
          );
        },
      ),
    ];

    return Scaffold(
      // v0.0.37: FAB — основная CTA «Отправить разработчику».
      // Prominent, всегда видна, не спрятана в ⋮ меню.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final code = await _uploadDiagnostic(context);
          if (code != null && context.mounted) {
            _showDiagSentDialog(context);
          }
        },
        icon: const Icon(Icons.send_rounded),
        label: const Text('Отправить разработчику'),
      ),
      appBar: AppBar(
        title: Text(t.pages.logs.title),
        actions: [
          if (state.paused)
            IconButton(
              onPressed: notifier.resume,
              icon: const Icon(FluentIcons.play_20_regular),
              tooltip: t.common.resume,
              iconSize: 20,
            )
          else
            IconButton(
              onPressed: notifier.pause,
              icon: const Icon(FluentIcons.pause_20_regular),
              tooltip: t.common.pause,
              iconSize: 20,
            ),
          IconButton(
            onPressed: notifier.clear,
            icon: const Icon(FluentIcons.delete_lines_20_regular),
            tooltip: t.common.clear,
            iconSize: 20,
          ),
          if (popupButtons.isNotEmpty)
            PopupMenuButton(
              icon: Icon(AdaptiveIcon(context).more),
              itemBuilder: (context) {
                return popupButtons;
              },
            ),
          const Gap(8),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return <Widget>[
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: MultiSliver(
                children: [
                  // NestedAppBar(
                  //   forceElevated: innerBoxIsScrolled,
                  // ),
                  SliverPinnedHeader(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Flexible(
                              child: TextFormField(
                                controller: filterController,
                                onChanged: notifier.filterMessage,
                                decoration: InputDecoration(isDense: true, hintText: t.common.filter),
                              ),
                            ),
                            const Gap(16),
                            DropdownButton<Option<LogLevel>>(
                              value: optionOf(state.levelFilter),
                              onChanged: (v) {
                                if (v == null) return;
                                notifier.filterLevel(v.toNullable());
                              },
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              borderRadius: BorderRadius.circular(4),
                              items: [
                                DropdownMenuItem(value: none(), child: Text(t.common.all)),
                                ...LogLevel.choices.map((e) => DropdownMenuItem(value: some(e), child: Text(e.name))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            return CustomScrollView(
              primary: false,
              reverse: true,
              slivers: <Widget>[
                switch (state.logs) {
                  AsyncData(value: final logs) => SliverList.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (log.level != null)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        log.level!.name.toUpperCase(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium?.copyWith(color: log.level!.color),
                                      ),
                                      if (log.time != null)
                                        Text(log.time!.toString(), style: Theme.of(context).textTheme.labelSmall),
                                    ],
                                  ),
                                Text(extractMessage(log.message), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          if (index != 0) const Divider(indent: 16, endIndent: 16, height: 4),
                        ],
                      );
                    },
                  ),
                  AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                  _ => const SliverLoadingBodyPlaceholder(),
                },
                SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}

String extractMessage(String message) {
  final parts = message.split(' ');
  return parts.length <= 2 ? parts.last : parts.sublist(2).join(' ');
}

/// v0.0.37: consent AlertDialog ПЕРЕД upload (privacy-safe).
/// Возвращает 5-символьный код или null при отказе / ошибке.
Future<String?> _uploadDiagnostic(BuildContext context) async {
  // Шаг 1 — явный consent юзера.
  final consent = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Отправить логи разработчику?'),
      content: const Text(
        'Диагностический журнал (события приложения, состояние VPN, '
        'ошибки, модель устройства) будет отправлен на сервер разработчика '
        'для устранения неисправностей.\n\n'
        'Журнал НЕ содержит адресов посещённых сайтов и содержимого трафика.\n\n'
        'Хранится до 30 дней, после чего автоматически удаляется.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Отправить'),
        ),
      ],
    ),
  );
  if (consent != true) return null;

  // Шаг 2 — сам upload с progress spinner.
  if (!context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Отправляем логи...'),
        ],
      ),
    ),
  );
  try {
    final code = await DiagnosticUploader.instance.uploadDiagnostic();
    if (context.mounted) Navigator.pop(context);
    return code;
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}'),
      backgroundColor: Colors.red.shade900,
    ));
    return null;
  }
}

/// v0.0.37: показываем юзеру friendly-сообщение вместо кода.
/// Код генерируется на сервере и хранится для нас — юзеру его знать не нужно.
void _showDiagSentDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Логи отправлены'),
      content: const Text(
        'Логи отправлены. Мы приступили к анализу — ответим в TG-канале в течение 24 часов.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}
