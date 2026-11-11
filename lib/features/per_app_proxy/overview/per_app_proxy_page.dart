import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_loading_notifier.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

class PerAppProxyPage extends HookConsumerWidget with PresLogger {
  const PerAppProxyPage({super.key});

  int _getPriority(AppPackageInfo app, Map<String, int> selected) {
    final flag = selected[app.packageName];
    if (flag == null) return 4;
    if (PkgFlag.userSelection.check(flag)) {
      return 1;
    } else if (PkgFlag.autoSelection.check(flag) && !PkgFlag.forceDeselection.check(flag)) {
      return 2;
    } else {
      return 3;
    }
  }

  Future<Set<AppPackageInfo>> getApps(bool hideSystem) async {
    if (PlatformUtils.isAndroid) {
      return (await InstalledApps.getInstalledApps(
        hideSystem,
        true,
      )).map((e) => AppPackageInfo(packageName: e.packageName, name: e.name, icon: e.icon)).toSet();
    }
    if (Platform.isWindows) {
      return _getWindowsProcesses(hideSystem);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return _getUnixProcesses(hideSystem);
    }
    return {};
  }

  /// Scan running processes on Linux/macOS via `ps -A -o comm=`.
  /// - Linux: returns command name (basename, no args).
  /// - macOS: returns full executable path — we basename it.
  /// Deduped by basename, filtered system/kernel noise.
  Future<Set<AppPackageInfo>> _getUnixProcesses(bool hideSystem) async {
    const noise = <String>{
      // Linux kernel threads + core services
      'init', 'systemd', 'systemd-journal', 'systemd-logind', 'systemd-udevd',
      'systemd-resolve', 'systemd-timesyn', 'systemd-oomd', 'systemd-networkd',
      'kthreadd', 'ksoftirqd', 'kworker', 'rcu_sched', 'rcu_tasks_rude_',
      'migration', 'watchdog', 'cpuhp', 'kcompactd', 'khugepaged', 'kswapd0',
      'kblockd', 'ata_sff', 'md', 'edac-poller', 'devfreq_wq', 'kdevtmpfs',
      'khubd', 'kintegrityd', 'kstrp', 'crypto', 'scsi_eh_0',
      'dbus-daemon', 'dbus-broker', 'udevd', 'rsyslogd', 'cron', 'crond',
      'sshd', 'avahi-daemon', 'cups-browsed', 'NetworkManager', 'wpa_supplicant',
      'polkitd', 'accounts-daemon', 'power-profiles-', 'upowerd', 'colord',
      'bluetoothd', 'ModemManager', 'gdm', 'gdm-session-wor', 'gdm-wayland-ses',
      'Xorg', 'Xwayland', 'gnome-shell', 'gnome-session-b', 'ibus-daemon',
      'at-spi-bus-laun', 'at-spi2-registr', 'gvfsd', 'gvfs-udisks2-vo',
      'tracker-miner-f', 'goa-daemon', 'evolution-calen', 'evolution-addre',
      // macOS daemons
      'launchd', 'kernel_task', 'WindowServer', 'loginwindow', 'SystemUIServer',
      'ControlCenter', 'Dock', 'Finder', 'NotificationCenter', 'Spotlight',
      'coreaudiod', 'logd', 'mds', 'mds_stores', 'mdworker', 'mdworker_shared',
      'opendirectoryd', 'blued', 'identityservices', 'cfprefsd',
      'distnoted', 'trustd', 'nsurlsessiond', 'nsurlstoraged',
      'syspolicyd', 'tccd', 'secd', 'useractivityd', 'lsd', 'sharingd',
      'coreduetd', 'contextstored', 'suggestd', 'knowledge-agent',
      'universalaccessd', 'symptomsd', 'routined', 'remindd', 'callservicesd',
      'commerce', 'softwareupdated', 'parsec', 'cloudd', 'bird', 'apsd',
      'assistantd', 'coreremoted', 'bluetoothuserd',
      // PIXELLNET self
      'pixellnet', 'PIXELLNET', 'pixellnetagent', 'hiddify',
    };
    try {
      final result = await Process.run('ps', ['-A', '-o', 'comm=']);
      if (result.exitCode != 0) return {};
      final lines = (result.stdout as String).split('\n');
      final processes = <String, AppPackageInfo>{};
      for (final raw in lines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        // Skip kernel threads in square brackets: [kworker/0:1-events]
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) continue;
        // Basename
        final name = trimmed.contains('/')
            ? trimmed.substring(trimmed.lastIndexOf('/') + 1)
            : trimmed;
        if (name.isEmpty) continue;
        if (hideSystem && noise.contains(name)) continue;
        final key = name.toLowerCase();
        if (processes.containsKey(key)) continue;
        processes[key] = AppPackageInfo(packageName: name, name: name, icon: null);
      }
      return processes.values.toSet();
    } catch (e) {
      loggy.warning('Unix ps failed', e);
      return {};
    }
  }

  /// Scan running Windows processes via `tasklist /FO CSV /NH`.
  /// ~100-200ms, run on-demand when the screen opens — not in background.
  /// Returns unique .exe names (deduped). Icons not supported (would need PE
  /// resource extraction via FFI — skipped for MVP).
  Future<Set<AppPackageInfo>> _getWindowsProcesses(bool hideSystem) async {
    const systemExes = <String>{
      'system idle process', 'system', 'registry', 'memory compression',
      'smss.exe', 'csrss.exe', 'wininit.exe', 'winlogon.exe', 'services.exe',
      'lsass.exe', 'fontdrvhost.exe', 'dwm.exe', 'svchost.exe', 'conhost.exe',
      'runtimebroker.exe', 'searchhost.exe', 'searchindexer.exe', 'searchprotocolhost.exe',
      'sihost.exe', 'ctfmon.exe', 'applicationframehost.exe', 'startmenuexperiencehost.exe',
      'shellexperiencehost.exe', 'taskhostw.exe', 'smartscreen.exe', 'audiodg.exe',
      'spoolsv.exe', 'wmiprvse.exe', 'backgroundtaskhost.exe', 'backgroundtransferhost.exe',
      'dllhost.exe', 'wudfhost.exe', 'nissrv.exe', 'msmpeng.exe', 'securityhealthservice.exe',
      'crashpad_handler.exe', 'vctip.exe', 'vssvc.exe', 'perfhost.exe',
      // PIXELLNET self:
      'pixellnet.exe', 'pixellnetagent.exe', 'hiddifycli.exe',
    };
    try {
      final result = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
      if (result.exitCode != 0) return {};
      final lines = (result.stdout as String).split(RegExp(r'\r?\n'));
      final processes = <String, AppPackageInfo>{};
      final matcher = RegExp(r'^"([^"]+)"');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final m = matcher.firstMatch(line);
        if (m == null) continue;
        final exe = m.group(1)!.trim();
        final key = exe.toLowerCase();
        if (hideSystem && systemExes.contains(key)) continue;
        if (processes.containsKey(key)) continue;
        final friendly = exe.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
        processes[key] = AppPackageInfo(packageName: exe, name: friendly, icon: null);
      }
      return processes.values.toSet();
    } catch (e) {
      loggy.warning('Windows tasklist failed', e);
      return {};
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final localizations = MaterialLocalizations.of(context);

    final mode = ref.watch(Preferences.perAppProxyMode).toAppProxy();
    final selectedApps = ref.watch(PerAppProxyProvider(mode));

    final hideSystemApps = useState(false);
    final isSearching = useState(false);
    final searchQuery = useState("");
    final sortListener = useState(false);

    final asyncApps = useFuture(useMemoized(() => getApps(false)));
    final asyncAppsHideSys = useFuture(useMemoized(() => getApps(true)));

    final asyncFilteredApps = hideSystemApps.value ? asyncAppsHideSys : asyncApps;

    final displayedApps = useMemoized<AsyncValue<List<AppPackageInfo>>>(
      () {
        if (!(selectedApps.hasValue &&
            selectedApps is AsyncData &&
            asyncFilteredApps.hasData &&
            asyncFilteredApps.connectionState == ConnectionState.done))
          return const AsyncValue.loading();
        final appsList = asyncFilteredApps.requireData.toList();
        if (searchQuery.value.isBlank) {
          appsList.sort((a, b) {
            final priorityA = _getPriority(a, selectedApps.requireValue);
            final priorityB = _getPriority(b, selectedApps.requireValue);
            return priorityA.compareTo(priorityB);
          });
          return AsyncValue.data(appsList);
        }
        final filteredAppsList = appsList
            .filter((e) => e.name.toLowerCase().contains(searchQuery.value.toLowerCase()))
            .toList();
        return AsyncValue.data(filteredAppsList);
      },
      [
        asyncFilteredApps.connectionState == ConnectionState.done,
        hideSystemApps.value,
        selectedApps.hasValue,
        searchQuery.value,
        sortListener.value,
      ],
    );

    if (mode != null) {
      ref.listen(PerAppProxyProvider(mode), (previous, next) {
        if (previous != null) {
          if ((previous, next) case (AsyncData(value: final prevData), AsyncData(value: final nextData))) {
            if (nextData.isNotEmpty) {
              if ((nextData.length - prevData.length).abs() > 1) sortListener.value = !sortListener.value;
            }
          }
        }
      });
    }

    final scrollController = useScrollController();
    const double scrollThreshold = 300.0;
    final showScrollToTop = useState<bool>(false);
    useEffect(() {
      void listener() {
        showScrollToTop.value = scrollController.offset > scrollThreshold;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, []);
    useEffect(() {
      showScrollToTop.value = false;
      return null;
    }, [displayedApps]);

    return Scaffold(
      appBar: isSearching.value
          ? AppBar(
              title: TextFormField(
                onChanged: (value) => searchQuery.value = value,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "${localizations.searchFieldLabel}...",
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              leading: IconButton(
                onPressed: () {
                  searchQuery.value = "";
                  isSearching.value = false;
                },
                icon: const Icon(Icons.close),
                tooltip: localizations.cancelButtonLabel,
              ),
            )
          : AppBar(
              title: Text(t.pages.settings.routing.generalOptions.perAppProxy.title),
              actions: [
                IconButton(
                  icon: const Icon(FluentIcons.search_24_regular),
                  onPressed: () => isSearching.value = true,
                  tooltip: localizations.searchFieldLabel,
                ),
                MenuAnchor(
                  menuChildren: <Widget>[
                    SubmenuButton(
                      menuChildren: <Widget>[
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.import.clipboard),
                          onPressed: () async => await ref
                              .read(dialogNotifierProvider.notifier)
                              .showConfirmation(
                                title: t.common.msg.import.confirm,
                                message: t.dialogs.confirmation.perAppProxy.import.msg,
                              )
                              .then((shouldImport) async {
                                if (shouldImport) await ref.read(PerAppProxyProvider(mode).notifier).importClipboard();
                              }),
                        ),
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.import.file),
                          onPressed: () async => await ref
                              .read(dialogNotifierProvider.notifier)
                              .showConfirmation(
                                title: t.pages.settings.routing.generalOptions.perAppProxy.options.import.file,
                                message: t.pages.settings.routing.generalOptions.perAppProxy.options.import.msg,
                              )
                              .then((shouldImport) async {
                                if (shouldImport) await ref.read(PerAppProxyProvider(mode).notifier).importFile();
                              }),
                        ),
                      ],
                      child: Text(t.common.import),
                    ),
                    SubmenuButton(
                      menuChildren: <Widget>[
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.export.clipboard),
                          onPressed: () async => await ref.read(PerAppProxyProvider(mode).notifier).exportClipboard(),
                        ),
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.export.file),
                          onPressed: () async => await ref.read(PerAppProxyProvider(mode).notifier).exportFile(),
                        ),
                      ],
                      child: Text(t.common.export),
                    ),
                    if (ref.watch(ConfigOptions.region) != Region.other)
                      MenuItemButton(
                        child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.shareToAll),
                        onPressed: () async => await ref
                            .read(appProxyLoadingProvider.notifier)
                            .doAsync(ref.read(PerAppProxyProvider(mode).notifier).shareOnGithub),
                      ),
                    const PopupMenuDivider(),
                    MenuItemButton(
                      child: Text(t.pages.settings.routing.generalOptions.perAppProxy.options.clearAllSelections),
                      onPressed: () => ref.read(PerAppProxyProvider(mode).notifier).clearAll(),
                    ),
                  ],
                  builder: (context, controller, child) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: ref.watch(appProxyLoadingProvider)
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator()),
                          )
                        : IconButton(
                            onPressed: () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                            icon: const Icon(Icons.more_vert_outlined),
                          ),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      PopupMenuButton(
                        borderRadius: BorderRadius.circular(8),
                        position: PopupMenuPosition.under,
                        tooltip: (mode?.toPerAppProxy() ?? PerAppProxyMode.off).present(t).message,
                        initialValue: mode?.toPerAppProxy() ?? PerAppProxyMode.off,
                        onSelected: (e) async {
                          if (ref.read(Preferences.autoAppsSelectionRegion) != null)
                            await ref.read(PerAppProxyProvider(mode).notifier).clearAutoSelected();
                          if (e == PerAppProxyMode.off && context.mounted) context.pop();
                          await ref.read(Preferences.perAppProxyMode.notifier).update(e);
                        },
                        itemBuilder: (context) => PerAppProxyMode.values
                            .map((e) => PopupMenuItem(value: e, child: Text(e.present(t).message)))
                            .toList(),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surface,
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              const Gap(16),
                              Text(mode?.present(t).title ?? ''),
                              const Gap(4),
                              Icon(Icons.arrow_drop_down_outlined, color: theme.colorScheme.onSurfaceVariant),
                              const Gap(8),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      ChoiceChip(
                        label: Text(t.pages.settings.routing.generalOptions.perAppProxy.hideSysApps),
                        selected: hideSystemApps.value,
                        onSelected: (value) => hideSystemApps.value = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: showScrollToTop.value
          ? FloatingActionButton(
              onPressed: () =>
                  scrollController.animateTo(0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut),
              child: const Icon(Icons.keyboard_arrow_up_outlined),
            )
          : (ref.watch(ConfigOptions.region) != Region.other)
          ? FloatingActionButton.extended(
              onPressed: () async =>
                  await ref.read(bottomSheetsNotifierProvider.notifier).showAutoAppsSelection(mode: mode!),
              label: Text(t.pages.settings.routing.generalOptions.perAppProxy.autoSelection.title),
              icon: Icon(
                ref.watch(Preferences.autoAppsSelectionRegion) == null
                    ? Icons.toggle_off_outlined
                    : Icons.toggle_on_outlined,
              ),
            )
          : null,
      body: displayedApps.when(
        data: (packages) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          controller: scrollController,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildExplanation(context, ref.watch(Preferences.perAppProxyMode));
            }
            final package = packages[index - 1];
            final flag = selectedApps.requireValue[package.packageName];
            return CheckboxListTile.adaptive(
              title: Row(
                children: [
                  Flexible(child: Text(package.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (flag != null && PkgFlag.forceDeselection.check(flag)) ...[
                    const Gap(6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                package.packageName,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              value: flag == null ? false : PkgFlag.checkboxValue(flag),
              tristate: true,
              onChanged: (_) => ref.read(PerAppProxyProvider(mode).notifier).updatePkg(package.packageName),
              secondary: package.icon == null
                  ? null
                  : Image.memory(package.icon!, width: 48, height: 48, cacheWidth: 48, cacheHeight: 48),
            );
          },
          itemCount: packages.length + 1,
        ),
        error: (error, _) => SliverErrorBodyPlaceholder(error.toString()),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildExplanation(BuildContext context, PerAppProxyMode mode) {
    final theme = Theme.of(context);
    final (title, hint) = switch (mode) {
      PerAppProxyMode.off => (
        'Все приложения через VPN',
        'VPN работает для всех программ. Нажмите на режим вверху ⋮, чтобы выбрать по-другому.',
      ),
      PerAppProxyMode.include => (
        'Только отмеченные приложения через VPN',
        'VPN работает только для отмеченных ✓ приложений. Остальные выходят в интернет напрямую.',
      ),
      PerAppProxyMode.exclude => (
        'Все приложения через VPN, кроме отмеченных',
        'Отмеченные ✓ приложения выходят в интернет напрямую (без VPN). Удобно для банков, госуслуг, Ozon — они часто блокируют VPN.',
      ),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
          const Gap(6),
          Text(hint, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
        ],
      ),
    );
  }
}
