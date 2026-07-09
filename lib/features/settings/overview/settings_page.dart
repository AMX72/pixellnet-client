import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

/// PIXELLNET Settings (Sprint 4): 3 уровня прогрессивного раскрытия.
///
/// **Уровень 1 — базовые** (95% юзеров): Общие настройки (язык, тема, автозапуск)
///
/// **Уровень 2 — Дополнительно** (expand-tile, для гиков): Логи, О приложении,
///  Управление конфигом (import/export/reset)
///
/// **Уровень 3 — dev-menu** (скрыто, 5 тапов по версии внизу): Маршрутизация,
/// DNS, Входящие, TLS-трюки, Цепь — вся технически-глубокая часть Hiddify.
///
/// Согласно design consilium 2026-07-08 (agent-app-designer + agent-linguist):
/// домохозяйка не должна видеть «Строгая маршрутизация», «Смешанный порт», «TLS-трюки»
/// в основных настройках. Только по явной разблокировке dev-меню.
class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion ?? '';

    // Sprint 4: dev-menu разблокировщик — 5 тапов подряд по строке версии.
    final devTapCount = useState<int>(0);
    final devMenuUnlocked = useState<bool>(false);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.title),
        actions: [
          if (devMenuUnlocked.value) _configMenuAnchor(context, ref, t),
          const Gap(8),
        ],
      ),
      body: ListView(
        children: [
          // ═══════ Уровень 1 — базовые ═══════
          _SectionHeader(text: 'Основные'),
          // Sprint 4.2: «Вставить ключ» поднят из «Дополнительно» в Уровень 1
          // (design consilium: редкая, но важная операция для домохозяйки — не прятать)
          ListTile(
            leading: const Icon(Icons.vpn_key_rounded),
            title: const Text('Вставить ключ'),
            subtitle: const Text('Скопируй ключ и нажми — разберёмся сами'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
          ),
          _SettingsTile(
            title: t.pages.settings.general.title,
            icon: Icons.tune_rounded,
            namedLocation: context.namedLocation('general'),
          ),

          // ═══════ Уровень 2 — Дополнительно ═══════
          const Gap(8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Дополнительно'),
              childrenPadding: const EdgeInsets.only(left: 8),
              children: [
                _SettingsTile(
                  title: t.pages.logs.title,
                  icon: Icons.description_outlined,
                  namedLocation: Breakpoint(context).isMobile()
                      ? context.namedLocation('logs')
                      : '/logs',
                ),
                _SettingsTile(
                  title: t.pages.about.title,
                  icon: Icons.info_outlined,
                  namedLocation: Breakpoint(context).isMobile()
                      ? context.namedLocation('about')
                      : '/about',
                ),
                if (PlatformUtils.isIOS)
                  ListTile(
                    title: Text(t.pages.settings.resetTunnel),
                    leading: const Icon(Icons.autorenew_outlined),
                    onTap: () async {
                      await ref.read(resetTunnelNotifierProvider.notifier).run();
                    },
                  ),
              ],
            ),
          ),

          // ═══════ Уровень 3 — dev-меню (скрыто до 5 тапов) ═══════
          if (devMenuUnlocked.value) ...[
            const Gap(8),
            _SectionHeader(text: 'Разработчику'),
            if (ref.watch(hasAnyProfileProvider).value ?? false)
              _SettingsTile(
                title: t.pages.settings.chain.title,
                icon: Icons.webhook_rounded,
                subtitle: t.pages.settings.chain.subtitle,
                namedLocation: context.namedLocation('chainOptions'),
              ),
            _SettingsTile(
              title: t.pages.settings.routing.title,
              icon: Icons.route_rounded,
              namedLocation: context.namedLocation('routingOptions'),
            ),
            _SettingsTile(
              title: t.pages.settings.dns.title,
              icon: Icons.dns_rounded,
              namedLocation: context.namedLocation('dnsOptions'),
            ),
            _SettingsTile(
              title: t.pages.settings.inbound.title,
              icon: Icons.input_rounded,
              namedLocation: context.namedLocation('inboundOptions'),
            ),
            _SettingsTile(
              title: t.pages.settings.tlsTricks.title,
              icon: Icons.content_cut_rounded,
              namedLocation: context.namedLocation('tlsTricks'),
            ),
          ],

          const Gap(24),

          // Строка версии с dev-menu-разблокировщиком
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (devMenuUnlocked.value) return;
                devTapCount.value += 1;
                if (devTapCount.value >= 5) {
                  devMenuUnlocked.value = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Режим разработчика включён'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Text(
                  devMenuUnlocked.value
                      ? 'Версия $version · режим разработчика'
                      : 'Версия $version',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          ),
          const Gap(16),
        ],
      ),
    );
  }

  Widget _configMenuAnchor(BuildContext context, WidgetRef ref, Translations t) {
    return MenuAnchor(
      menuChildren: <Widget>[
        SubmenuButton(
          menuChildren: <Widget>[
            MenuItemButton(
              onPressed: () async => await ref
                  .read(dialogNotifierProvider.notifier)
                  .showConfirmation(
                    title: t.common.msg.import.confirm,
                    message: t.dialogs.confirmation.settings.import.msg,
                  )
                  .then((shouldImport) async {
                    if (shouldImport) {
                      await ref.read(configOptionNotifierProvider.notifier).importFromClipboard();
                    }
                  }),
              child: Text(t.pages.settings.options.import.clipboard),
            ),
            MenuItemButton(
              onPressed: () async => await ref
                  .read(dialogNotifierProvider.notifier)
                  .showConfirmation(
                    title: t.common.msg.import.confirm,
                    message: t.dialogs.confirmation.settings.import.msg,
                  )
                  .then((shouldImport) async {
                    if (shouldImport) {
                      await ref.read(configOptionNotifierProvider.notifier).importFromJsonFile();
                    }
                  }),
              child: Text(t.pages.settings.options.import.file),
            ),
          ],
          child: Text(t.common.import),
        ),
        SubmenuButton(
          menuChildren: <Widget>[
            MenuItemButton(
              onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonClipboard(),
              child: Text(t.pages.settings.options.export.anonymousToClipboard),
            ),
            MenuItemButton(
              onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(),
              child: Text(t.pages.settings.options.export.anonymousToFile),
            ),
            const PopupMenuDivider(),
            MenuItemButton(
              onPressed: () async => await ref
                  .read(configOptionNotifierProvider.notifier)
                  .exportJsonClipboard(excludePrivate: false),
              child: Text(t.pages.settings.options.export.allToClipboard),
            ),
            MenuItemButton(
              onPressed: () async =>
                  await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(excludePrivate: false),
              child: Text(t.pages.settings.options.export.allToFile),
            ),
          ],
          child: Text(t.common.export),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          child: Text(t.pages.settings.options.reset),
          onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).resetOption(),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(namedLocation),
    );
  }
}
