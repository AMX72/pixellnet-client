import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/updater/auto_update_notifier.dart';
import 'package:hiddify/features/updater/update_dialog.dart';
import 'package:hiddify/features/updater/updater_service.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/trial/auto_trial_provider.dart';
import 'package:hiddify/features/trial/trial_service.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    // final hasAnyProfile = ref.watch(hasAnyProfileProvider);
    final activeProfile = ref.watch(activeProfileProvider);
    // Zero-config: при первом запуске автоматически получаем trial через
    // pixellnet-api и импортируем как активный профиль. Если у юзера уже
    // есть профиль — провайдер вернёт null и ничего не сделает.
    final autoTrial = ref.watch(autoTrialProvider);
    // v0.1.26: активация тихой автопроверки обновлений при первом mount Home.
    ref.watch(autoUpdateStateProvider);

    return Scaffold(
      appBar: AppBar(
        // leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) && showDrawerButton(context)
        //     ? DrawerButton(
        //         onPressed: () {
        //           RootScaffold.stateKey.currentState?.openDrawer();
        //         },
        //       )
        //     : null,
        // v0.1.19: bimodal spec — чистый AppBar только с логотипом и названием.
        // Убрано: «+» кнопка (импорт ключа переехал в «Ключи»), version chip.
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text(t.common.appTitle, style: const TextStyle(letterSpacing: 1.2)),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'), // Replace with your image path
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn) //
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ), // Apply white tint in dark mode
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600, // Set the maximum width here
                ),
                child: CustomScrollView(
                  slivers: [
                    // switch (activeProfile) {
                    // AsyncData(value: final profile?) =>
                    MultiSliver(
                      children: [
                        // v0.1.26: banner «Есть свежая версия» — над всем.
                        // Подхватывается автопроверкой; тап → скачать/установить.
                        const SliverToBoxAdapter(child: _UpdateAvailableBanner()),
                        // v0.1.26: banner «Обновлено до X · Что нового →»
                        // Показывается 3 дня после успешной установки.
                        const SliverToBoxAdapter(child: _PostUpdateBanner()),
                        switch (activeProfile) {
                          AsyncData(value: final profile?) => ProfileTile(
                            profile: profile,
                            isMain: true,
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          _ => const Text(""),
                        },
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [ConnectionButton(), ActiveProxyDelayIndicator()],
                                ),
                              ),
                              ActiveProxyFooter(),
                              Gap(32),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // AsyncData() => switch (hasAnyProfile) {
                    //     AsyncData(value: true) => const EmptyActiveProfileHomeBody(),
                    //     _ => const EmptyProfilesHomeBody(),
                    //   },
                    // AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                    // _ => const SliverToBoxAdapter(),
                    // },
                  ],
                ),
              ),
            ),
            // Zero-config auto-trial overlay: показывается пока идёт запрос
            // на pixellnet-api /api/trial при первом запуске.
            if (autoTrial.isLoading)
              Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
                    const Gap(24),
                    Text('Готовим ваш пробный период (7 дней)',
                        style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                    const Gap(8),
                    Text('Одна секунда, и всё готово',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            if (autoTrial.hasError)
              Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.error),
                    const Gap(16),
                    Text('Не получилось создать пробный доступ',
                        style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                    const Gap(8),
                    Text(
                      autoTrial.error is TrialException
                          ? (autoTrial.error as TrialException).message
                          : 'Проверь интернет и попробуй снова',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const Gap(24),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                      onPressed: () => ref.invalidate(autoTrialProvider),
                    ),
                  ],
                ),
              ),
            // v0.1.19: bimodal spec — тонкий info-strip внизу для IT-юзеров.
            // 11sp Mono muted — домохозяйке не мешает (как EXIF под фото),
            // IT-юзер сразу видит нужное: страна, ping, protocol, трафик.
            // Тап → та же логика что server card (открывает детали).
            if (ref.watch(hasAnyProfileProvider).value ?? false)
              const Positioned(
                left: 16,
                right: 16,
                bottom: 8,
                child: _InfoStrip(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Info-strip с live-скоростью: `Gandalf · 45ms · vless · ↑12KB/s ↓340KB/s`.
///
/// Дизайн (app-designer bimodal spec): 11sp Mono muted alpha 55% — домохозяйка
/// не замечает (как EXIF), IT-юзер сразу видит нужное. Обновляется каждую
/// секунду через Timer.periodic, скорость вычисляется как delta upload/
/// download от предыдущего тика. Long-press копирует в буфер обмена.
class _InfoStrip extends ConsumerStatefulWidget {
  const _InfoStrip();

  @override
  ConsumerState<_InfoStrip> createState() => _InfoStripState();
}

class _InfoStripState extends ConsumerState<_InfoStrip> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    if (connection is! Connected) return const SizedBox.shrink();

    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    if (active == null) return const SizedBox.shrink();

    // v0.1.25: скорости из SystemInfo.uplink/downlink (bytes/sec от sing-box
    // core через gRPC). Раньше вычислял delta от active.upload вручную —
    // не работало потому что active.upload = cumulative от group-outbound,
    // не активной сессии. Восстановлено из baseline v0.1.0 stats-модуль.
    final stats = ref.watch(statsNotifierProvider).valueOrNull;
    final upSpeed = (stats?.uplink.toInt() ?? 0).toDouble();
    final downSpeed = (stats?.downlink.toInt() ?? 0).toDouble();

    final delay = active.urlTestDelay;
    final delayText = delay > 0 && delay < 65000 ? '${delay}ms' : '—';
    final name = active.tagDisplay.isNotEmpty
        ? active.tagDisplay
        : (active.tag.isNotEmpty ? active.tag : '—');
    final protocol = active.type.isNotEmpty ? active.type : '';
    final speedPart = '↑${_formatSpeed(upSpeed)} ↓${_formatSpeed(downSpeed)}';
    final parts = [
      name,
      delayText,
      if (protocol.isNotEmpty) protocol,
      speedPart,
    ];
    final line = parts.join(' · ');

    return GestureDetector(
      // Тап → session sheet с деталями (v0.1.22)
      onTap: () => _showSessionSheet(context, active, upSpeed, downSpeed),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: line));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано')),
        );
      },
      child: Text(
        line,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 11,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toInt()}B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  void _showSessionSheet(BuildContext context, OutboundInfo active, double up, double down) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final rows = <(String, String)>[
          ('Канал', active.tagDisplay.isNotEmpty ? active.tagDisplay : active.tag),
          ('Страна', active.ipinfo.countryCode.isNotEmpty ? active.ipinfo.countryCode : '—'),
          ('IP выходной',
              active.ipinfo.ip.isNotEmpty ? active.ipinfo.ip : '—'),
          ('Провайдер (ASN)',
              active.ipinfo.org.isNotEmpty ? active.ipinfo.org : '—'),
          ('Протокол', active.type.isNotEmpty ? active.type : '—'),
          ('Задержка',
              active.urlTestDelay > 0 && active.urlTestDelay < 65000
                  ? '${active.urlTestDelay} мс'
                  : '—'),
          ('Скорость сейчас',
              '↑${_formatSpeed(up)}  ↓${_formatSpeed(down)}'),
          ('Всего за сессию',
              '↑${_bytes(active.upload.toInt())}  ↓${_bytes(active.download.toInt())}'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Сессия',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Gap(4),
                Text('Технические детали текущего соединения',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Gap(16),
                for (final r in rows) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(r.$1,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 7,
                        child: Text(r.$2,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Consolas')),
                      ),
                    ],
                  ),
                  const Gap(10),
                ],
                const Gap(8),
                FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Скопировать для поддержки'),
                  onPressed: () async {
                    final text = rows.map((r) => '${r.$1}: ${r.$2}').join('\n');
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _bytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

/// v0.1.26: Banner «Есть свежая версия» на Home.
/// Синтез app-designer + linguist: короткий title + одна CTA + крестик.
/// Тап на текст = скачать сразу, крестик = скрыть на 3 дня.
class _UpdateAvailableBanner extends ConsumerWidget {
  const _UpdateAvailableBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoUpdateStateProvider);
    if (!state.shouldShowBanner) return const SizedBox.shrink();
    final info = state.available!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: PixellnetBrand.mocha.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => UpdateDialog(info: info),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded,
                    color: PixellnetBrand.mochaOnDark, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Есть свежая версия · ${info.version}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: PixellnetBrand.mochaOnDark,
                    ),
                  ),
                ),
                Text('Обновить',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: PixellnetBrand.mochaOnDark,
                        fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: PixellnetBrand.textSecondary,
                  tooltip: 'Скрыть на 3 дня',
                  onPressed: () =>
                      ref.read(autoUpdateStateProvider.notifier).dismissBanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// v0.1.26: Post-update banner «Обновлено до X · Что нового →».
/// Показывается 3 дня после установки. Читает Preferences.lastInstalledAt.
class _PostUpdateBanner extends ConsumerWidget {
  const _PostUpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(Preferences.lastInstalledAt);
    final version = ref.watch(Preferences.lastInstalledVersion);
    if (ts == 0 || version.isEmpty) return const SizedBox.shrink();

    // Показываем не дольше 3 дней после установки.
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - ts;
    if (ageMs > const Duration(days: 3).inMilliseconds) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: PixellnetBrand.olive.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // TODO v0.1.27: показать changelog для этой версии
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Обновлено до $version')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: PixellnetBrand.olive, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Обновлено до $version',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: PixellnetBrand.olive,
                    ),
                  ),
                ),
                Text('Что нового →',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: PixellnetBrand.olive, fontWeight: FontWeight.w700)),
                const Gap(4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: PixellnetBrand.textSecondary,
                  tooltip: 'Скрыть',
                  onPressed: () async {
                    await ref.read(Preferences.lastInstalledAt.notifier).update(0);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
