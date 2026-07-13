import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/notifier/auto_profile_refresh_notifier.dart';
import 'package:hiddify/features/updater/auto_update_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:humanizer/humanizer.dart';

class GeneralPage extends HookConsumerWidget {
  const GeneralPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.general.title)),
      body: ListView(
        children: [
          const LocalePrefTile(),
          const ThemeModePrefTile(),
          const EnableAnalyticsPrefTile(),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.general.autoIpCheck),
            value: ref.watch(Preferences.autoCheckIp),
            secondary: const Icon(Icons.flag_rounded),
            onChanged: ref.read(Preferences.autoCheckIp.notifier).update,
          ),
          if (PlatformUtils.isAndroid) ...[
            SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.dynamicNotification),
              secondary: const Icon(Icons.speed_rounded),
              value: ref.watch(Preferences.dynamicNotification),
              onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
            ),
            SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.hapticFeedback),
              secondary: const Icon(Icons.vibration_rounded),
              value: ref.watch(hapticServiceProvider),
              onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
            ),
          ],
          if (PlatformUtils.isDesktop) ...[
            const ClosingPrefTile(),
            SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.autoStart),
              secondary: const Icon(Icons.auto_mode_rounded),
              value: ref.watch(autoStartNotifierProvider).asData!.value,
              onChanged: (value) async => value
                  ? await ref.read(autoStartNotifierProvider.notifier).enable()
                  : await ref.read(autoStartNotifierProvider.notifier).disable(),
            ),
            SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.silentStart),
              secondary: const Icon(Icons.visibility_off_rounded),
              value: ref.watch(Preferences.silentStart),
              onChanged: ref.read(Preferences.silentStart.notifier).update,
            ),
          ],
          if (PlatformUtils.isAndroid) const BatteryOptimizationWidget(),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.general.memoryLimit),
            subtitle: Text(t.pages.settings.general.memoryLimitMsg),
            secondary: const Icon(Icons.memory_rounded),
            value: !ref.watch(Preferences.disableMemoryLimit),
            onChanged: (value) async => await ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
          ),
          ListTile(
            leading: const Icon(Icons.description_rounded),
            title: const Text('Размер журнала'),
            subtitle: Text('${ref.watch(Preferences.logMaxSizeMb)} МБ — старые записи затираются'),
            trailing: DropdownButton<int>(
              value: ref.watch(Preferences.logMaxSizeMb),
              underline: const SizedBox.shrink(),
              items: const [5, 20, 50, 100, 500]
                  .map((mb) => DropdownMenuItem(value: mb, child: Text('$mb МБ')))
                  .toList(),
              onChanged: (v) async {
                if (v != null) await ref.read(Preferences.logMaxSizeMb.notifier).update(v);
              },
            ),
          ),
          // v0.1.26: раздел обновлений — 3-режимный dropdown + час проверки.
          ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('Как обновлять'),
            subtitle: Text(_updateModeLabel(ref.watch(Preferences.updateMode))),
            trailing: DropdownButton<int>(
              value: ref.watch(Preferences.updateMode),
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Само')),
                DropdownMenuItem(value: 1, child: Text('Спросить')),
                DropdownMenuItem(value: 2, child: Text('Руками')),
              ],
              onChanged: (v) async {
                if (v != null) await ref.read(Preferences.updateMode.notifier).update(v);
              },
            ),
          ),
          if (ref.watch(Preferences.updateMode) == 0)
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Когда проверять'),
              subtitle: Text(_updateHourLabel(ref.watch(Preferences.updateCheckHour))),
              trailing: DropdownButton<int>(
                value: ref.watch(Preferences.updateCheckHour),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 3, child: Text('Ночью')),
                  DropdownMenuItem(value: 7, child: Text('Утром')),
                  DropdownMenuItem(value: 14, child: Text('Днём')),
                  DropdownMenuItem(value: 21, child: Text('Вечером')),
                  DropdownMenuItem(value: 24, child: Text('В любое')),
                ],
                onChanged: (v) async {
                  if (v != null) await ref.read(Preferences.updateCheckHour.notifier).update(v);
                },
              ),
            ),
          // v0.1.29: ручная кнопка «Проверить сейчас» — доступна во всех режимах
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Проверить сейчас'),
            subtitle: const Text('Не ждём — ищем обновление прямо сейчас'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await ref.read(autoUpdateStateProvider.notifier).forceCheck();
              if (!context.mounted) return;
              final available = ref.read(autoUpdateStateProvider).available;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(available == null
                      ? 'Уже свежак — новее пока нет'
                      : 'Есть свежая версия · ${available.version}'),
                ),
              );
            },
          ),
          // v0.1.38: раздел обновления прокси-каналов (Marzban subscription)
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Как обновлять прокси-каналы'),
            subtitle: Text(_profileRefreshModeLabel(ref.watch(Preferences.profileRefreshMode))),
            trailing: DropdownButton<int>(
              value: ref.watch(Preferences.profileRefreshMode),
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Само')),
                DropdownMenuItem(value: 1, child: Text('Спросить')),
                DropdownMenuItem(value: 2, child: Text('Руками')),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await ref.read(Preferences.profileRefreshMode.notifier).update(v);
                }
              },
            ),
          ),
          if (ref.watch(Preferences.profileRefreshMode) == 0)
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Когда обновлять каналы'),
              subtitle: Text(_profileRefreshHourLabel(ref.watch(Preferences.profileRefreshHour))),
              trailing: DropdownButton<int>(
                value: ref.watch(Preferences.profileRefreshHour),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 3, child: Text('Ночью')),
                  DropdownMenuItem(value: 7, child: Text('Утром')),
                  DropdownMenuItem(value: 14, child: Text('Днём')),
                  DropdownMenuItem(value: 21, child: Text('Вечером')),
                  DropdownMenuItem(value: 24, child: Text('В любое')),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    await ref.read(Preferences.profileRefreshHour.notifier).update(v);
                  }
                },
              ),
            ),
          ListTile(
            leading: ref.watch(autoProfileRefreshProvider).isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_rounded),
            title: const Text('Обновить прокси сейчас'),
            subtitle: const Text('Скачать свежий список серверов'),
            trailing: const Icon(Icons.chevron_right_rounded),
            enabled: !ref.watch(autoProfileRefreshProvider).isRefreshing,
            onTap: () async {
              await ref.read(autoProfileRefreshProvider.notifier).refreshNow();
              if (!context.mounted) return;
              final st = ref.read(autoProfileRefreshProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    st.lastError != null
                        ? st.lastError!
                        : st.newChannelsCount > 0
                            ? 'Обновились прокси-каналы: +${st.newChannelsCount}'
                            : 'Список актуален — изменений нет',
                  ),
                ),
              );
            },
          ),
          // Debug mode toggle — hidden in release builds (PIXELLNET brand)
          if (kDebugMode)
            SwitchListTile.adaptive(
              title: Text(t.pages.settings.general.debugMode),
              secondary: const Icon(Icons.bug_report_rounded),
              value: ref.watch(debugModeNotifierProvider),
              onChanged: (value) async {
                if (value)
                  await ref
                      .read(dialogNotifierProvider.notifier)
                      .showOk(t.pages.settings.general.debugMode, t.pages.settings.general.debugModeMsg);
                await ref.read(debugModeNotifierProvider.notifier).update(value);
              },
            ),
          ChoicePreferenceWidget(
            selected: ref.watch(ConfigOptions.logLevel),
            preferences: ref.watch(ConfigOptions.logLevel.notifier),
            choices: LogLevel.choices,
            title: t.pages.settings.general.logLevel,
            icon: Icons.description_rounded,
            presentChoice: (value) => value.name.toUpperCase(),
          ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.connectionTestUrl),
            preferences: ref.watch(ConfigOptions.connectionTestUrl.notifier),
            title: t.pages.settings.general.connectionTestUrl,
            icon: Icons.link_rounded,
          ),
          ListTile(
            title: Text(t.pages.settings.general.urlTestInterval),
            subtitle: Text(ref.watch(ConfigOptions.urlTestInterval).toApproximateTime(isRelativeToNow: false)),
            leading: const Icon(Icons.timer_rounded),
            onTap: () async => await ref
                .read(dialogNotifierProvider.notifier)
                .showSettingSlider(
                  title: t.pages.settings.general.urlTestInterval,
                  initialValue: ref.watch(ConfigOptions.urlTestInterval).inMinutes.coerceIn(0, 60).toDouble(),
                  onReset: ref.read(ConfigOptions.urlTestInterval.notifier).reset,
                  min: 1,
                  max: 60,
                  divisions: 60,
                  labelGen: (value) => Duration(minutes: value.toInt()).toApproximateTime(isRelativeToNow: false),
                )
                .then((value) async {
                  if (value == null) return;
                  await ref.read(ConfigOptions.urlTestInterval.notifier).update(Duration(minutes: value.toInt()));
                }),
          ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.clashApiPort),
            preferences: ref.watch(ConfigOptions.clashApiPort.notifier),
            title: t.pages.settings.general.clashApiPort,
            icon: Icons.api_rounded,
            validateInput: isPort,
            digitsOnly: true,
            inputToValue: int.tryParse,
          ),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.general.useXrayCoreWhenPossible),
            subtitle: Text(t.pages.settings.general.useXrayCoreWhenPossibleMsg),
            secondary: const Icon(Icons.extension_rounded),
            value: ref.watch(ConfigOptions.useXrayCoreWhenPossible),
            onChanged: ref.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update,
          ),
        ],
      ),
    );
  }

  static String _updateModeLabel(int mode) => switch (mode) {
        0 => 'Скачает и поставит без вопросов',
        1 => 'Спросим — ты решишь',
        2 => 'Только когда сам нажмёшь',
        _ => '',
      };

  static String _updateHourLabel(int hour) => switch (hour) {
        3 => 'Ночью (около 3:00) — пока ты спишь',
        7 => 'Утром (около 7:00)',
        14 => 'Днём (около 14:00)',
        21 => 'Вечером (около 21:00)',
        24 => 'В любое время дня',
        _ => 'В $hour:00',
      };

  static String _profileRefreshModeLabel(int mode) => switch (mode) {
        0 => 'Обновит список серверов без вопросов',
        1 => 'Спросим — ты решишь',
        2 => 'Только когда сам нажмёшь',
        _ => '',
      };

  static String _profileRefreshHourLabel(int hour) => switch (hour) {
        3 => 'Ночью (около 3:00) — пока ты спишь',
        7 => 'Утром (около 7:00)',
        14 => 'Днём (около 14:00)',
        21 => 'Вечером (около 21:00)',
        24 => 'В любое время дня',
        _ => 'В $hour:00',
      };
}
