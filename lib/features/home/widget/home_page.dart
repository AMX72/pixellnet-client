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
                        // const Gap(100),
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

/// Info-strip: тонкая техническая строка `DE · 45ms · Reality · ↑2.3 ↓15 MB`.
///
/// Дизайн (app-designer bimodal spec): 11sp Mono muted alpha 55% — домохозяйка
/// её не замечает (как EXIF), IT-юзер сразу видит всё нужное. Тап открывает
/// session-sheet с deep telemetry. Long-press копирует в буфер обмена.
class _InfoStrip extends ConsumerWidget {
  const _InfoStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    if (connection is! Connected) return const SizedBox.shrink();

    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    if (active == null) return const SizedBox.shrink();

    final delay = active.urlTestDelay;
    final delayText = delay > 0 && delay < 65000 ? '${delay}ms' : '—';
    final name = active.tagDisplay.isNotEmpty
        ? active.tagDisplay
        : (active.tag.isNotEmpty ? active.tag : '—');
    final protocol = active.type.isNotEmpty ? active.type : '';
    final up = _formatBytes(active.upload.toInt());
    final down = _formatBytes(active.download.toInt());
    final parts = [
      name,
      delayText,
      if (protocol.isNotEmpty) protocol,
      if (up.isNotEmpty || down.isNotEmpty) '↑$up ↓$down',
    ];
    final line = parts.join(' · ');

    return GestureDetector(
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

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
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
