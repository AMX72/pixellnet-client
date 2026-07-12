import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/trial/trial_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Быстрые настройки — упрощённый bottom-sheet для домохозяек.
///
/// Дизайн (синтез app-designer + vpn-product-manager + linguist):
/// - 1 карточка: «Убрать рекламу» (Switch, дефолт ON — value-driver)
/// - 2 карточка: «Осталось X дней» + «Продлить» (если trial ≤ 3 дня)
/// - Ссылка «Все настройки» → в существующий /settings
///
/// Убрано из quick (перенесено в существующий Settings):
/// - SegmentedButton Прокси/Системный/VPN (дефолт TUN везде, юзеру не понять)
/// - LAN sharing (нужно 3-5%, в advanced)
/// - Chain двойной прокси (жаргон, не для домохозяек)
class QuickSettingsModal extends HookConsumerWidget {
  const QuickSettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adBlock = ref.watch(Preferences.adBlockEnabled);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ручка сверху для свайпа
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Быстрые настройки',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Gap(4),
            Text('Основное в одном месте',
                style: theme.textTheme.bodySmall?.copyWith(color: PixellnetBrand.textSecondary)),
            const Gap(20),

            // Карточка 1 — убрать рекламу
            _SettingCard(
              icon: Icons.block_rounded,
              iconColor: PixellnetBrand.mocha,
              title: 'Убрать рекламу',
              subtitle: 'Меньше баннеров, сайты грузятся быстрее',
              trailing: Switch.adaptive(
                value: adBlock,
                onChanged: ref.read(Preferences.adBlockEnabled.notifier).update,
              ),
            ),
            const Gap(12),

            // Карточка 2 — trial-таймер + CTA (только когда trial активен)
            const _TrialCard(),

            const Gap(16),

            // Ссылка на полные настройки
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/settings');
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Все настройки'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Gap(2),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: PixellnetBrand.textSecondary, height: 1.3)),
              ],
            ),
          ),
          const Gap(8),
          trailing,
        ],
      ),
    );
  }
}

/// Trial-таймер + кнопка «Продлить». Показывается когда trial активен.
/// Скрыт если у юзера paid-подписка (пока проверяем только через
/// TrialService, в будущем — через отдельный billing state).
class _TrialCard extends HookConsumerWidget {
  const _TrialCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cached = useMemoized(() => TrialService.instance.loadCached(), []);
    final snapshot = useFuture(cached);
    final info = snapshot.data;
    if (info == null || info.isExpired) {
      return const SizedBox.shrink();
    }

    final daysLeft = info.daysLeft;
    final urgent = daysLeft <= 3;
    final accent = urgent ? PixellnetBrand.coralOnDark : PixellnetBrand.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.hourglass_top_rounded, color: accent, size: 22),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  daysLeft == 1 ? 'Остался 1 день пробного доступа' : 'Осталось $daysLeft дн. пробного доступа',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Gap(2),
                Text(
                  urgent
                      ? 'Скоро выключится. Продли, чтобы не потерять доступ.'
                      : 'Пользуйся сколько нужно.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: PixellnetBrand.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          const Gap(8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF1A1917),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: v0.1.15 — открыть paywall с планами тарифов
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Оплата скоро — уже верстаем ЛК')),
              );
            },
            child: const Text('Продлить'),
          ),
        ],
      ),
    );
  }
}
