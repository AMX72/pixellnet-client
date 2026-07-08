import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PIXELLNET — Главная (Sprint 2 radical simplification).
///
/// Держим ТРИ элемента (Hick-Hyman ≤ 5-7):
/// 1. Заголовок в AppBar (логотип + название)
/// 2. Connect button — единственный focal point, смещённый к низу
/// 3. Строка «Автовыбор · Матрица» + 🟢🟡🔴 качество
///
/// **Удалено** (per design consilium 2026-07-08):
/// - `TunToggleButton` в AppBar → в dev-menu (5-tap по версии)
/// - `ProfileTile` карточка активного профиля → в раздел Мой ключ
/// - Кнопка «+» add profile → в Настройки → Управление подпиской
/// - `ActiveProxyFooter` — traffic/counter → в Настройки → Статистика
/// - Bottom sheet «Быстрые настройки» — дублировал Настройки
/// - `AppVersionLabel` рядом с логотипом → в низ Настроек (5-tap разблокирует dev-menu)
class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text(t.common.appTitle),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'),
            fit: BoxFit.cover,
            opacity: 0.06,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(theme.colorScheme.onSurface.withValues(alpha: .12), BlendMode.srcIn)
                : ColorFilter.mode(theme.colorScheme.onSurface.withValues(alpha: .5), BlendMode.srcATop),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const Spacer(),
                const ConnectionButton(),
                const Gap(24),
                const ActiveProxyDelayIndicator(),
                const Spacer(),
                // Bottom offset per UX Ergonomics agent (Fitts's Law: mouse rests
                // near bottom-taskbar, Connect button reachable with least travel)
                const Gap(96),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
