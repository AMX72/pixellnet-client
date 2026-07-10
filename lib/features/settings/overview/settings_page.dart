import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/activation/notifier/trial_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/updater/update_dialog.dart';
import 'package:hiddify/features/updater/updater_service.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

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

/// PIXELLNET Settings (v0.0.45): 3 уровня прогрессивного раскрытия.
///
/// **Уровень 1** (95% юзеров):
///   - «Моя подписка» Card (состояние + CTA)
///   - «Само обновляется» Card (auto-update)
///   - «Если что-то не работает» (диагностика → логи)
///
/// **Уровень 2 — Дополнительно** (expand-tile):
///   - Полное логирование toggle (перенесён из Уровня 1)
///   - Макс. размер логов (перенесён из Уровня 1)
///   - О приложении
///   - Сброс туннеля (iOS only)
///
/// **Уровень 3 — dev-меню** (скрыто, 5 тапов по версии):
///   - Маршрутизация, DNS, Входящие, TLS-трюки, Цепь
class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion ?? '';

    // dev-menu разблокировщик — 5 тапов по строке версии
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
          // ═══════ «Моя подписка» Card (v0.0.45) ═══════
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child: Consumer(
              builder: (context, ref, _) {
                final trial = ref.watch(trialStateProvider);
                return _SubscriptionCard(state: trial);
              },
            ),
          ),

          const Gap(8),

          // ═══════ «Само обновляется» Card ═══════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final autoUpdate = ref.watch(autoUpdateEnabledProvider);
                      return SwitchListTile(
                        secondary: const Icon(Icons.system_update_rounded),
                        title: const Text('Само обновляется'),
                        subtitle: const Text('Обновляется в фоне'),
                        value: autoUpdate,
                        onChanged: (v) =>
                            ref.read(autoUpdateEnabledProvider.notifier).toggle(v),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Builder(
                    builder: (context) {
                      final ver =
                          ref.watch(appInfoProvider).valueOrNull?.presentVersion ?? '';
                      return ListTile(
                        leading: const Icon(Icons.search_rounded),
                        title: const Text('Проверить обновления сейчас'),
                        subtitle: ver.isNotEmpty ? Text('Текущая версия: $ver') : null,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        onTap: () async {
                          final info = await UpdaterService.instance
                              .checkForUpdate(force: true);
                          if (context.mounted) {
                            if (info != null) {
                              showDialog(
                                context: context,
                                builder: (_) => UpdateDialog(info: info),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Установлена последняя версия'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ═══════ Диагностика ═══════
          // v0.0.45: иконка bug → support_agent, subtitle сокращён
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Если что-то не работает'),
            subtitle: const Text('Журнал событий — поделись с поддержкой'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.pushNamed('logs'),
          ),

          // ═══════ Основные настройки ═══════
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
                // Verbose logging — перенесён из Уровня 1 (v0.0.45)
                Consumer(
                  builder: (context, ref, _) {
                    final verbose = ref.watch(verboseLoggingNotifierProvider);
                    return SwitchListTile(
                      secondary: const Icon(Icons.article_outlined),
                      title: const Text('Полное логирование'),
                      subtitle: const Text(
                        'Детальные события приложения. Включай только по просьбе поддержки.',
                      ),
                      value: verbose,
                      onChanged: (v) {
                        ref.read(verboseLoggingNotifierProvider.notifier).update(v);
                        // Sync с sing-box через MethodChannel (handler добавлен v0.0.37)
                        _syncVerboseToCore(v);
                      },
                    );
                  },
                ),
                // Макс. размер логов — перенесён из Уровня 1 (v0.0.45)
                Consumer(
                  builder: (context, ref, _) {
                    final limit = ref.watch(logSizeLimitNotifierProvider);
                    return ListTile(
                      leading: const Icon(Icons.storage_outlined),
                      title: const Text('Макс. размер журнала'),
                      subtitle: Text('$limit МБ (старая половина удаляется при превышении)'),
                      trailing: DropdownButton<int>(
                        value: limit,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 10, child: Text('10 МБ')),
                          DropdownMenuItem(value: 50, child: Text('50 МБ')),
                          DropdownMenuItem(value: 100, child: Text('100 МБ')),
                          DropdownMenuItem(value: 200, child: Text('200 МБ')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            ref.read(logSizeLimitNotifierProvider.notifier).update(v);
                          }
                        },
                      ),
                    );
                  },
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

/// Sync verbose flag с sing-box через MethodChannel.
/// Kotlin-handler `set_verbose_logging` добавлен в v0.0.37.
void _syncVerboseToCore(bool verbose) {
  // Используем fire-and-forget: если канал недоступен (не Android) — игнорируем
  try {
    const channel = MethodChannel('pixellnet/core');
    channel.invokeMethod<void>('set_verbose_logging', {'enabled': verbose});
  } catch (_) {
    // Desktop/iOS: канал не зарегистрирован — нормально
  }
}

// ── «Моя подписка» Card ──────────────────────────────────────────────────────

/// v0.0.45: Карточка статуса подписки в топе Настроек.
/// Читает [trialStateProvider], отображает статус + CTA.
class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({required this.state});

  final TrialState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    void openKeySheet() =>
        ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (state) {
          TrialNotActivated() => _SubscriptionRow(
              icon: Icons.key_off_outlined,
              iconColor: scheme.error,
              title: 'Нет подписки',
              subtitle: 'Введи ключ чтобы начать',
              ctaLabel: 'Ввести ключ',
              ctaFilled: true,
              onCta: openKeySheet,
            ),
          TrialActivating() => _SubscriptionRow(
              icon: Icons.hourglass_top_rounded,
              iconColor: scheme.tertiary,
              title: 'Активация...',
              subtitle: 'Подождите',
              ctaLabel: null,
              ctaFilled: false,
              onCta: null,
            ),
          TrialActive(
            :final daysLeft,
            :final isExpired,
            :final isTrial,
            :final expiresAt,
          ) =>
            _SubscriptionRow(
              icon: isExpired ? Icons.warning_amber_rounded : Icons.verified_rounded,
              iconColor: isExpired ? scheme.error : scheme.primary,
              title: isExpired
                  ? 'Подписка истекла'
                  : (isTrial ? 'Пробный период' : 'Подписка активна'),
              subtitle: isExpired
                  ? 'Истекла ${_formatDate(expiresAt)}'
                  : 'Ещё $daysLeft ${_pluralDays(daysLeft)} · до ${_formatDate(expiresAt)}',
              ctaLabel: isExpired ? 'Продлить' : (isTrial ? 'Оплатить' : 'Продлить'),
              ctaFilled: isExpired,
              onCta: () {
                // Открываем WebView или браузер на страницу оплаты
                UriUtils.tryLaunch(Uri.parse('https://pixellnet.com/pay'));
              },
            ),
          TrialError(:final message) => _SubscriptionRow(
              icon: Icons.error_outline_rounded,
              iconColor: scheme.error,
              title: 'Ошибка активации',
              subtitle: message,
              ctaLabel: 'Попробовать снова',
              ctaFilled: false,
              onCta: openKeySheet,
            ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('d MMMM yyyy', 'ru').format(dt);
  }

  String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.ctaFilled,
    required this.onCta,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final bool ctaFilled;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 32),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (ctaLabel != null) ...[
          const Gap(8),
          ctaFilled
              ? FilledButton(onPressed: onCta, child: Text(ctaLabel!))
              : OutlinedButton(onPressed: onCta, child: Text(ctaLabel!)),
        ],
      ],
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────────

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
