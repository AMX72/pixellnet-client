import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PIXELLNET quality indicator (Sprint 2.5): цветной кружок + строка «Автовыбор · Канал».
///
/// Заменяет старый показ мс (агент-linguist: домохозяйка не понимает «47ms»).
/// Цветовая семантика — олива/янтарь/коралл (semantic tokens из palette v3):
/// - 🟢 delay ≤ 150ms: «Отлично» — success (олива)
/// - 🟡 delay 150–500ms: «Нормально» — warning (янтарь)
/// - 🔴 delay > 500ms or timeout: «Плохо» — danger (коралл)
///
/// При тапе — запускает urltest.
class ActiveProxyDelayIndicator extends HookConsumerWidget with InfraLogger {
  const ActiveProxyDelayIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final theme = Theme.of(context);

    if (activeProxy is! AsyncData) return const SizedBox();

    final proxy = activeProxy.value!;
    final delay = proxy.urlTestDelay;
    final tag = proxy.tagDisplay.isNotEmpty ? proxy.tagDisplay : proxy.tag;
    final isTimeout = delay > 65000;
    final isTesting = delay <= 0;

    final ({Color color, String label, String tooltip}) quality = switch (delay) {
      _ when isTesting => (
        color: PixellnetColors.warning,
        label: 'Проверяем…',
        tooltip: 'Измеряем качество соединения',
      ),
      _ when isTimeout => (
        color: PixellnetColors.danger,
        label: 'Плохо',
        tooltip: 'Сайты открываются с трудом. Нажмите — попробуем снова',
      ),
      _ when delay > 500 => (
        color: PixellnetColors.danger,
        label: 'Плохо',
        tooltip: 'Соединение медленное',
      ),
      _ when delay > 150 => (
        color: PixellnetColors.warning,
        label: 'Нормально',
        tooltip: 'Работает, но иногда медленно',
      ),
      _ => (
        color: PixellnetColors.success,
        label: 'Отлично',
        tooltip: 'Всё работает быстро',
      ),
    };

    return Tooltip(
      message: quality.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          try {
            await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
          } catch (e) {
            loggy.error("Error during URL test: $e");
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Цветной кружок качества
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: quality.color,
                  shape: BoxShape.circle,
                ),
              ),
              const Gap(10),
              Text(
                quality.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (tag.isNotEmpty) ...[
                Text(
                  ' · $tag',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
